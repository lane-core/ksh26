# sfio: Buffered I/O Substrate

ksh26's I/O layer — inherited from AT&T's sfio (Safe/Fast I/O), slated
for clean-room reimplementation. 39 of 77 exported functions used by ksh.

## Purpose

Behavioral contracts for the sfio buffered I/O substrate used by ksh26.

**Status**: Architecture documented, implementation not started.

**Source material**: [sfio-rewrite-v2.md](../../notes/sfio-rewrite-v2.md),
[sfio-analysis/](../../notes/sfio-analysis/) (12-file contract corpus),
[REDESIGN.md §sfio reimplementation](../../REDESIGN.md#sfio-reimplementation).
**Theory**: [SPEC.md §Tightening the analogies](../../SPEC.md#tightening-the-analogies).


## Requirements

### Requirement: Same API, new code

The reimplementation SHALL be a drop-in replacement: same `sfio.h` header,
same `Sfio_t` type, same sf* function names. Zero changes to ksh call
sites. The current `src/lib/libast/sfio/` directory (~42 files after
legacy reduction from original 78) SHALL be replaced by ~7 source files
(~2,600 LOC).

**Source**: sfio-rewrite-v2.md §Strategy

#### Scenario: Zero call site changes
`git diff` between pre-swap and post-swap shows no changes outside
`src/lib/libast/sfio/`, `sfio.h`, `sfhdr.h`, and `configure.sh`.


### Requirement: Five-pointer buffer invariant

In steady state, Sfio_t buffer pointers SHALL satisfy:
`_data ≤ _next ≤ min(_endr, _endw) ≤ _endb`

Intermediate violations occur during mode transitions and lock states.
Every buffer-manipulating function MUST restore this before returning.

**Polarity**: Boundary (mediates value/computation modes)
**Source**: sfio.h:Sfio_t, sfio-analysis/03-buffer-model.md
**Hazard**: No assertion exists in legacy sfio. The reimplementation
should add `sfio_check(f)` in debug builds.

#### Scenario: Debug assertion
Debug builds include a buffer invariant check after every public function.


### Requirement: Three flag namespaces

Sfio_t SHALL separate public flags, private bits, and mode flags into
distinct typed fields. Public flags (`_flags`, `unsigned short`), private
bits (`bits`, `unsigned short`), and mode flags (`mode`, `unsigned int`)
SHALL live
in different `Sfio_t` fields. The reimplementation SHALL use C23 typed
enums to make cross-namespace mixing a compile-time error.

**Source**: sfio.h, sfio-analysis/02-flags-and-modes.md

#### Scenario: Typed enums prevent cross-namespace assignment
Assigning a mode flag to a public flag field produces a compiler diagnostic.


### Requirement: sfreserve calling patterns

sfreserve SHALL support 5+ distinct calling patterns:

| Pattern | Call | Behavior |
|---------|------|----------|
| Peek availability | `sfreserve(f, 0, 0)` | Fill if empty, return ptr, do NOT advance f->next |
| Peek/lock | `sfreserve(f, SF_UNBOUND, SF_LOCKR)` | Fill, return ptr, set PEEK mode (release via sfread(f,buf,0)) |
| Consume | `sfreserve(f, SF_UNBOUND, 0)` | Fill, return ptr, advance f->next by available |
| Reserve N | `sfreserve(f, n, SF_LOCKR)` | Ensure ≥n bytes, return ptr, set PEEK |
| Assess | `sfreserve(f, -size, SF_LOCKR)` | Negative size with special handling |

**Polarity**: Negative (consumer — demands data)
**Source**: sfio-rewrite-v2.md §The sfreserve contract
**Hazard**: This is where v1 failed. All 5 patterns must be independently
unit-tested before integration.

#### Scenario: 5-pattern test coverage
Each calling pattern has a dedicated test exercising its specific
semantics (ptr return, f->next advancement, PEEK state).


### Requirement: LOCKR protocol (thunk structure)

`sfreserve(..., SF_LOCKR)` SHALL suspend the stream's fill machinery into
a storable value (pointer + length). The releasing `sfread(f, buf, 0)` or
`sfwrite(f, buf, 0)` SHALL force the thunk (resume computation by
releasing the lock).

The stream is genuinely frozen until explicitly released — lazy, not eager.

**Polarity**: Negative→Shift (has ↓N thunk structure)
**Source**: sfio-analysis/04-read-path.md §sfreserve, sfio-rewrite-v2.md §C1

#### Scenario: LOCKR freeze
Between sfreserve(LOCKR) and sfread(f,buf,0), no other sfio operation
on the same stream shall succeed.


### Requirement: sfprintf %! format engine

`sfvprintf` SHALL support the `%!` extension protocol:
1. Parse format string until `%!` encountered
2. Read `Sffmt_t*` from va_args
3. If `ft->form` is set, push format context
4. For each `%` directive, call `ft->extf(f, &argv, ft)`
5. extf return: <0 = pop, >0 = extf already wrote, 0 = use argv

Standard specifiers (d/i/o/u/x/s/c/p/f/e/g) SHALL delegate to libc
`vsnprintf`. The reimplementation handles only the %!/extf protocol.

**Polarity**: Positive + Shift (format + extf callback)
**Source**: sfio-rewrite-v2.md §The sfprintf/%! format engine
**Hazard**: ~48/57 test files exercise printf → sfprintf. Subtle
interactions with format context stacking.

#### Scenario: ksh printf builtin
`print -f '%d %s' 42 hello` produces `42 hello` through sfvprintf.


### Requirement: Discipline system (Dccache)

Disciplines SHALL be a push/pop linked list dispatching read/write/seek/
except through the chain. When data is buffered and a new discipline is
pushed, buffered data MUST be saved and replayed through the new
discipline (Dccache).

Dccache is the non-associativity witness: the composition equation
`(h ○ g) • f ≠ h ○ (g • f)` — data that crossed to value mode cannot
be re-processed through a new context.

**Polarity**: Interception (boundary between buffer and OS)
**Source**: sfio-rewrite-v2.md §C2, sfio-analysis/07-disciplines.md

#### Scenario: Discipline push with buffered data
Pushing a discipline while data is buffered replays that data through
the new discipline on the next read.


### Requirement: _sfmode state machine

`_sfmode()` SHALL run at every operation entry, mediating between the
stream's current state and the caller's expected polarity:
1. GETR restore: if `f->mode & SF_GETR`, restore `f->next[-1] = f->getr`
2. Mode switch: WRITE→READ or READ→WRITE
3. Initialization: if SF_INIT, allocate buffer
4. Pool management: if SF_POOL, move to head
5. Lock acquisition

**Polarity**: Shift mediator
**Source**: sfio-rewrite-v2.md §The _sfmode state machine

#### Scenario: Mode transition correctness
Writing then reading the same stream (without explicit seek) produces
correct data.


### Requirement: NUL sentinel — sfio does NOT guarantee

No sfio write function SHALL write `*_next = 0` as a postcondition. The
stk allocator provides its own NUL sentinel via `STK_SENTINEL`. Adding
a sentinel to sfio write functions would break stk's `_stkseek`.

**Source**: sfio-analysis/05-write-path.md §NUL sentinel contract

#### Scenario: sfwrite does not NUL-terminate
After `sfwrite(f, "abc", 3)`, `f->next[0]` is not guaranteed to be `\0`.


### Requirement: ksh integration architecture

The reimplementation SHALL fire the same notification events as legacy
sfio at the same lifecycle points. ksh maintains three parallel arrays
(`sh.sftable`, `sh.fdstatus`, `sh.fdptrs`) grown atomically by
`sh_iovalidfd()`. `sftrack()` (via `sfnotify`) keeps them in sync. The
reimplementation MUST fire the same
notification events at the same lifecycle points.

**Source**: sfio-rewrite-v2.md §B11, sfio-analysis/10-ksh-integration.md

#### Scenario: sfnotify fires on open/close/dup
Opening, closing, and duping a stream fires the notification callback
with the correct fd and event type.


### Requirement: Existing regression test coverage

The sfio regression tests (`tests/infra/sfio/sfio_test.c`) SHALL
continue to pass through the rewrite. They exercise the core contracts:

| Test | Contract exercised |
|------|-------------------|
| sfreserve (3 patterns) | sfreserve calling patterns (peek, lock, consume) |
| sfgetr | Record reading + GETR destructive NUL |
| sfputl/sfgetl roundtrip | VLE signed encoding |
| sfputu/sfgetu roundtrip | VLE unsigned encoding |
| sfprintf | Format engine + %! protocol |
| String seek | String stream positioning |
| sfstack | Stream stack operations |
| NUL sentinel | NUL sentinel contract (sfio does NOT guarantee) |
| sfputd/sfgetd roundtrip | VLE double encoding — **disabled** (precision loss from 7-bit mantissa encoding) |

**Source**: tests/infra/sfio/sfio_test.c, sfio-reduction-report.md §Gating

#### Scenario: Regression tests pass after rewrite
`just test-iffe` passes all sfio contract regression tests with the
reimplemented code.


### Requirement: Surviving dependencies

The reimplementation SHALL preserve compatibility with these legacy
dependencies that survive the rewrite:

- `sfstrtof.h` MUST remain available — `comp/strtod.c` and
  `comp/strtold.c` include it for `_ast_strtold`/`_ast_strtod`, which
  ksh actively calls (test.c, print.c, arith.c via AST's strtold remap)
- sfio/mmap feature probe outputs (`_ptr_bits`, `_tmp_rmfail`,
  `_more_void_int`, `_more_long_int`, `_mmap_worthy`) MUST remain
  available — actively used by sfhdr.h, sflife.c, sfvprintf.c, sfseek.c
- `sfdcfilter.c` MUST remain excluded from the build (depends on deleted
  sfpopen; excluded via `-not -name 'sfdcfilter.c'` in configure.sh)

**Source**: sfio-reduction-report.md §What Was NOT Changed, §Build System Changes
**Hazard**: N_ARRAY macro is `#define`d with different values across
encoding files (256 for double, 16 for long/ulong). Consolidation
into a single file requires `#undef N_ARRAY` between sections.

#### Scenario: sfstrtof.h survives rewrite
After the swap, `comp/strtod.c` still compiles and `_ast_strtold` is
still available to ksh.


## File layout (reimplementation)

| File | Polarity role | Functions | Est. lines |
|------|---------------|-----------|------------|
| sfmode.c | Shift mediator | _sfmode, sfsetbuf, sfclrlock, _sfsetpool, _sfcleanup | ~250 |
| sfread.c | Negative (consumers) | sfrd, _sffilbuf, sfread, sfreserve, sfgetr, sfungetc, sfpkrd, sfmove, _sfrsrv | ~500 |
| sfwrite.c | Positive (producers) | sfwr, _sfflsbuf, sfwrite, sfputr, sfnputc | ~350 |
| sfdisc.c | Interception | sfdisc, _sfexcept, sfraise, Dccache_t | ~200 |
| sflife.c | Cuts (lifecycle) | sfnew, sfopen, sfclose, sfstack, sfswap, sfsetfd, sfsetfd_cloexec, sfset, sfseek, sftell, sfsize, sfsync, sfpurge, sftmp, sfpool, sfnotify | ~450 |
| sfvprintf.c | Positive + shift (format) | sfvprintf, sfprintf, sfprints, format tables | ~700 |
| sfvle.c | Neutral (encoding) | sfputl/sfgetl, sfputu/sfgetu, sfputd/sfgetd, sfputm/sfgetm | ~150 |


## Success criteria

1. `just build && just test` passes (≥114 stamps, ≥110 gate)
2. `just build-asan` is clean
3. sfio/ directory deleted from libast
4. Total I/O code: ≤3,500 lines (vs ~12,800)
5. Zero changes to ksh call sites
6. All fd creation uses POSIX Issue 8 atomic primitives where available

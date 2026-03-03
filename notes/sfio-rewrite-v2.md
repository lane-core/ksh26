# sfio Rewrite v2: Clean Reimplementation

## Premise

The Direction 12 failure analysis (see `sfio-rewrite-failure-analysis.md`)
established that the problem was "replace sfio with stdio" rather than
"provide ksh's I/O semantics cleanly." This proposal takes the second
approach: reimplement sfio's contracts from scratch in modern C, keeping
the same API surface that ksh expects, but without sfio's legacy
complexity.

sfio is ~12,800 lines across 78 files. ksh uses 39 of 77 exported
functions (plus `sfsetfd_cloexec`, a ksh26 extension). A clean
reimplementation targeting only what ksh needs should be ~2,600 lines
across 7 source files, plus headers with 11 `static inline` entry
points.

## Rollback point

**Complete.** main is at v0.0.1 + cherry-picked infrastructure.
115/115 tests pass. All stdio-specific build/test/CI infrastructure
has been removed (justfile, flake.nix, configure.sh --stdio flag).

## Strategy: don't abstract, reimplement

v1 tried to create an abstraction layer between ksh and sfio, then
provide alternate backends. This added complexity (two code paths,
shim headers, conditional compilation) without reducing the contract
surface ksh depends on.

v2 takes the opposite approach: **one implementation, same API names,
same semantics, new code.** The result is a drop-in replacement for
`src/lib/libast/sfio/` — same `sfio.h` header, same `Sfio_t` type,
same sf\* functions — but implemented in ~2,600 lines instead of ~13K.

This means:
- Zero changes to ksh call sites
- Zero abstraction layers or conditional compilation
- The old sfio directory is deleted and replaced
- libast's non-sfio code (CDT, stk, optget, error, etc.) continues
  to work because the API is identical


## Polarity architecture

sfio's functions map naturally to the duploid polarity framework from
SPEC.md. Rather than organizing by implementation priority (tier 1/2/3),
the reimplementation organizes source files by **polarity role** — what
each function *is* in the structural vocabulary.

### File layout

| File | Polarity role | Functions | Est. lines |
|------|---------------|-----------|------------|
| `sfmode.c` | **Shift mediator** | `_sfmode`, `sfsetbuf`, `sfclrlock`, `_sfsetpool`, `_sfcleanup` | ~250 |
| `sfread.c` | **Negative (consumers)** | `sfrd`, `_sffilbuf`, `sfread`, `sfreserve`, `sfgetr`, `sfungetc`, `sfpkrd`, `sfmove`, `_sfrsrv` | ~500 |
| `sfwrite.c` | **Positive (producers)** | `sfwr`, `_sfflsbuf`, `sfwrite`, `sfputr`, `sfnputc` | ~350 |
| `sfdisc.c` | **Interception layer** | `sfdisc`, `_sfexcept`, `sfraise`, `Dccache_t` | ~200 |
| `sflife.c` | **Cuts (lifecycle/identity)** | `sfnew`, `sfopen`, `sfclose`, `sfstack`, `sfswap`, `sfsetfd`, `sfsetfd_cloexec`, `sfset`, `sfseek`, `sftell`, `sfsize`, `sfsync`, `sfpurge`, `sftmp`, `sfpool`, `sfnotify` | ~450 |
| `sfvprintf.c` | **Positive + shift (format)** | `sfvprintf`, `sfprintf`, `sfprints`, format tables | ~700 |
| `sfvle.c` | **Neutral (encoding)** | `sfputl/sfgetl`, `sfputu/sfgetu`, `sfputd/sfgetd`, `sfputm/sfgetm` | ~150 |
| **Total** | | **40 exported + 9 internal** | **~2,600** |

Plus headers:
- `sfio.h` (public, ~200 lines)
- `sfhdr.h` (internal, ~250 lines)

### Role descriptions

**Shift mediator** (`sfmode.c`): `_sfmode()` runs at every operation
entry. It mediates between the stream's current state and the caller's
expected polarity. GETR restore (`f->next[-1] = f->getr`) undoes STRING
mode observation. Mode transitions (WRITE→READ, READ→WRITE) are polarity
boundary crossings — the function's entire purpose is managing these
shifts.

**Negative polarity** (`sfread.c`): Operations that observe/demand data.
The LOCKR protocol creates thunks (↓N: suspend computation into storable
value). `sfreserve(..., SF_LOCKR)` suspends; `sfread(f,buf,0)` forces.
Every function here demands data from below (fd or discipline chain) and
presents it upward as a value (pointer, record, byte).

**Positive polarity** (`sfwrite.c`): Operations that produce data.
String stream buffer extension is a positive operation triggering a cut
(buffer reallocation). `sfwrite(f,buf,0)` also releases LOCKR — polarity
mixing by design (see "Polarity-mixing operations" below).

**Interception layer** (`sfdisc.c`): Disciplines sit at the boundary
between buffer (value) and OS (computation). `Dccache_t` is the non-
associativity witness: `(push-disc . read) ≠ read . (push-disc)` — if
buffered data exists when a discipline is pushed, it must be replayed
through the new discipline, not served directly.

**Cuts** (`sflife.c`): Restructure context without producing or
consuming. `sfswap` (identity exchange), `sfstack` (source management),
`sftmp` with `_tmpexcept` (value→computation substrate promotion — a
textbook ↑A shift: string buffer becomes fd-backed file when size
threshold is crossed).

**Format engine** (`sfvprintf.c`): Positive with internal shift. `%!`
shifts into computation (extf callback). `FMTSET`/`FMTGET` is the
format engine's own polarity frame — save/restore around the shift,
analogous to `sh_polarity_enter`/`sh_polarity_leave` in the interpreter.

**Neutral** (`sfvle.c`): Pure encoding/decoding with no mode interaction.
7-bit VLE unsigned (sfputu/sfgetu), 6-bit VLE with zigzag sign
(sfputl/sfgetl), and the less-used sfputd/sfgetd/sfputm/sfgetm. Self-
contained, no dependency on the rest of the library beyond basic buffer
access.


## Polarity-mixing operations

Three places where polarity boundaries are deliberately crossed within
the library. These are structural features, not bugs:

### 1. LOCKR protocol

`sfreserve` (negative) → `sfwrite(f,buf,0)` or `sfread(f,buf,0)`
(positive/negative release). Both endpoints live in their respective
files; shared state (the SFIO_PEEK flag) lives in `sfhdr.h`.

This is the clearest polarity boundary crossing in sfio. The reserve
creates a thunk (suspended computation stored as a value — the locked
buffer pointer), and the zero-length write/read forces it (resumes
computation by releasing the lock). Confirmed in ksh source:
- edit.c:539-543 — `sfreserve(sfstderr, LOCKR)` to get write buffer,
  then `sfwrite(sfstderr, ptr, 0)` to release
- history.c:686-689 — `sfreserve(histfp, LOCKR)` then `sfwrite` to
  release

### 2. String stream extension

Positive write triggers `_sfexcept` → realloc. A value-mode operation
(writing bytes into a buffer) causes a computation-mode side effect
(memory allocation, pointer invalidation). The `_sfexcept` call is the
shift — it enters computation mode to resize the substrate, then returns
to value mode with updated buffer pointers.

### 3. sftmp promotion

`_tmpexcept` switches from string (value substrate) to fd (computation
substrate) when the string buffer exceeds a size threshold. This is
the cleanest genuine ↑A shift in sfio: a value (in-memory buffer) is
promoted to a computation substrate (file descriptor) while preserving
identity. The stream handle is the same before and after; only the
backing store changes.


## Headers strategy

### Public `sfio.h` (~200 lines)

Full `Sfio_t` struct definition — no more `_SFIO_PRIVATE` macro dance.
The stdio compat layer is gone; stk already has its own struct. Add
`static_assert` verifying the three-pointer prefix (`data`, `endb`,
`next`) matches stk's expectations.

C23 features:
- `constexpr` for buffer size constants and flag values
- `[[nodiscard]]` on I/O functions that return error indicators
- `static inline` replacing fast-path macros (`sfputc`, `sfgetc`,
  `sffileno`, `sfvalue`, `sfeof`, `sferror`, `sfclrerr`, `sfstacked`,
  `sfstropen`, `sfstruse`, `sfstrclose`)
- Typed enums for mode/flag constants

### Internal `sfhdr.h` (~250 lines)

Consolidate from legacy's 772 lines. Drop: `NIL(t)`, `reg`, hand-
unrolled `MEMCPY`/`MEMSET`, Research UNIX/Apollo probes. Keep:
`SFLOCK`/`SFOPEN` (lock acquisition/release macros), `SFDISC`
(discipline dispatch), `SFDCRD`/`SFDCWR` (discipline read/write
dispatch), `SFRPEEK`/`SFWPEEK` (buffer access macros), `SFSTRSIZE`
(string stream growth), discipline dispatch macros, `_Sfextern`
global state struct, format engine types.


## What gets eliminated

Legacy sfio carries ~3,435 lines that ksh never touches:

| Component | Lines | Reason |
|-----------|-------|--------|
| sfvscanf + sfscanf | 1,124 | ksh never calls scanf |
| sfstrtod + sfstrtof | ~540 | scanf support only |
| sfecvt + sffcvt | ~80 | stdio compat wrappers |
| sfpopen + sfpoll | ~300 | ksh has own pipe/poll mgmt |
| 19 `_sf*.c` wrapper files | 881 | `static inline` in header |
| mmap infrastructure | ~200 | POSIX Issue 8 fd primitives |
| Platform probes | ~150 | Dead platforms |
| Position args (`sftable.c`) | ~160 | Can use libc for `%n$` if ever needed |
| **Total eliminated** | **~3,435** | **27% of legacy sfio** |

The remaining ~9,000 lines of legacy sfio implement the 39 ksh-used
functions with aggressive optimization, K&R compatibility, and internal
macro complexity. The clean reimplementation provides the same semantics
in ~2,600 lines of modern C.


## The sfreserve contract (nucleus)

sfreserve is the most critical function. It has at least 5 distinct
calling patterns used by ksh:

### Pattern 1: Peek availability — `sfreserve(f, 0, 0)`
- Fill buffer if empty (one read attempt)
- Return pointer to `f->next` if data available, NULL if not
- Set `f->val` to bytes available
- **Do NOT advance f->next**
- Used by: exfile main loop (data availability check)

### Pattern 2: Peek/lock — `sfreserve(f, SF_UNBOUND, SF_LOCKR)`
- Fill buffer if empty
- Return pointer to `f->next`
- Set `f->val` to bytes available
- Set PEEK mode (caller must release via sfread(f,buf,0))
- **Do NOT advance f->next**
- Used by: fcin.c (lexer character stream), edit.c (terminal I/O)

### Pattern 3: Consume — `sfreserve(f, SF_UNBOUND, 0)`
- Fill buffer if empty
- Return pointer to `f->next`
- Set `f->val` to bytes available
- **Advance f->next by available amount** (consume all)
- Used by: macro.c (command substitution capture), history.c

### Pattern 4: Reserve N — `sfreserve(f, n, SF_LOCKR)`
- Ensure at least n bytes available (may require multiple fills)
- Return pointer to `f->next`
- Set PEEK mode
- Used by: io.c (here-doc copying)

### Pattern 5: Assess — `sfreserve(f, -size, SF_LOCKR)`
- Negative size: treat as positive but with special handling
- Used by: io.c (io_heredoc)

### Pattern 6: LASTR recovery — `sfgetr(f, delim, SF_LASTR)`
- Not sfreserve, but tightly coupled: returns last partial record
  saved by sfgetr when it hit EOF without finding delimiter


## The sfprintf/%! format engine

This is the biggest single function (sfvprintf.c = 1,434 lines in sfio).
ksh's `print` and `printf` builtins call `sfprintf(outfile, "%!", &pdata)`
where pdata contains an `extf` callback that handles all ksh-specific
format specifiers (%b, %q, %H, %T, %Z, %P, %R, %B, %Q).

The %! protocol:
1. Parse format string until `%!` encountered
2. Read `Sffmt_t*` from va_args
3. If `ft->form` is set, push format context (save current position
   and args), switch to `ft->form` / `ft->args`
4. For each subsequent `%` directive, call `ft->extf(f, &argv, ft)`
5. extf return: <0 = pop format, >0 = extf already wrote, 0 = use argv
6. If `ft->flags & SFFMT_VALUE`: extf populated argv with the value
7. Handle standard specifiers (d/i/o/u/x/X/s/c/p/f/e/g) via
   libc snprintf on a temp buffer

The reimplementation delegates standard specifiers to libc vsnprintf
and handles only the %!/extf protocol. This should reduce sfvprintf
from 1,434 lines to ~400 lines (in sfvprintf.c, the positive+shift
polarity file).

Key detail: the FMTSET/FMTGET macros save and restore format state
around extf calls — this is the format engine's own polarity frame.
The extf may modify ft->fmt, ft->size, ft->flags, ft->width,
ft->precis, ft->base, ft->t_str, ft->n_str. After extf returns, we
read these back to determine how to format the value.


## The discipline system

sfio disciplines are callback chains for custom I/O behavior. ksh uses
them for:

- **outexcept** (io.c:508): Write error handling on stdout
- **pipeexcept** (io.c): Pipe-specific error handling
- **slowexcept** (io.c): Slow device read (tty)
- **slowread** (io.c): TTY read with signal handling
- **piperead** (io.c): Pipe read with interrupt support

The discipline API is simple: push/pop on a linked list, dispatch
read/write/seek/except through the chain. The complex part is Dccache
(caching buffered data when a new discipline is pushed during a read),
which we can implement simply: if data is buffered when a discipline
is pushed, save it and replay it before reading through the new
discipline.

Dccache is the non-associativity witness in the interception layer:
the order of `push-discipline` and `read` operations matters because
buffered data predating the discipline must still be served.


## The _sfmode state machine

sfio calls `_sfmode()` at the start of every operation to ensure the
stream is in the right mode. This is the shift mediator — it handles:

1. GETR restore: if `f->mode & SF_GETR`, restore `f->next[-1] = f->getr`
2. Mode switch: WRITE→READ (drain, reset, seek back for unread),
   READ→WRITE (seek back for unread, reset to write position)
3. Initialization: if SF_INIT, allocate buffer and set initial mode
4. Pool management: if SF_POOL, move to head of pool
5. Lock acquisition

The reimplementation is a single `_sfmode()` function (~100 lines) in
`sfmode.c`, called at the entry of every public function. Each mode
transition is a polarity boundary crossing; the function's structure
directly reflects the shift rules.


## Implementation sequence

The dependency order reflects polarity structure:

```
sfio.h + sfhdr.h  →  sfmode.c  →  sflife.c  →  sfdisc.c  →  sfwrite.c  →  sfread.c  →  sfvprintf.c  →  sfvle.c
   contracts         shift        lifecycle     intercept     positive      negative     format          encoding
```

Each step is independently compilable. The ordering:

1. **Headers** (`sfio.h`, `sfhdr.h`): Contracts and types. Everything
   depends on these; nothing depends on anything else yet.

2. **Shift mediator** (`sfmode.c`): The keystone — every other file
   calls `_sfmode()`. Must exist before any operation can be implemented.

3. **Lifecycle/cuts** (`sflife.c`): Creation, destruction, identity
   operations. Needed before anything can be tested (can't test reads
   without `sfnew`/`sfopen`).

4. **Interception** (`sfdisc.c`): Exception handling and discipline
   dispatch. Called by read/write on error paths. Needed before I/O
   operations can handle failures correctly.

5. **Positive** (`sfwrite.c`): Write operations. Before read because
   `sfwrite(f,buf,0)` LOCKR release path is simpler to test than the
   full read pipeline, and `sfputr`/`sfnputc` are needed by early ksh
   startup (prompt, error messages).

6. **Negative** (`sfread.c`): Read operations. The hardest file —
   sfreserve's 5+ patterns, sfgetr's record accumulation, sfpkrd's
   timed reads. All the v1 failures were here.

7. **Format engine** (`sfvprintf.c`): Depends on all write operations
   being correct. 48/58 test files exercise printf → sfprintf.

8. **Encoding** (`sfvle.c`): Self-contained, can be implemented at any
   point. Listed last because nothing else depends on it.


## POSIX Issue 8 (IEEE 1003.1-2024) integration

The reimplementation targets POSIX Issue 8 as its standard baseline.
Issue 8 adds several primitives relevant to sfio's domain, but they
fall into two sharply different categories.

### Safe: fd-level primitives (use unconditionally)

These operate on file descriptors, have well-specified semantics, and
eliminate fd-leak races that sfio and io.c currently work around:

| Primitive | Replaces | Benefit |
|-----------|----------|---------|
| `pipe2(O_CLOEXEC\|O_CLOFORK)` | `pipe()` + `fcntl(FD_CLOEXEC)` | Atomic — no race between creation and flag set |
| `dup3(old, new, O_CLOEXEC)` | `dup2()` + `fcntl(FD_CLOEXEC)` | Atomic fd dup |
| `ppoll(fds, n, ts, sigmask)` | `poll()` + `sigprocmask()` | Atomic signal mask — for sfpkrd timeout reads |
| `posix_close(fd, 0)` | `close(fd)` | Defined EINTR behavior — for sfclose |
| `mkostemp(tmpl, O_CLOEXEC)` | `mkstemp()` + `fcntl()` | Atomic — for sftmp file creation |
| `O_CLOFORK` | Manual `FD_CLOEXEC` everywhere | Close-on-fork — ksh forks constantly |

These go into `sflife.c` (sfclose, sftmp), `sfread.c` (sfpkrd), and
ksh's `io.c`. Pure improvements, zero design tension with the buffer
model.

### Dangerous: FILE\*-based primitives (do NOT use)

These return or operate on `FILE*`, whose internal buffer is opaque.
They reintroduce the exact problem that killed v1.

| Primitive | Proposed use | Why it fails |
|-----------|-------------|-------------|
| `open_memstream()` | String streams | Buffer pointer only valid after fflush — but sfreserve gives direct `f->next` pointers into the buffer. Seek-past-extent is **implementation-defined** (Issue 8 defect 1406). glibc updates bufp on fclose/fflush; musl on write. |
| `fmemopen()` | Read-only string streams | Binary mode **implementation-defined**. Can't get pointer into buffer for sfreserve LOCKR. |
| `getdelim()` | Inner loop of sfgetr | Requires FILE\* input. Allocation strategy differs across libc (musl had a heap overflow). sfgetr's SF_STRING mode and LASTR recovery have no getdelim equivalent — we'd still write the hard parts ourselves. |

**Why not even for the "easy" cases.** The v1 postmortem established
that sfio is ksh's semantic substrate. The buffer IS the API — code
does pointer arithmetic on `f->next`, `f->endb`, `f->data` directly.
`FILE*` is opaque by POSIX design. The moment you wrap a FILE*, every
sfreserve call becomes fflush-to-get-pointer + fseek-to-set-position,
fighting the abstraction rather than using it.

### Borderline: vasprintf()

`vasprintf()` is now POSIX-standard (Issue 8, previously GNU extension).
It's a leaf operation — format to allocated buffer, return — with no
buffer state entanglement. Could replace sfprints' internal formatting.
However, sfprints intentionally uses a static buffer (zero-alloc,
thread-unsafe — matches sfio's behavior). Use vasprintf only where
allocation is acceptable.


## Polarity analysis: why FILE\* fails for negative polarity

sfio's positive-polarity operations are entangled with negative-polarity
buffer state:

1. **sfputc is a buffer-pointer macro.** The inline form
   `*f->_next++ = c` directly writes into the buffer. fputc would
   work semantically but loses the inline fast path.

2. **sfwrite handles LOCKR release.** sfwrite(f, buf, 0) is the
   standard idiom for releasing an sfreserve lock (sfwrite.c:42-75).
   This is negative-polarity state management masquerading as a write
   call.

3. **sfstruse accesses buffer pointers.** The macro does
   `sfputc(f,0)` then `f->_next = f->_data` — NUL-terminate and
   rewind. Even this value-producing operation needs direct buffer
   access.

**Conclusion:** sfio's design deliberately mixes positive and negative
polarity on the same buffer. The LOCKR protocol is the clearest
example: sfreserve (negative) locks the buffer, sfwrite with n=0
(nominally positive) releases it. This polarity mixing in the shared
buffer model is the fundamental reason FILE\* cannot serve as the
buffer layer for **either** polarity.

The correct architecture: **custom buffer for everything, FILE\* never
appears.** Issue 8's fd-level primitives improve the layer below the
buffer (race-free fd creation, defined close semantics, atomic signal
masks). The buffer layer is ours.

```
┌─────────────────────────────────────────────┐
│  ksh call sites (unchanged)                 │
│  sfprintf, sfreserve, sfgetr, sfputr, ...   │
├─────────────────────────────────────────────┤
│  libsfio (new, ~2,600 lines)                │
│  7 source files by polarity role            │
│  _sfmode() shift mediator                   │
│  %! format engine                           │
│  Discipline chains                          │
│  String stream extent tracking              │
├─────────────────────────────────────────────┤
│  POSIX Issue 8 fd primitives                │
│  pipe2, dup3, ppoll, posix_close, mkostemp  │
│  O_CLOFORK                                  │
├─────────────────────────────────────────────┤
│  kernel: read/write/lseek/close/poll        │
└─────────────────────────────────────────────┘
```


## Philosophy-compatible libraries

The goal is minimal code. Where a well-maintained library provides
functionality that sfio reimplements from scratch, use it:

| Need | sfio approach | Modern approach |
|------|--------------|----------------|
| Buffer management | Custom with mmap fallback | Direct malloc/realloc (mmap unnecessary) |
| Printf formatting | 1,434-line custom engine | libc vsnprintf for standard specifiers |
| Temp files | Custom with string→file spill | `mkostemp(O_CLOEXEC)` + unlink |
| Unicode width | None (added later) | utf8proc (already a dependency) |
| Float conversion | 458-line custom `sfcvt` | libc `snprintf` with %e/%f/%g |
| Timed reads | Custom poll + signal juggling | `ppoll()` (POSIX Issue 8, mandatory) |
| fd lifecycle | Manual FD_CLOEXEC everywhere | `pipe2`, `dup3`, `O_CLOFORK` (Issue 8) |
| Close semantics | `close()` with EINTR ambiguity | `posix_close()` (Issue 8) |

No external libraries needed beyond existing ksh26 dependencies.
The substrate is POSIX Issue 8 libc — specifically the fd-level
primitives, not the FILE\*-based ones.


## Success criteria

1. `just build && just test` passes 115/115
2. `just check-asan` is clean
3. `just check` passes in nix sandbox
4. sfio/ directory deleted from libast
5. ast_stdio.h interception eliminated
6. Total I/O code: ≤3,500 lines (vs ~12,800 in sfio)
7. Zero changes to ksh call sites (same API)
8. All fd creation uses Issue 8 atomic primitives where available


## Risk: what we might get wrong again

1. **sfvprintf %! protocol.** This is the hardest part. 48/58 test
   files use printf. The extf callback protocol has subtle interactions
   with format context stacking. Mitigation: read sfvprintf.c source
   and print.c extend() together, test incrementally.

2. **sfreserve calling patterns.** The v1 failure was exactly here.
   Mitigation: implement and unit-test all 5 patterns before
   integrating with ksh.

3. **Discipline Dccache.** Buffered data caching on discipline push
   is subtle. Mitigation: test with ksh's actual discipline
   configurations (outexcept, slowread, piperead).

4. **sfio_s.h field compatibility.** Some libast code accesses Sfio_t
   fields directly via `f->_data`, `f->_next`, etc. The struct layout
   must match or these accesses must be identified and updated.
   Mitigation: grep for `->_` field accesses in libast.

5. **Global state.** sfio has global state in `_Sfextern` (pools,
   notification hooks, exit handler). Must replicate this correctly.
   Mitigation: `_sfcleanup` atexit handler is straightforward;
   pool list is a linked list through `f->pool`.

6. **Issue 8 availability.** Not all targets may have pipe2/dup3/ppoll/
   posix_close yet. configure.sh must probe for each and provide
   fallbacks (e.g. pipe+fcntl when pipe2 unavailable). The fd-level
   Issue 8 primitives are available on all Tier 1 targets (glibc 2.9+,
   musl, macOS 11+, FreeBSD 10+, OpenBSD 5.7+, illumos) but feature
   probes ensure correctness.

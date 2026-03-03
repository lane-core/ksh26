# sfio Rewrite v2: Clean Reimplementation

## Premise

The Direction 12 failure analysis (see `sfio-rewrite-failure-analysis.md`)
established that the problem was "replace sfio with stdio" rather than
"provide ksh's I/O semantics cleanly." This proposal takes the second
approach: reimplement sfio's contracts from scratch in modern C, keeping
the same API surface that ksh expects, but without sfio's legacy
complexity.

sfio is ~12,800 lines across 78 files. ksh uses 39 of 77 exported
functions. A clean reimplementation targeting only what ksh needs should
be ~2,000–3,000 lines in a single file, with a clean header.

## Rollback point

Start from `v0.0.1` (commit `a98a33db`). This is the last known-good
state: Directions 1–11 complete, sfio build at 114/115, build system
functional. Cherry-pick forward:

**Infrastructure** (must preserve):
- `configure.sh` improvements (shim headers, dsymutil fix, test runner)
- `justfile` recipes (stdio build/test, asan, diagnostics)
- `flake.nix` improvements (agent devshell, checks, formatter)
- `CLAUDE.md` updates (recipes, workflow docs)

**Documentation** (preserve selectively):
- `notes/sfio-retirement-plan.md` — root cause analysis is gold, keep
- `notes/sfio-rewrite-failure-analysis.md` — this document, keep
- `REDESIGN.md` — update Direction 12 to reflect v2 approach
- `SPEC.md` — unchanged, still the theoretical foundation

**Discard**:
- `sh_io_stdio.c` (FILE\*-based approach, 1227 lines)
- `sh_io_core.c` (fd+buffer approach, ~2000 lines with debug)
- Phase 7/8 commits (structural approach was wrong)
- The dual KSH_IO_SFIO build flag complexity

## Strategy: don't abstract, reimplement

v1 tried to create an abstraction layer between ksh and sfio, then
provide alternate backends. This added complexity (two code paths,
shim headers, conditional compilation) without reducing the contract
surface ksh depends on.

v2 takes the opposite approach: **one implementation, same API names,
same semantics, new code.** The result is a drop-in replacement for
`src/lib/libast/sfio/` — same `sfio.h` header, same `Sfio_t` type,
same sf\* functions — but implemented in ~3K lines instead of ~13K.

This means:
- Zero changes to ksh call sites
- Zero abstraction layers or conditional compilation
- The old sfio directory is deleted and replaced
- libast's non-sfio code (CDT, stk, optget, error, etc.) continues
  to work because the API is identical

## What to implement

### Tier 1: Core (ksh startup requires these)

These functions must work before `ksh -c 'print hello'` produces output.

| Function | Calls | Contract summary |
|----------|-------|-----------------|
| `sfnew` | 18 | Create/reinit stream. Handle STATIC flag preservation. |
| `sfsetbuf` | 11 | Buffer assignment. Magic `(f,f,0)` query. Mode inference. |
| `sfset` | 30 | Flag manipulation with protection mask. |
| `sfopen` | 13 | Mode string → flags → fd or string stream. |
| `sfclose` | 24 | Drain → CLOSING event → close fd → free → FINAL event. |
| `sfsync` | 40 | Drain writes. NULL = sync all tracked streams. |
| `sfnotify` | 1 | Register global callback (already trivial). |
| `sfdisc` | 12 | Push/pop discipline. DPUSH/DPOP events. Dccache on push. |
| `sfpool` | 11 | Pool membership (linked list through pool pointer). |
| `sfputc` | 61 | Write byte. Line-buffer flush on '\n'. |
| `sfwrite` | 50 | Write buffer. n=0 releases LOCKR. Line-buffer check. |
| `sfprintf` | 118 | **The gate.** Must support %! format stacking for print.c. |
| `sfputr` | 66 | Write string + optional delimiter. |
| `sfnputc` | 30 | Write repeated byte. |
| `sfgetc` | — | Read byte. (Used via macro/fcin.) |
| `sfread` | — | Read buffer. n=0 releases LOCKR. |
| `sfreserve` | 11 | **The nucleus.** 4+ calling patterns (see below). |
| `sfgetr` | — | Record read. 3 modes (default, STRING, LASTR). |
| `sfseek` | 24 | Seek with buffer accounting. String stream extent. |
| `sftell` | — | Position query with buffer offset correction. |
| `sfsetfd` | — | Change fd. Sync first if needed. |
| `sfswap` | — | Content exchange. STATIC stays with memory location. |
| `sfstack` | — | Push/pop stream (lexer, aliases, here-strings). |
| `sftmp` | — | Temp stream (string initially, spill to file). |
| `sffileno` | 27 | Macro: `f->file`. |
| `sfvalue` | — | Macro: `f->val`. |
| `sfeof` | — | Macro: `f->flags & SF_EOF`. |
| `sferror` | — | Macro: `f->flags & SF_ERROR`. |
| `sfclrerr` | — | Macro: clear EOF+ERROR. |

### Tier 2: Used but simpler

| Function | Calls | Notes |
|----------|-------|-------|
| `sfmove` | — | Bulk copy between streams. |
| `sfungetc` | — | Push back one byte. |
| `sfsize` | — | fstat or extent for string streams. |
| `sfstacked` | — | Boolean: stack != NULL. |
| `sfclrlock` | — | Clear PEEK/GETR mode bits. |
| `sfpurge` | — | Discard buffered data. |
| `sfraise` | — | Walk discipline chain, call exceptf. |
| `sfpkrd` | — | Raw read with optional timeout and delimiter. |
| `sfrd` | — | Read through discipline chain. |
| `sfputu/sfgetu` | 14/11 | 7-bit VLE (unsigned). |
| `sfputl/sfgetl` | 12/— | 6-bit VLE with sign (zigzag). |
| `sfprints` | — | Format to static buffer. |
| `sfsetfd_cloexec` | — | ksh26-specific extension. |

### Tier 3: Not needed (eliminate)

| Subsystem | Lines | Why not needed |
|-----------|-------|---------------|
| scanf engine (`sfvscanf.c`) | 1,061 | ksh never calls scanf. |
| Float conversion (`sfcvt.c`) | 458 | ksh uses libc for floats. |
| Type encoding (`sfputd/sfgetd/sfputm/sfgetm`) | ~200 | Unused by ksh. |
| Memory mapping | ~300 | Complexity for marginal perf. |
| Process co-pipes (`sfpopen.c`) | 70 | ksh has its own pipe management. |
| Poll wrapper (`sfpoll.c`) | 244 | ksh has its own poll/select. |
| Stdio compatibility (`ast_stdio.h` interception) | ~500 | The thing we're trying to eliminate. |
| Position args in printf (`sftable.c`) | 523 | Can use libc for `%n$` if ever needed. |
| Inline macro wrappers (19 `_sf*.c` files) | ~400 | Modern compiler handles inlining. |

**Eliminated: ~3,756 lines (29% of sfio) that ksh never touches.**

The remaining ~9,000 lines of sfio implement the Tier 1+2 functions
with aggressive optimization, K&R compatibility, and internal macro
complexity. A clean reimplementation of the same semantics in modern
C should be 2,000–3,000 lines.

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

The reimplementation can delegate standard specifiers to libc vsnprintf
and handle only the %!/extf protocol ourselves. This should reduce
sfvprintf from 1,434 lines to ~300–400 lines.

Key detail: the FMTSET/FMTGET macros save and restore format state
around extf calls. The extf may modify ft->fmt, ft->size, ft->flags,
ft->width, ft->precis, ft->base, ft->t_str, ft->n_str. After extf
returns, we read these back to determine how to format the value.

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

## The _sfmode state machine

sfio calls `_sfmode()` at the start of every operation to ensure the
stream is in the right mode. This handles:

1. GETR restore: if `f->mode & SF_GETR`, restore `f->next[-1] = f->getr`
2. Mode switch: WRITE→READ (drain, reset, seek back for unread),
   READ→WRITE (seek back for unread, reset to write position)
3. Initialization: if SF_INIT, allocate buffer and set initial mode
4. Pool management: if SF_POOL, move to head of pool
5. Lock acquisition

The reimplementation should be a single `_sfmode()` function (~100
lines) called at the entry of every public function. This replaces
the scattered mode checks in the v1 approach.

## Implementation plan

### Phase 1: Contracts and structure (~1 day)

Write `src/lib/libsfio/sfio.h` (public header) and
`src/lib/libsfio/sfio_impl.h` (internal header) defining:

- `Sfio_t` struct (same field names as sfio for sfio_s.h compat)
- Mode bits, flag constants
- Discipline types
- All function declarations

Write contracts as comments for every function, extracted from reading
the sfio source. No implementation yet — just the spec.

### Phase 2: Core (~2 days)

Implement in `src/lib/libsfio/sfio.c` (single file):

1. `_sfmode()` — the mode state machine
2. `_sfdrain()` / `_sffill()` — buffer drain and fill through disciplines
3. `sfreserve` — all 5+ calling patterns
4. `sfgetc` / `sfputc` / `sfread` / `sfwrite` — byte and buffer I/O
5. `sfgetr` — record read with getr_buf accumulation
6. `sfnew` / `sfclose` / `sfsync` / `sfset` / `sfsetbuf` — lifecycle
7. `sfopen` / `sftmp` — stream creation
8. `sfseek` / `sftell` / `sfsize` — positioning
9. `sfswap` / `sfstack` — content exchange and stacking
10. `sfdisc` / `sfraise` — discipline push/pop/dispatch
11. `sfpool` — pool membership
12. `sfsetfd` / `sfsetfd_cloexec` — fd manipulation
13. `sfputr` / `sfnputc` / `sfungetc` / `sfmove` — convenience
14. `sfpkrd` / `sfrd` — raw I/O
15. `sfputu` / `sfgetu` / `sfputl` / `sfgetl` — VLE
16. `sfprints` / `sfstropen` / `sfstruse` / `sfstrclose` — string ops

### Phase 3: Format engine (~1 day)

Implement `sfvprintf` with %! support in
`src/lib/libsfio/sfvprintf.c` (~300–400 lines):

1. Parse format directives (flags, width, precision, size, specifier)
2. Handle %! format stacking (push/pop Fmt_t context)
3. Call extf with FMTSET/FMTGET protocol
4. Delegate standard specifiers to libc vsnprintf
5. Handle padding/alignment ourselves for exact parity

### Phase 4: Integration (~1 day)

1. Update build system to compile libsfio instead of libast/sfio
2. Remove old sfio directory from libast
3. Remove ast_stdio.h interception
4. Build and test: target 115/115

### Phase 5: Cleanup

1. Remove KSH_IO_SFIO conditional compilation
2. Remove shim headers
3. Remove sh_io.h abstraction layer (sfio.h IS the API now)
4. Update REDESIGN.md

## Philosophy-compatible libraries

The goal is minimal code. Where a well-maintained library provides
functionality that sfio reimplements from scratch, use it:

| Need | sfio approach | Modern approach |
|------|--------------|----------------|
| Buffer management | Custom with mmap fallback | Direct malloc/realloc (mmap unnecessary) |
| Printf formatting | 1,434-line custom engine | libc vsnprintf for standard specifiers |
| Temp files | Custom with string→file spill | mkstemp + unlink |
| Unicode width | None (added later) | utf8proc (already a dependency) |
| Float conversion | 458-line custom `sfcvt` | libc `snprintf` with %e/%f/%g |

No external libraries are needed beyond what ksh26 already depends on.
The "library" is libc itself — modern libc's snprintf, mkstemp, poll,
read, write are the building blocks. sfio was written in the 1990s when
these either didn't exist or weren't portable. They're all POSIX now.

## Success criteria

1. `just build && just test` passes 115/115
2. `just check-asan` is clean
3. `just check` passes in nix sandbox
4. sfio/ directory deleted from libast
5. ast_stdio.h interception eliminated
6. Total I/O code: ≤3,500 lines (vs ~12,800 in sfio)
7. Zero changes to ksh call sites (same API)

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

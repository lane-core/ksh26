## Context

sfio is ksh's semantic substrate — not a library it "uses" but the
medium through which all I/O flows. ~1000 call sites in ksh, ~800 in
libast. Three prior stdio-replacement attempts failed because the buffer
IS the API: code does pointer arithmetic on `f->next`, `f->endb`,
`f->data` directly. FILE* is opaque by design.

See `notes/sfio-rewrite-failure-analysis.md` for the v1 postmortem.

**Prior reduction work** (commit `aa3c9798`): Phases A–E1 consolidated
legacy sfio from 80 to 42 `.c` files (-2140 lines, no behavioral changes).
Three consolidated files (sfvle.c, sflife.c, sfread.c) already match the
rewrite's polarity-role file layout. Remaining phases E2 (write path →
sfwrite.c, ~718 lines) and E3 (seek/sync → sfseek.c, ~764 lines) can
proceed independently — they reduce legacy complexity regardless of
whether the clean-room rewrite supersedes them. After E2+E3: 42 → ~35
files (56% total reduction from 80).

Files that stay separate by design in the legacy reduction (not relevant
to the rewrite, which replaces everything): sfvprintf.c (1103),
sfmode.c (390), sfsetbuf.c (439), sfdisc.c (230), sfexcept.c (181),
sfextern.c (120), sftable.c (425), sfstack.c (161), sfswap.c (105),
sfpool.c (341), sfset.c (78), sfmove.c (168), sfwalk.c (41),
sfpoll.c (175), sfcvt.c (168), sfprintf.c (32), sfprints.c (72).

See `notes/sfio-analysis/sfio-reduction-report.md` for details and
lessons learned (macro-hidden callers, N_ARRAY collisions, nix staging).

## Goals / Non-Goals

**Goals:**
- Drop-in replacement: same sfio.h, same Sfio_t, same sf* functions
- ~2,600 lines replacing ~12,800 lines
- Modern C23: typed enums, constexpr, static_assert, [[nodiscard]]
- POSIX Issue 8 fd primitives where available
- Source files organized by duploid polarity role

**Non-Goals:**
- Abstracting sfio behind a generic I/O layer (v1's mistake)
- Using FILE*-based Issue 8 primitives
- Changing any ksh call sites
- Thread safety (ksh is single-threaded)

## Decisions

### 1. Same API, new code (not abstraction layer)

v1 tried to create an abstraction between ksh and sfio, then provide
alternate backends. This added complexity without reducing the contract
surface. v2 reimplements the same API directly.

**Alternative rejected**: Dual-representation approach (sfio + stdio
wrappers). Worse than either alone due to polarity mixing in the shared
buffer model.

### 2. Source files by polarity role

Seven files organized by duploid correspondence:

| File | Role | Lines |
|------|------|-------|
| sfmode.c | Shift mediator | ~250 |
| sfread.c | Negative (consumers) | ~500 |
| sfwrite.c | Positive (producers) | ~350 |
| sfdisc.c | Interception | ~200 |
| sflife.c | Cuts (lifecycle) | ~450 |
| sfvprintf.c | Positive + shift (format) | ~700 |
| sfvle.c | Neutral (encoding) | ~150 |

**Alternative rejected**: Organization by legacy file boundaries (78
files). Too granular, obscures the polarity structure.

### 3. Delegate standard printf to libc

sfvprintf.c handles only %!/extf. Standard specifiers go through libc
vsnprintf. Reduces ~1,434 lines to ~700.

**Alternative rejected**: Reimplement all format specifiers. Unnecessary
— libc's vsnprintf is correct, tested, and locale-aware.

### 4. Incremental replacement via consolidation

The atomic swap approach was attempted and failed with heap corruption
during sh_init (see notes/sfio-analysis/sfio-reduction-report.md). The
revised approach: consolidate legacy sfio into the same file layout as
the rewrite (80→42→~35 files), then replace each consolidated file with
its staging counterpart one at a time. Each replacement is gated by
`just build && just test`.

This works because consolidation eliminates the internal coupling problem
— once legacy code is organized into the same 7 files as the rewrite,
each file can be swapped independently without breaking the build.

**Alternative rejected**: Big-bang atomic swap. Heap corruption during
sh_init was extremely hard to debug (ASAN passed, non-ASAN crashed).
Root cause narrowed to sfsetbuf calls but never fully isolated.

### 5. POSIX Issue 8 fd primitives (not FILE*)

Use pipe2, dup3, ppoll, posix_close, mkostemp for race-free fd lifecycle.
Explicitly exclude open_memstream, fmemopen, getdelim — they return
FILE* and reintroduce the exact problem that killed v1.

## Risks / Trade-offs

**[sfvprintf %! protocol]** → Most complex function. 48/58 tests use
printf. Mitigation: read sfvprintf.c and print.c extend() together,
test incrementally with ksh's actual extf callback.

**[sfreserve calling patterns]** → Where v1 failed. 5+ distinct patterns
with different f->next advancement semantics. Mitigation: independent
unit tests for each pattern before integration.

**[Dccache discipline replay]** → Subtle buffered-data caching on
discipline push. Mitigation: test with ksh's actual discipline
configurations (outexcept, slowread, piperead).

**[Sfio_t field compatibility]** → Some libast code accesses fields
directly via `f->_data`, `f->_next`. Mitigation: grep for `->_` field
accesses, ensure struct layout matches.

**[Issue 8 availability]** → Not all targets may have all primitives.
Mitigation: configure.sh probes each, provides fallbacks.

## Resolved Questions

- **sfio_check()**: Always-on (matching polarity frame depth tracking).
  The assertion is cheap and catches buffer invariant violations early.
- **Staging directory**: src/lib/libsfio/ is the staging location. Files
  are swapped into src/lib/libast/sfio/ incrementally (one file at a
  time), not in one step. The staging directory is deleted after all
  files are swapped.

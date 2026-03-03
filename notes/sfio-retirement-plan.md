# sfio Retirement: Phase 6–8 Plan

## Context

Direction 12 Phase 5 brought the stdio backend from 0/115 to 36/115 tests
passing. The sfreserve buffer model (LOCKR vs non-LOCKR polarity), sfswap
SFIO_STATIC semantics, and all sf* function stubs are implemented. The sfio
build remains at 115/115 (zero regressions).

79 tests still crash. Analysis of the failure patterns, io.c's discipline
usage, and the sh_iorenumber/sh_iostream FILE* lifecycle shows three root
causes responsible for nearly all crashes.

Current uncommitted changes: sfreserve fix, sfswap SFIO_STATIC fix, sfseek
fflush, REDESIGN.md update. These must be committed as a checkpoint before
proceeding.


## Step 0: Commit current work

Commit all uncommitted changes (sh_io_stdio.c, sh_io.h, REDESIGN.md,
justfile, etc.) as a clean checkpoint before beginning Phase 6.


## Root cause analysis of 79 failures

### RC1: FILE* lifecycle in sfnew/sfsetfd (~50 failures)

The primary crash path. `sh_iostream()` (io.c:577) calls `sfnew()` to
create a stream around an fd, then installs a discipline. Under sfio,
the stream and its buffering are one unified object. Under stdio, we
have an `sh_stream_t` wrapping a `FILE*` created by `fdopen()`.

The problem: `_sh_ensure_fp()` calls `fdopen(fd, mode)` immediately, but:

1. **fd may not yet be ready** — ksh allocates fds then configures them.
   `sfsetfd(sp, 10)` in `io_preserve` (io.c:618) moves the fd, then
   later code creates a FILE* for the new fd. But fdopen on a moved fd
   can produce a stale FILE*.

2. **sfsetfd closes the old FILE*** but ksh expects sfio-style seamless
   fd replacement. In sfio, `sfsetfd` just changes the backing fd of the
   same buffer object. In stdio, we fclose the old FILE* (destroying its
   buffer state) and fdopen a new one. Any buffered data is lost.

3. **`sh_iorenumber` (io.c:652)** does `sfsetfd(spnew, f2)` then
   `sfswap(spnew, sp)` — the swap moves the FILE* from spnew into sp,
   but sp might have had a different FILE* that's now leaked.

### RC2: Discipline event protocol (DPUSH/DPOP) (~15 failures)

io.c disciplines expect SFIO_DPOP and SFIO_FINAL events to trigger
cleanup (free the discipline struct). Current sfdisc() is a plain
linked-list push/pop with no event firing.

Concrete pattern (io.c:494, 1882, 2223, 2366, 2442):
```c
if(type==SFIO_DPOP || type==SFIO_FINAL)
    free(handle);
```

Without DPOP events, these `free()` calls never happen → memory leaks
at minimum, and some disciplines use DPOP to do essential cleanup
(sfsetfd(sp,-1) in io.c:2439).

### RC3: Here-doc/here-string I/O chain (~14 failures)

Here-docs use a write→seek→read chain on `sh.heredocs` (a persistent
sftmp stream):
1. Write heredoc content to sh.heredocs (sfwrite)
2. Record offset (sftell)
3. Later: seek to offset (sfseek), read content (sfmove)

Under stdio, the write populates the FILE* buffer but sfseek (even with
our fflush fix) may not properly synchronize with sfreserve's separate
buffer. And sfmove in record mode uses sfgetr, which reads from the
FILE* directly — potentially missing data that's in sfreserve's buffer.

Also: here-strings (`<<<`) create an sfnew STRING stream with
fmemopen, but the lifecycle around closing and reopening these is
fragile with FILE*.


## Implementation plan

### Phase 6A: sfdisc event protocol

**Files:** `src/cmd/ksh26/sh/sh_io_stdio.c`

Fire DPOP events when popping a discipline, DPUSH events when pushing.
This is ~15 lines in sfdisc() — call the discipline's exceptf before
removing it from the chain.

```c
/* pop: fire DPOP event, then remove */
if(!d)
{
    old = f->disc;
    if(old)
    {
        f->disc = old->disc;
        if(old->exceptf)
            old->exceptf(f, SH_IO_DPOP, NULL, old);
    }
    return old;
}
/* push: add to chain, fire DPUSH event */
old = f->disc;
d->disc = old;
f->disc = d;
if(d->exceptf)
    d->exceptf(f, SH_IO_DPUSH, NULL, d);
```

Also update `sh_stream_close()` to fire SFIO_FINAL through the chain
before closing.

**Expected impact:** Fixes discipline memory leaks, enables discipline
cleanup that calls sfsetfd(sp,-1).

### Phase 6B: sfsetfd FILE* lifecycle

**Files:** `src/cmd/ksh26/sh/sh_io_stdio.c`

The core issue: sfsetfd must NOT destroy buffered data when changing fds.
Under sfio, changing the fd just changes what the buffer reads/writes to.
Under stdio, fclose destroys the buffer.

Fix: when changing fds, flush the FILE* first (preserve writes), then
use `dup2` + `freopen` or close+reopen. For the common `sfsetfd(sp,-1)`
pattern (detach fd without closing FILE*), just clear the fd field
without touching the FILE*.

Specific cases:
1. `sfsetfd(sp, -1)` — detach: set f->fd = -1, do NOT fclose. The
   FILE* may still be needed (sh_iorenumber pattern).
2. `sfsetfd(sp, newfd)` — move: flush, fclose old, fdopen new.
3. `sfsetfd(sp, 10)` via F_DUPFD — preserve: the old fd is duped to
   10+, then the stream should point to the new fd.

**Expected impact:** Fixes ~50 segfaults from stale/invalid FILE*.

### Phase 6C: Here-doc I/O path

**Files:** `src/cmd/ksh26/sh/sh_io_stdio.c`

Ensure sfmove in byte mode flushes the source stream before reading
from FILE*. The write→seek→read chain must go through the same FILE*
buffer, not the sfreserve buffer (which is for reading, not for
written-then-seeked-back data).

Add: clear sfreserve buffer state on seek (any seek invalidates the
read buffer, since the FILE* position moved).

```c
static inline off_t
_sh_io_seek(sh_stream_t *f, off_t offset, int whence)
{
    if(f->flags & SH_IO_WRITE)
        fflush(f->fp);
    /* seek invalidates sfreserve's read buffer */
    f->val = 0;
    f->data = NULL;
    f->flags &= ~_SH_IO_RSVLCK;
    if(fseeko(f->fp, offset, whence) < 0)
        return (off_t)-1;
    return ftello(f->fp);
}
```

**Expected impact:** Fixes here-doc/here-string failures where data
written to sftmp is not visible after seek+read.


## Phase 7: Parity (115/115 on stdio)

After Phase 6, run full test suite and categorize remaining failures.
Expected to be edge cases:
- Edit/interactive paths (sfpkrd + tty)
- Coprocess I/O (two-way pipe with sfnew)
- Signal interaction during I/O
- Locale-specific behavior

Each remaining failure gets a targeted fix. No speculative work — each
fix is driven by a specific test failure and stack trace.


## Phase 8: Remove sfio from build

Once stdio passes 115/115:
1. Delete `src/lib/libast/sfio/` (80 files, ~11.5k LOC)
2. Delete `src/lib/libast/include/sfio*.h` and shim headers
3. Remove `KSH_IO_SFIO` conditional compilation from sh_io.h
4. Remove sfio from configure.sh source collection and link line
5. Remove `--stdio` flag from configure.sh (it becomes the only backend)
6. Update justfile: remove build-stdio/test-stdio/clean-stdio recipes,
   make the default recipes use the (now only) backend
7. Verify: `just clean && just build && just test` → 115/115


## Files to modify (Phase 6)

| File | Changes |
|------|---------|
| `src/cmd/ksh26/sh/sh_io_stdio.c` | sfdisc events (6A), sfsetfd lifecycle (6B) |
| `src/cmd/ksh26/include/sh_io.h` | sfseek buffer invalidation (6C) |


## Verification

```sh
# 0. Commit checkpoint
git add ... && git commit

# After each sub-phase (6A, 6B, 6C):
just clean test && just test          # sfio: must stay 115/115
just clean-stdio && just build-stdio && just test-stdio  # count passing

# Phase 6 target: >=100/115 passing on stdio
# Phase 7 target: 115/115 on stdio
# Phase 8 target: 115/115 on unified (sfio-free) build
```

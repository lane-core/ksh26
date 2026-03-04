# 09: String Streams and Temp Files

String streams (`SF_STRING`) use heap memory as a resizable buffer with no
fd. Temp streams (`sftmp`) start as string streams and promote to file-backed
streams on demand. Both are workhorses in ksh for here-docs, command
substitution capture, and temporary storage.

## SF_STRING mode

### Properties

- `f->file = -1` (no fd)
- Buffer is heap-allocated, resizable
- `f->data` points to the allocation
- `f->endb = f->data + allocated_size`
- No I/O syscalls — all operations are in-memory

### Buffer extension

When a write exceeds `f->endb`, the write path calls `sfwr()` which for
string streams passes the required new size to `_sfexcept()`:

```c
/* sfwr.c: string stream path */
w = n + (f->next - f->data);  /* new size needed */
/* falls through to _sfexcept with SFIO_WRITE event */
```

`_sfexcept` (`Legacy: sfexcept.c`) handles extension:

```c
/* if SFIO_MALLOC and not fixed-size: */
new_size = round_up_to(SFIO_GRAIN, max(new_size, current_size * 2));
data = realloc(f->data, new_size);
f->endb = data + new_size;
f->next = data + (f->next - f->data);  /* preserve cursor offset */
f->endr = f->endw = f->data = data;
f->size = new_size;
/* returns SFIO_EDISC → caller retries the write */
```

`Contract:` After extension, all pointers are updated. The cursor offset
is preserved. Callers that hold pointers into the old buffer must reload
after any operation that might trigger extension.

### String stream macros

`Legacy: sfio.h:367-401`

| Macro | Purpose |
|-------|---------|
| `sfstropen()` | `sfnew(0, 0, -1, -1, SFIO_READ\|SFIO_WRITE\|SFIO_STRING)` |
| `sfstrclose(f)` | `sfclose(f)` |
| `sfstrseek(f,p,m)` | Seek within string buffer (pointer arithmetic) |
| `sfstrsize(f)` | `f->_size` |
| `sfstrtell(f)` | `f->_next - f->_data` |
| `sfstrbase(f)` | `(char*)f->_data` |
| `sfstruse(f)` | NUL-terminate and reset: `sfputc(f,0)`, return data, reset next |

`sfstruse` is the standard idiom for extracting a string from a write
stream: writes a NUL terminator, returns the data pointer, resets the
cursor to the start.

### Extent tracking

`Legacy: sfhdr.h:555-558`

```c
#define SFSTRSIZE(f) { Sfoff_t s = (f)->next - (f)->data; \
    if(s > (f)->here) \
        { (f)->here = s; if(s > (f)->extent) (f)->extent = s; } \
}
```

`here` tracks the high-water mark within the current session. `extent`
tracks the all-time maximum. Both used during string→file promotion in
`sftmp()` to determine how much data to copy.

---

## sftmp(size) — temp stream

`Legacy: sfio/sftmp.c:233-271`

**Signature:** `Sfio_t *sftmp(size_t s)`

Creates a temporary stream that starts as a string stream and promotes to
a real temp file on overflow.

### Creation

```c
f = sfnew(NULL, NULL, s, -1, SFIO_STRING|SFIO_READ|SFIO_WRITE);
```

Three cases by `s`:

| s | Behavior |
|---|----------|
| > 0 | String stream with `Tmpdisc` discipline. Promotes on overflow |
| SFIO_UNBOUND (-1) | String stream, no discipline. Grows without limit |
| 0 | Immediately creates a temp file (calls `_tmpexcept` right away) |

For `s > 0`: attaches `Tmpdisc` (line 238), whose `exceptf = _tmpexcept`
handles the overflow event.

---

## _tmpexcept — string → file promotion

`Legacy: sfio/sftmp.c:158-231`

Fired on: SFIO_WRITE (buffer overflow), SFIO_SEEK (seek on string stream),
SFIO_DPUSH, SFIO_DPOP, SFIO_DBUFFER.

### Sequence

1. Create temp fd via `_tmpfd()` (tries /dev/shm on Linux with tmpfs,
   falls back to tmpdir).
2. Create new file-backed stream: `sfnew(&newf, NULL, SFIO_UNBOUND, fd, SFIO_READ|SFIO_WRITE)`.
   ⚠ Hazard: `_Sfnotify` is temporarily zeroed during this `sfnew` to prevent
   `sftrack` from seeing the intermediate stream creation. Restored immediately
   after.
3. **Identity swap** — the critical step:

```c
memcpy(&savf, f, sizeof(Sfio_t));   /* save string stream state */
memcpy(f, sf, sizeof(Sfio_t));      /* overwrite f with file stream */
f->push = savf.push;                /* restore structural links */
f->pool = savf.pool;
f->rsrv = savf.rsrv;
f->proc = savf.proc;
f->stdio = savf.stdio;
if(!(savf.flags & SFIO_STATIC))
    f->flags &= ~SFIO_STATIC;
```

The original `Sfio_t* f` address stays valid (callers hold it), but its
internals now describe the file-backed stream. Push/pool/rsrv/proc/stdio
are identity fields — they stay with the address, not the state.

4. **Data migration**: if the old string stream had data:
   - `sfwrite(f, savf.data, extent)` — copy into file.
   - `sfseek(f, savf.next - savf.data, SEEK_SET)` — restore position.
   - Free old heap buffer if SFIO_MALLOC.

5. **Cleanup**: `f->disc = NULL` (remove Tmpdisc), notify SFIO_SETFD,
   close the temporary `newf`.

Returns 1 (SFIO_ECONT) — the operation that triggered the exception
retries on the now-file-backed stream.

`Polarity:` `_tmpexcept` has the structure of the cleanest genuine polarity
shift in the sfio codebase. The stream starts as pure value (in-memory string
buffer, no I/O syscalls) and promotes to computation-backed (file descriptor,
actual I/O). The memcpy identity swap preserves the `Sfio_t*` address as a
stable identity while completely changing the computation substrate
underneath. The `SFIO_ECONT` return means the caller never knows the shift
happened — it's transparent. The shift direction is perspective-dependent:
from the stream's internals, value → computation (like `eval` forcing a
string into command mode); from the caller's view, computation is packaged
behind a value-mode interface (like ↑A/return). The structural point is the
mode change with transparent identity preservation; the specific ↑/↓ label
depends on which side of the boundary you stand on.

---

## Temp file cleanup

### POSIX systems

`Legacy: sftmp.c:106-127`

The temp file is `remove()`d immediately after creation — it lives only as
an open fd with no directory entry. Clean on all exit paths including crashes.

### Non-POSIX (_tmp_rmfail, e.g., Windows)

`Rmdisc` is pushed below `Tmpdisc` in the discipline chain. Its
`_tmprmfile` handler catches SFIO_CLOSING, closes the fd first, then
removes the file. An `_rmfiles()` atexit handler covers process-exit.

---

## ksh use cases

### Here-documents

`io_heredoc()` (`Legacy: io.c:1602-1681`):

```
outfile = sftmp(0)              /* or sftmp(size) for in-memory */
sfputr(outfile, content, '\n')  /* write here-doc body */
fd = sffileno(outfile)
sfsetfd(outfile, -1)            /* detach fd from stream */
sfclose(outfile)                /* free stream, keep fd */
lseek(fd, 0, SEEK_SET)         /* rewind */
```

The `sfsetfd(f, -1)` + `sfclose(f)` idiom extracts the fd: sfclose with
fd=-1 frees the stream without calling `close(fd)`.

### Command substitution capture

`sh_subshell()` (`Legacy: subshell.c:524-798`):

```
iop = sftmp(PIPE_BUF)          /* create capture buffer */
sfswap(iop, sfstdout)           /* install as stdout */
/* execute command — output goes to sftmp */
iop = sfswap(sfstdout, NULL)    /* recover capture buffer */
sfset(iop, SFIO_READ, 1)       /* switch to read mode */
/* read captured output from iop */
```

`sftmp(PIPE_BUF)`: in-memory if output fits (512 bytes), promotes to
file on overflow. For `${ ...; }` shared-state comsub: doesn't swap stdout.

### String expansion

Throughout `macro.c`: `sfstropen()` for temporary string assembly during
parameter expansion, arithmetic evaluation, pattern matching.

---

## Key invariants

1. **Identity preservation.** `sftmp` promotion preserves the `Sfio_t*`
   address. Callers don't need to know the underlying storage changed.

2. **SFIO_ECONT return.** After promotion, the triggering operation (write,
   seek) is retried automatically. Callers don't need to handle the transition.

3. **Immediate unlink on POSIX.** Temp files have no directory entry after
   creation. No cleanup needed on any exit path.

4. **Push/pool/rsrv/proc stay with address.** These are identity fields,
   not state fields. The memcpy swap restores them from the saved copy.

→ C23: `constexpr` for buffer growth constants. `nullptr` in sentinel
comparisons.

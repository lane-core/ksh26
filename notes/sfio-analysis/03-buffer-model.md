# 03: Buffer Model

The buffer is the central abstraction in SFIO. Five pointers define a contiguous
memory region with separate read and write windows. Understanding their
invariants is prerequisite to understanding any SFIO operation.

## The five-pointer system

```
    _data                    _next        _endw/_endr     _endb
      |                        |              |              |
      v                        v              v              v
      +------------------------+--------------+--------------+
      |    consumed/written    |   available  |  slack space |
      +------------------------+--------------+--------------+

      |<------------ _size (may be larger) --------------->|
```

| Pointer | Type | Meaning |
|---------|------|---------|
| `_data` | `unsigned char*` | Base of buffer allocation |
| `_next` | `unsigned char*` | Current position (next byte to read or write) |
| `_endw` | `unsigned char*` | End of writable region |
| `_endr` | `unsigned char*` | End of readable region |
| `_endb` | `unsigned char*` | Physical end of buffer |

`Legacy: sfio_s.h:33-36, sfhdr.h:30-39`

## Fundamental invariant

```
Contract: _data <= _next <= min(_endr, _endw) <= _endb
```

This holds in the steady state. During mode transitions and lock states,
intermediate values may temporarily violate this (e.g., lock sets
`_endr = _endw = _data`).

## Read mode buffer lifecycle

When the stream is in `SFIO_READ` mode:

```
Active:   _endr = _endb (or end of valid data)
          _endw = _data (writes disabled)
          _next advances from _data toward _endr as bytes are consumed
```

1. **Fill**: When the buffer is empty, `_sffilbuf()` resets
   `_next = _endb = _endr = _data`, then reads into the buffer starting
   at `_data`. After the read: `_endb = _endr = _data + bytes_read`,
   `_next` stays at `_data`.
2. **Consume**: `sfgetc` / `sfread` advance `_next` toward `_endr`.
3. **Refill**: When `_next >= _endr`, the fast path falls through to
   `_sffilbuf()` which resets and refills.

The fast-path read macro:
```c
/* Legacy: sfio.h:298-299 */
#define __sf_getc(f) \
    (f->_next >= f->_endr ? _sffilbuf(f,0) : (int)(*f->_next++))
```

`Contract:` After a successful read, `_next` has advanced by the number of
bytes consumed. Data between `_data` and `_next` is consumed (may be
overwritten on next fill). Data between `_next` and `_endr` is available.

## Write mode buffer lifecycle

When the stream is in `SFIO_WRITE` mode:

```
Active:   _endw = _endb (fully buffered) or _endw = _data (line buffered)
          _endr = _data (reads disabled)
          _next advances from _data toward _endw as bytes are produced
```

1. **Produce**: `sfputc` / `sfwrite` place bytes at `_next` and advance it.
2. **Flush**: When `_next >= _endw`, `_sfflsbuf()` writes buffer to fd.
   Resets `_next = _data`.
3. **Produce**: Cycle repeats.

The fast-path write macro:
```c
/* Legacy: sfio.h:295-297 */
#define __sf_putc(f,c) \
    (f->_next >= f->_endw ? _sfflsbuf(f,(int)((unsigned char)(c))) : \
     (int)(*f->_next++ = (unsigned char)(c)))
```

### Line buffering trick

`Legacy: sfhdr.h:506`

```c
#define _SFOPENWR(f) ((f)->endw = ((f)->flags&SFIO_LINE) ? (f)->data : (f)->endb)
```

When `SFIO_LINE` is set, `_endw = _data`. This means every `sfputc` falls
through to `_sfflsbuf()`, which checks for newlines and flushes on `'\n'`.
The HIFORLINE threshold (128 bytes, `Legacy: sfhdr.h:552`) provides a
heuristic: if more than 128 bytes are being written at once, the slow path
skips the line-scan and does a bulk write.

## Mode switching

`Legacy: sfmode.c via _sfmode(f, mode, local)`

When switching between read and write (or vice versa), the buffer must be
reconciled:

**Read → Write**:
- Unconsumed read data (`_next` to `_endr`) represents bytes that were
  read from the fd but not consumed. The fd's logical position must be
  adjusted backward by seeking: `f->here -= (f->endb - f->next)`.
- Buffer is then reset for writing: `_next = _data`, `_endr = _data`,
  `_endw = _endb` (or `_data` if line-buffered).

**Write → Read**:
- Pending write data (`_data` to `_next`) must be flushed via `_sfflsbuf()`.
- Buffer is then reset for reading: `_next = _data = _endr` (empty, will
  fill on next read).

`Polarity:` Mode switching is a *cut* — it restructures the buffer's role
from value-producing (write) to value-consuming (read) or vice versa. The
seek/flush is the cost of crossing this polarity boundary.

## Lock state

`Legacy: sfhdr.h:504`

```c
#define SFLOCK(f,l) (void)((f)->mode |= SFIO_LOCK, (f)->endr = (f)->endw = (f)->data)
```

When locked:
- `_endr = _endw = _data`
- Fast-path macros always see `_next >= _endr` (or `_next >= _endw`), so
  they call the slow path
- Slow path checks `SFIO_LOCK` and returns error/EOF

```c
#define SFOPEN(f,l) (void)((l) ? 0 : \
    ((f)->mode &= ~(SFIO_LOCK|SFIO_RC|SFIO_RV), _SFOPEN(f), 0))
```

Unlock restores `_endr`/`_endw` via `_SFOPEN(f)` based on exact mode equality:
- `mode == SFIO_READ`: `_endr = _endb`
- `mode == SFIO_WRITE`: `_endw = _endb` (or `_data` if line-buffered)
- Otherwise (mode has extra bits): `_endr = _endw = _data`

⚠ Hazard: This is exact equality, not flag-test. A stream with
`mode == SFIO_WRITE|SFIO_STRING` hits the else branch.

`Contract:` Every public SFIO function locks on entry, unlocks on exit. The
SETLOCAL/GETLOCAL mechanism (`Legacy: sfhdr.h:483-484`) ensures only the
outermost (non-recursive) call actually unlocks.

## SFIO_PEEK state

Set by `sfreserve()` when it returns a pointer to buffer data without
consuming it. While SFIO_PEEK is set:

- The returned pointer is valid — the buffer won't be refilled
- Stream access is frozen (`SFFROZEN()` returns true for SFIO_PEEK)
- The peek is released by a subsequent `sfread()` with `n == 0` or another
  `sfreserve()` call

`Legacy: sfhdr.h:165` — `SFIO_PEEK 00000400`

`Polarity:` SFIO_PEEK is a suspended cut — the buffer is in a state where
neither production nor consumption can proceed until the peek is released.
This is structurally a thunk (↓N): a computation is suspended into a
storable value (the pointer + length) that must be explicitly forced
(via `sfread(f, buf, 0)` or another `sfreserve`).

## String stream buffer

For `SFIO_STRING` streams (`_file == -1`):

- Buffer is heap-allocated, resizable
- `_data` points to the allocation, `_endb = _data + allocated_size`
- Write past `_endb` triggers a WRITE exception → discipline handler
  extends the buffer via realloc
- No fd I/O — all operations are in-memory
- `sfstruse(f)` NUL-terminates and returns `_data`, resetting `_next`

The string stream extent tracking macro:
```c
/* Legacy: sfhdr.h:555-558 */
#define SFSTRSIZE(f) { Sfoff_t s = (f)->next - (f)->data; \
    if(s > (f)->here) \
        { (f)->here = s; if(s > (f)->extent) (f)->extent = s; } \
}
```

`here` tracks the high-water mark within the current session; `extent`
tracks the all-time maximum. Both are used to determine how much data to
copy during string→file promotion in `sftmp()`.

## Mmap buffer

When `SFIO_MMAP` is set in `bits` (and `MAP_TYPE` is available):

- Buffer is a memory-mapped region of the file
- `_data` points to the mapping, `_endb = _data + mapped_size`
- `SFIO_NMAP` pages mapped at a time (1024 on 64-bit, 32 on 32-bit)
- Unmapping via `SFMUNMAP(f, addr, size)` zeros all five pointers
- `madvise(MADV_SEQUENTIAL)` / `MADV_NORMAL` for access pattern hints

`Legacy: sfhdr.h:434-467`

## Direct I/O

When a request is large enough relative to the buffer, SFIO bypasses the
buffer and does I/O directly to/from the caller's memory:

```c
/* Legacy: sfhdr.h:431-432 */
#define SFDIRECT(f,n) (((ssize_t)(n) >= (f)->size) || \
    ((n) >= SFIO_GRAIN && (ssize_t)(n) >= (f)->size/16))
```

A request qualifies for direct I/O if it's at least as large as the buffer,
or at least 1024 bytes and at least 1/16th of the buffer size. This avoids
the double-copy overhead for bulk transfers.

## Buffer sizing

| Constant | Value | Purpose |
|----------|-------|---------|
| `SFIO_BUFSIZE` | 8192 | Default buffer size |
| `SFIO_GRAIN` | 1024 | Minimum allocation granularity |
| `SFIO_PAGE` | `1024 * sizeof(int) * 2` | Page-sized allocation unit |

`Legacy: sfhdr.h:425-426`

→ C23: Inline accessor functions with `[[nodiscard]]` for buffer queries.
Bounds-checked helpers for pointer arithmetic. `constexpr` for size constants.

## Fast peek macros

```c
/* Legacy: sfhdr.h:545-549 */
#define _SFAVAIL(f,s,n) ((n) = (f)->endb - ((s) = (f)->next))
#define SFRPEEK(f,s,n)  (_SFAVAIL(f,s,n) > 0 ? (n) : \
    ((n) = SFFILBUF(f,-1), (s) = (f)->next, (n)))
#define SFWPEEK(f,s,n)  (_SFAVAIL(f,s,n) > 0 ? (n) : \
    ((n) = SFFLSBUF(f,-1), (s) = (f)->next, (n)))
```

Internal fast path: check if buffer has data (read) or space (write). If not,
trigger fill/flush and retry. Returns available byte count in `n` and buffer
pointer in `s`.

⚠ Hazard: `_SFAVAIL` uses `_endb - _next`, not `_endr - _next`. For reads,
this considers all physically buffered bytes, including past a NUL-replaced
separator. Code that needs only the readable extent should check `_endr`.

## Polarity analysis

The buffer mediates between two polarities:

- **Value** (the data): what's stored between `_data` and `_next` (written) or
  between `_next` and `_endr` (readable). This is the *content*.
- **Computation** (the I/O): syscalls that move data between buffer and fd.
  Triggered when the buffer boundary is hit (read exhausted or write full).

The five pointers are the *polarity boundary* — they encode both the value
extent (data range) and the computation state (where in the fill/flush cycle
we are). Lock state freezes this boundary; mode switching is a polarity
reversal that must reconcile both sides.

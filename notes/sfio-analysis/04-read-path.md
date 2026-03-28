# 04: Read Path

All read operations ultimately flow through `sfrd()` for the actual I/O
dispatch. Higher-level functions manage buffering, record assembly, and
the peek/lock protocol.

## Call graph

```
sfgetc (inline macro)
  → _sffilbuf(f, 0)          [buffer empty]
      → SFRD → sfrd → read(2) / disc->readf / sfpkrd

sfread(f, buf, n)
  [peek release]              direct buffer manipulation
  [normal]
      → SFRD(direct)          if request large enough
      → _sffilbuf(f,-1) → SFRD → sfrd

sfgetr(f, rc, type)
  → SFRPEEK → _sffilbuf(f,-1)
  → memchr for separator
  → _sfrsrv (if cross-buffer)

sfreserve(f, size, type)
  → SFFILBUF(f, iosz)
  → _sfrsrv (overflow to side buffer)

sfmove(fr, fw, n, rc)
  → sfgetr (record mode)
  → SFFILBUF / SFRD (byte mode)

sfungetc(f, c)
  [fast] f->next--
  [slow] sfnew + sfstack (pushback string stream)
```

---

## sfgetc — inline macro

`Legacy: sfio.h:298-299`

```c
#define __sf_getc(f) \
    (f->_next >= f->_endr ? _sffilbuf(f,0) : (int)(*f->_next++))
```

Fast path: if `next < endr`, dereference and advance. One instruction on the
hot path — no function call.

Slow path: calls `_sffilbuf(f, 0)` which refills the buffer and returns the
first byte (consuming it).

`Contract:` Returns the next byte (0–255) or EOF (-1). Advances `_next` by 1.

---

## sfread(f, buf, n)

`Legacy: sfio/sfread.c`

**Signature:** `ssize_t sfread(Sfio_t *f, void *buf, size_t n)`

**Returns:** bytes read (may be < n), 0 on EOF, -1 on error.

### Peek release path (lines 44–71)

When `f->mode & SFIO_PEEK` is set, `sfread` serves as the commit/release
operation for a prior `sfreserve(..., SFIO_LOCKR)` or `sfgetr(..., SFIO_LOCKR)`.

**SFIO_GETR sub-case:** Validates that `buf` is the address of the peeked
record (either `(uchar*)buf + f->val == f->next` for buffer-resident, or
`buf == f->rsrv->data` for rsrv-resident). Clears SFIO_PEEK. Returns 0.

**Plain SFIO_PEEK sub-case:** Validates `(uchar*)buf == f->next` exactly.
Clears SFIO_PEEK. If SFIO_PKRD was set (peek-read on unseekable stream),
issues the real `read()` to consume from the fd. Advances `f->next += n`,
restores `f->endr = f->endb`. Returns n.

⚠ Hazard: Address validation is strict. If you modify `f->next` between
`sfreserve` and the releasing `sfread`, the release fails.

### Normal read path (lines 73–131)

Loop until `n == 0` (satisfied) or error/EOF:

1. Copy buffered data: `r = f->endb - f->next`, clamp to n, memcpy to
   user buffer, advance both `f->next` and output pointer, decrement n.
2. If n == 0, done.
3. Reset `f->next = f->endb = f->data` (discard consumed buffer).
4. Buffer strategy decision:
   - `SFDIRECT(f,n)`: request ≥ buffer size (or ≥ 1024 and ≥ size/16) →
     direct I/O into user buffer via `SFRD(f, buf, n, f->disc)`.
   - Otherwise: refill via `SFFILBUF(f, -1)` and loop.
5. Direct I/O: on success advances output pointer. On EOF or complete
   satisfaction, breaks. On `r < 0` (discipline stack pop), falls through
   to `SFFILBUF`.

`Contract:` Returns total bytes copied. Does NOT set SFIO_EOF directly —
that happens inside `sfrd` → `_sfexcept`.

---

## _sffilbuf(f, n)

`Legacy: sfio/sffilbuf.c`

**Signature:** `int _sffilbuf(Sfio_t *f, int n)`

The buffer refill engine. Parameter `n` controls behavior:

| n | Behavior |
|---|----------|
| < 0 | Fill buffer, return total available bytes |
| = 0 | Fill if empty, return first byte (consuming it). This is sfgetc's slow path |
| > 0 | Ensure ≥ n bytes buffered (may do multiple reads) |

### Core logic

1. Save `f->mode & (SFIO_RC|SFIO_RV|SFIO_LOCK)` and `f->getr` — restored
   before SFRD call so discipline receives the original context.
2. If buffer has data and n ≤ available: return immediately.
3. If not string/mmap and buffer has partial data: slide left (block-aligned
   via `f->blksz` — destination is NOT necessarily `f->data`) to maximize
   contiguous read space.
4. Compute read size:
   - mmap: request n or f->size.
   - Normal: `f->size - (f->endb - f->data)` (remaining buffer space).
   - SFIO_SHARE unseekable with n > 0: cap to n (no read-ahead).
5. Call `SFRD(f, f->endb, r, f->disc)` — reads into trailing buffer space.
6. On success: `r = f->endb - f->next` (total available), break.
7. On r < 0: discipline stack popped, loop again.

**Return:** For n == 0: `r > 0 ? (int)(*f->next++) : EOF`. Otherwise: total
available bytes `r`.

`Contract:` After successful fill, `f->endb` has advanced. Region
`[f->next, f->endb)` is valid buffered data.

⚠ Hazard: When n > 0 and existing data is shifted left, any external
pointers into the old buffer positions are invalidated.

---

## sfreserve(f, size, type)

`Legacy: sfio/sfreserve.c`

**Signature:** `void *sfreserve(Sfio_t *f, ssize_t size, int type)`

The central zero-copy primitive. Returns a pointer to buffered data without
copying, with optional locking.

**Parameters:**

| Parameter | Meaning |
|-----------|---------|
| `size > 0` | Request exactly size bytes |
| `size < 0` | Request at least \|size\| bytes, fill as much as possible |
| `size == 0` | Query/lock with no specific byte requirement |
| `type = 0` | Consume (advance `f->next`) |
| `type = SFIO_LOCKR` | Lock stream, return pointer without consuming |
| `type = SFIO_LASTR` | Return last incomplete record from prior sfgetr |

**Returns:** pointer to data, or NULL. `sfvalue(f)` returns actual available
bytes (which may exceed `size`).

### SFIO_LASTR path

1. If in-buffer remainder matches `f->val`: return `f->next`, advance.
2. Else if `rsrv->slen < 0`: partial record in rsrv. Return `rsrv->data`,
   set `sfvalue = -rsrv->slen`.
3. Else: NULL.

Does NOT lock or set SFIO_PEEK.

### Normal path — refill loop

Iterates until enough data buffered or no progress:

1. If `f->endb - f->next >= |size|`: done.
2. Compute needed I/O size.
3. Call `SFFILBUF(f, iosz)` to fill.
4. For SFIO_LOCKR: break as soon as any data available (even if < size).
5. For non-locking: break if no progress.

### Completion (done label)

**SFIO_LOCKR case:**
- Sets `f->mode |= SFIO_PEEK`.
- Collapses `f->endr = f->endw = f->data` — disables fast-path I/O.
- Stream is now frozen. Only `sfread(f, ptr, n)` can release.

`Polarity:` SFIO_LOCKR has the structure of a thunk (↓N) — computation (the
stream's fill/read machinery) is suspended into a storable value (a pointer +
length). The releasing `sfread(f, ptr, 0)` forces the thunk, completing the
deferred consumption. The peek/release protocol composes like a force/return
pair. Like SFIO_PEEK (see [03-buffer-model](03-buffer-model.md)), this is a
genuine thunk, not a future: the stream is frozen until explicitly released,
making the ↓N label exact for both polarity structure and evaluation strategy
(see SPEC.md §"Tightening the analogies" for the thunk/future distinction).

**Non-locking case:**
- Advances `f->next += (size >= 0 ? size : n)` — but ONLY when
  `data == f->next` (return is from the main buffer). When the return is
  from `rsrv->data`, `f->next` is NOT advanced.
- Data at returned pointer is valid but not exclusively owned.

`Contract:` `sfvalue(f)` always returns the full available extent, not the
subset requested.

⚠ Hazard: `sfvalue` after SFIO_LOCKR may return much more than `size`.
The caller gets `size` bytes of valid commitment but the buffer holds more.

---

## sfgetr(f, rc, type)

`Legacy: sfio/sfgetr.c`

**Signature:** `char *sfgetr(Sfio_t *f, int rc, int type)`

Record-oriented read. Scans for separator `rc` (0–255) in the buffer.

**Type flags:**

| Type | Behavior |
|------|----------|
| `0` | Return record including separator, no NUL termination |
| `SFIO_STRING` | NUL-terminate by overwriting separator (only when `rc != 0`) |
| `SFIO_LASTR` | Return last incomplete record from prior call |
| `SFIO_LOCKR` | Lock stream (set SFIO_PEEK\|SFIO_GETR) |

**Returns:** pointer to record, or NULL. `sfvalue(f)` = record length
(including separator or NUL).

### Fast path (common case)

When the record fits entirely in the current buffer:

1. `memchr(f->next, rc, f->endb - f->next)` finds the separator.
2. If found and no partial data accumulated: return `f->next` directly
   (pointer into the live buffer). Advance `f->next` past the record.
3. No copy, no allocation.

This is the critical performance path — most records fit in one buffer.

### Slow path (cross-buffer records)

When the separator isn't found in the current buffer:

1. Copy `f->next..f->endb` into `rsrv->data` (growing rsrv as needed
   via `_sfrsrv(f, un + n + 1)`).
2. Refill buffer via `SFRPEEK`.
3. Scan for separator in new buffer data.
4. Repeat until found or EOF.

### NUL termination (SFIO_STRING)

When `found && rc != 0 && (type & SFIO_STRING)`:

⚠ Hazard: If the separator IS the NUL character (`rc == 0`), no overwrite
happens even with SFIO_STRING — the separator is already NUL.

- `us[un-1] = '\0'` — overwrites the separator in-place.
- If data is in the main buffer: sets `f->getr = rc` and
  `f->mode |= SFIO_GETR` — marks that the buffer has an embedded NUL.

⚠ Hazard: The in-buffer NUL is destructive. Subsequent reads that don't
know about SFIO_GETR will see a shorter string. The SFIO_GETR bit is the
only guard — cleared on `sfread` peek release.

### SFIO_RC optimization

Before calling `SFRPEEK`/`SFFILBUF`, sfgetr sets:
- `f->getr = rc` — the separator character
- `f->mode |= SFIO_RC` — tells sfrd to do a record-aware peek

If the platform supports peek reads (MSG_PEEK on sockets), `sfrd` calls
`sfpkrd()` which peeks at incoming data and stops at the separator. This
avoids over-reading on pipes/sockets.

### rsrv buffer (Sfrsrv_t)

- `rsrv->slen = 0` — record was complete
- `rsrv->slen < 0` — partial record of `-slen` bytes (recoverable via SFIO_LASTR)
- Shared with sfreserve — interleaved use clobbers state

---

## sfrd(f, buf, n, disc)

`Legacy: sfio/sfrd.c`

**Signature:** `ssize_t sfrd(Sfio_t *f, void *buf, size_t n, Sfdisc_t *disc)`

The low-level I/O dispatch. Called internally via `SFRD(f,b,n,d)` macro
(which sets SFIO_LOCAL first).

### External vs internal calls

- **External** (local == 0): full mode check, sync if buffered data exists,
  reset buffer pointers, handle mmap unmap.
- **Internal** (local != 0): trusts caller's state setup.

### SFIO_PKRD guard

If SFIO_PKRD is set, returns -1 immediately — a peek-read was done but
bytes haven't been consumed yet. A second read would skip past them.

### Dispatch priority

1. String stream: return remaining extent, or go to exception.
2. `SFDISC(f, dc, readf)` — walk discipline chain for first non-NULL readf.
3. SFIO_IOCHECK: pre-read exception notification via `dc->exceptf`.
4. Mmap: compute aligned mapping, mmap, set buffer pointers.
5. SFIO_SHARE + seekable: seek to `f->here` to establish position.
6. Actual I/O:
   - Discipline `readf`: call with `SFIO_DCDOWN` set in `f->bits` (not `mode`).
   - `/dev/null`: return 0.
   - Unseekable shared + SFIO_RC/RV: `sfpkrd()` with record separator.
   - Default: `read(f->file, buf, n)`.
7. On success: update `f->here += r`, update `f->extent`, if buf is inside
   buffer set `f->endb = f->endr = buf + r`.

### Exception handling

After `r <= 0`, calls `_sfexcept(f, SFIO_READ, r, dc)`:

| Return | Meaning |
|--------|---------|
| `SFIO_ECONT` | Retry (e.g., after EINTR) |
| `SFIO_EDONE` | Stop, return r |
| `SFIO_EDISC` | Continue with next discipline |
| `SFIO_ESTACK` | Stack popped, caller re-enters loop (returns -1) |

`Contract:` If `buf` was `f->endb` (sffilbuf pattern), after success
`f->endb = f->endr = buf + r`. The buffer region `[f->next, f->endb)` is
valid.

---

## sfpkrd(fd, buf, n, rc, tm, action)

`Legacy: sfio/sfpkrd.c`

**Signature:** `ssize_t sfpkrd(int fd, void *buf, size_t n, int rc, long tm, int action)`

Low-level peek-read on unseekable fds (pipes, sockets).

| action | Behavior |
|--------|----------|
| 0 | Plain `read(fd, buf, n)` |
| > 0 | Peek via `recv(MSG_PEEK)`, optionally stop at rc delimiter |
| ≤ 0 | Read with select timeout and/or record counting |

On platforms with `_socket_peek`: uses `recv(fd, buf, n, MSG_PEEK)` to read
without consuming. If `rc >= 0`, scans peeked data for the delimiter.

Used by sfrd when `SFIO_RC|SFIO_RV` mode bits indicate record-aware reading
on shared unseekable streams.

---

## sfmove(fr, fw, n, rc)

`Legacy: sfio/sfmove.c`

**Signature:** `Sfoff_t sfmove(Sfio_t *fr, Sfio_t *fw, Sfoff_t n, int rc)`

Bulk transfer between streams.

### Record mode (rc ≥ 0)

Uses `sfgetr(fr, rc, 0)` per record, then `SFWRITE(fw, cp, r)`. Counts
records (not bytes). On write failure, seeks both streams back if seekable.

### Byte mode (rc < 0)

1. If fw is NULL and fr seekable: seek forward (skip).
2. Direct transfer optimizations: read directly into fw's buffer, or
   malloc a transfer buffer for large moves.
3. Standard path: fill fr's buffer, copy/write to fw.
4. Handle partial writes by seeking back.

⚠ Hazard: Return value counts records in record mode, bytes in byte mode.
The `Sfoff_t` type accommodates both but the interpretation differs.

---

## sfungetc(f, c)

`Legacy: sfio/sfungetc.c`

**Signature:** `int sfungetc(Sfio_t *f, int c)`

**Fast path:** If `f->next > f->data && f->next[-1] == (uchar)c`: decrement
`f->next`. O(1).

**Slow path:** Creates a string stream, pushes it via `sfstack(f, uf)`.
Future reads drain the pushed stream first. The `_uexcept` discipline
auto-pops when the unget stream is exhausted.

⚠ Hazard: If the pushed-back byte differs from what's at `next[-1]`, the
fast path doesn't apply — even for consecutive pushbacks of the same byte.

---

## Key invariants

1. **sfread with SFIO_PEEK releases the lock.** This is the only sanctioned
   way to release a peek lock from sfreserve/sfgetr.

2. **sfvalue returns full extent, not requested size.** After
   `sfreserve(f, 10, SFIO_LOCKR)`, `sfvalue(f)` may return 4096.

3. **rsrv is shared** between sfgetr and sfreserve. Don't interleave
   record reads with non-record reserves on the same stream.

4. **SFIO_GETR marks in-buffer NUL mutation.** Only set when sfgetr
   overwrites a separator in the main buffer (SFIO_STRING mode).

5. **SFIO_PKRD means data is buffered but not consumed from fd.**
   The releasing `sfread` re-issues the `read()` to actually consume.

→ C23: `[[nodiscard]]` on all read functions. `static inline` replacing
sfgetc/sfeof/sferror/sffileno/sfvalue macros.

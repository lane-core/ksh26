# 05: Write Path

All write operations ultimately flow through `sfwr()` for actual I/O dispatch.
Higher-level functions manage buffering, string extension, line-flush, and the
NUL sentinel contract.

## Call graph

```
sfputc (inline macro)
  → _sfflsbuf(f, c)         [buffer full]
      → SFWR → sfwr → write(2) / disc->writef

sfwrite(f, buf, n)
  [peek commit]              direct cursor advance
  [normal]
      → SFWR(direct)         if request large enough
      → _sfflsbuf(f,-1) → SFWR → sfwr

sfputr(f, s, rc)
  → SFWPEEK → _sfflsbuf
  → byte-at-a-time copy or memcpy
  → SFWRITE for overflow

sfnputc(f, c, n)
  → MEMSET into buffer
  → SFWRITE for overflow

sfprintf / sfvprintf
  → SFputc / SFwrite macros (shadow pointer d)
  → SFFLSBUF when shadow buffer exhausted
```

---

## sfputc — inline macro

`Legacy: sfio.h:295-297`

```c
#define __sf_putc(f,c) \
    (f->_next >= f->_endw ? _sfflsbuf(f,(int)((unsigned char)(c))) : \
     (int)(*f->_next++ = (unsigned char)(c)))
```

Fast path: if `next < endw`, store `c` at `*next`, increment `next`. Returns
the stored byte value. No function call, no lock, no NUL sentinel.

Slow path: calls `_sfflsbuf(f, c)` which flushes and writes `c`.

### Line buffering gate

`Legacy: sfhdr.h:506`

When `SFIO_LINE` is set, `_endw = _data`. Since `_next >= _data` always,
every `sfputc` triggers the slow path, where `_sfflsbuf` checks for `'\n'`
and flushes on newline.

---

## _sfflsbuf(f, c)

`Legacy: sfio/sfflsbuf.c`

**Signature:** `int _sfflsbuf(Sfio_t *f, int c)`

| c | Behavior |
|---|----------|
| ≥ 0 | Flush buffer, then write this byte. Returns c on success |
| -1 | Flush only. Returns remaining write space |

### String stream extension (lines 50–62)

When buffer is full and `SFIO_STRING` set:
```c
w = ((f->bits & SFIO_PUTR) && f->val > 0) ? f->val : 1;
SFWR(f, data, w, f->disc);
```

Calls `sfwr()` which for string streams computes `n + (f->next - f->data)` as
the new size, then calls `_sfexcept()` → `realloc()`. After extension,
`f->data/next/endb` point to the larger buffer.

### File stream flush (lines 88–109)

```c
w = SFWR(f, data, n, f->disc);
if(w > 0 && (n -= w) > 0)
    memmove(f->data, data + w, n);  /* slide unwritten remainder left */
f->next = f->data + n;
```

Partial write handling: slides unwritten data to buffer front. `SFISALL(f, isall)`
controls retry behavior — when `SFIO_SHARE`, `SFIO_APPENDWR`, `SFIO_WHOLE`, or
`SFIO_RV` is active, keeps flushing until all data is written.

### Writing character c (lines 65–75)

If space available after flush: `*f->next++ = c`. For line-buffered streams,
`c == '\n'` triggers another flush cycle.

If unbuffered (size == 0): writes single byte directly via `SFWR`.

`Contract:` Does NOT write a NUL sentinel at `*_next` after the byte.

---

## sfwrite(f, buf, n)

`Legacy: sfio/sfwrite.c`

**Signature:** `ssize_t sfwrite(Sfio_t *f, const void *buf, size_t n)`

**Returns:** bytes written, -1 on error.

### Peek commit path (lines 43–75)

When `SFIO_PEEK` set: `sfwrite` commits a prior `sfreserve` reservation.
Clears SFIO_PEEK. The actual mechanics are more complex than read-side
peek release:

- **SFIO_PKRD sub-case:** For unseekable streams where peek-read was done,
  issues a real `read()` to consume the peeked bytes from the fd (via a
  local buffer). This ensures the fd position matches the buffer state.
- **Co-process sub-case:** For `f->proc` streams, advances `f->next` and
  caches unconsumed data in `f->proc->rdata`.
- **Normal case:** Clears the peek flag; the write loop handles any
  remaining positioning.

### Main write loop (lines 78–137)

1. **Self-buffer shortcut** (line 89): If `buf == f->next` (committing
   reserved space), just advance `f->next += w`. No copy.

2. **Flush decision** (line 98): Flush when no space, or when
   `SFIO_WHOLE && available < n`.

3. **Direct I/O** (line 119): When buffer empty and `SFDIRECT(f,n)` true
   (n ≥ buffer size, or n ≥ 1024 and ≥ size/16), write directly to fd
   via `SFWR(f, buf, n, disc)`. Bypasses double-copy.

4. **Buffered copy** (line 126): `memmove(f->next, s, w)`, advance `f->next`.

### Post-loop handling

- **Shared pipes** (line 140): `extent < 0 && SFIO_SHARE && !SFIO_PUBLIC` →
  always flush after write for immediate delivery.
- **Line buffering** (line 144): Scan last `min(buffer_used, bytes_written)`
  bytes for `'\n'`. If found (or ≥ HIFORLINE=128 bytes), flush.

`Contract:` Does NOT write a NUL sentinel.

---

## sfputr(f, s, rc)

`Legacy: sfio/sfputr.c`

**Signature:** `ssize_t sfputr(Sfio_t *f, const char *s, int rc)`

Writes NUL-terminated string `s` (without the NUL). If `rc >= 0`, appends
that byte as a separator after the string.

### Byte-at-a-time copy (lines 98–104)

```c
for(; p > 0; --p, ++ps, ++s)
    if((*ps = *s) == 0)
        break;
```

This is the **origin of the incidental NUL sentinel**: the loop copies each byte
including the NUL terminator to `*ps`, then breaks. After the break, `f->next`
is set to `ps`, so `*f->next == 0`.

⚠ Hazard: This NUL is incidental, path-dependent, and NOT present on the
whole-buffer path (which uses `memcpy(ps, s, n)` where `n = strlen(s)` —
NUL not copied). Do not rely on this in sfio code.

### SFIO_PUTR hint protocol (lines 41–48)

For string stream extension: `f->val = remaining_string_len + (rc>=0)`,
`f->bits |= SFIO_PUTR`. This hints `_sfflsbuf` about how much space to
request from the extension handler.

### SFIO_WHOLE path (lines 54–87)

When `SFIO_WHOLE` set or buffer empty: attempts to write entire string +
separator in one shot. If buffer can't hold it all, allocates an rsrv buffer,
assembles the complete output there, then calls `SFWRITE`.

---

## sfwr(f, buf, n, disc)

`Legacy: sfio/sfwr.c`

**Signature:** `ssize_t sfwr(Sfio_t *f, const void *buf, size_t n, Sfdisc_t *disc)`

Low-level write dispatch. Called via `SFWR(f,b,n,d)` macro.

### String stream path (line 144)

Does not write — computes `w = n + (f->next - f->data)` as new buffer size
and passes to `_sfexcept()` for realloc. Buffer extension happens here.

### File stream path

1. **SFIO_IOCHECK**: pre-write exception notification.
2. **Seek positioning**: `SFIO_APPENDWR` seeks to EOF. `SFIO_SHARE` seeks
   to `f->here`.
3. **Discipline chain**: `SFDISC(f, dc, writef)` finds first writef, calls
   with SFIO_DCDOWN set.
4. **/dev/null**: `w = n` (pretend all written).
5. **Hole-preserving** (`sfoutput`): for large writes on seekable streams,
   scans for zero-page runs and uses `lseek` to create sparse files.
6. **Direct write**: `write(f->file, buf, n)`.
7. **Position update**: `f->here += w`.

### Exception handling

Same as read path: `_sfexcept()` returns ECONT/EDONE/EDISC/ESTACK.

---

## sfnputc(f, c, n)

`Legacy: sfio/sfnputc.c`

**Signature:** `ssize_t sfnputc(Sfio_t *f, int c, size_t n)`

Writes `n` copies of byte `c`.

**Fast path:** If buffer has room for all n bytes, `MEMSET(f->next, c, n)`,
advance `f->next += n`. For `c == '\n'` on line-buffered streams, flushes.

**Slow path:** Uses a 128-byte local buffer filled with `c`, calls `SFWRITE`
in a loop.

`Contract:` Does NOT write a NUL sentinel.

---

## sfvprintf — format engine write mechanics

`Legacy: sfio/sfvprintf.c`

### Shadow pointer optimization

```c
uchar *d, *endd;
#define SFBUF(f)  (d = f->next, endd = f->endb)
#define SFEND(f)  ((n_output += d - f->next), (f->next = d))
```

Caches `f->next` in local `d` for hot-loop performance. Flushes back to
`f->next` via `SFEND` before any actual I/O.

### Output macros

```c
#define SFputc(f,c)   { if(d < endd) *d++ = c; else { SFEND(f); SMputc(f,c); SFBUF(f); } }
#define SFwrite(f,s,n) { if(d+n <= endd) copy; else { SFEND(f); SMwrite(f,s,n); SFBUF(f); } }
```

Fast path: direct store into shadow buffer. Slow path: flush back to stream,
call real sfio functions, re-load shadow.

`Contract:` Does NOT write a NUL sentinel.

---

## NUL sentinel contract — complete map

### sfio layer: NO guarantee

No sfio write function writes `*_next = 0` as a deliberate postcondition.
The only NUL is the incidental one from sfputr's byte-at-a-time loop
(path-dependent, not present on whole-buffer path).

### stk layer: EXPLICIT guarantee

`Legacy: stk.c:88`

```c
#define STK_SENTINEL(sp) \
    do { if((sp)->_next && (sp)->_next < (sp)->_endb) *(sp)->_next = 0; } while(0)
```

Called after every stk write operation:

| Function | Calls STK_SENTINEL? |
|----------|---------------------|
| `stkputc` | Yes |
| `stkputs` | Yes |
| `stkwrite` | Yes |
| `stknputc` | Yes |
| `stkalloc` | Yes |
| `stkopen` | Yes |
| `stkset` | Yes |
| `stkgrow` | Yes |
| `stkvprintf` | No (vsnprintf already wrote NUL) |
| `_stkseek` | **No** — deliberate |
| `stkfreeze` | No |

`_stkseek` deliberately omits the sentinel because seek is a positioning
operation (cut), not a write (positive effect). Code uses seek-back-and-read
patterns where data above `_next` must be preserved. Writing a sentinel in
seek destroyed the first byte → "bad trap" for all pseudosignals (1777 test
failures). See [11-stk-allocator](11-stk-allocator.md).

`Polarity:` Writes are positive (produce data, sentinel is postcondition of
production). Seek is a cut (restructures context). Sentinel in a cut violates
polarity discipline.

---

## SFIO_WHOLE semantics

`Legacy: sfio.h:134` — `SFIO_WHOLE 0020000`

"Preserve wholeness of sfwrite/sfputr." Makes writes attempt all-or-nothing:

- **sfwrite**: Forces flush when `available < n` instead of writing what fits.
  Direct I/O path triggered when buffer too small.
- **sfputr**: Takes whole-buffer path (assemble complete output, single write).
- **_sfflsbuf**: `SFISALL()` returns true → keeps flushing until all data
  written.

⚠ Hazard: Does NOT guarantee OS-level atomicity. Only affects SFIO buffer
management decisions. A single `write()` syscall may still produce a partial
write at the kernel level.

---

## Line buffering

When `SFIO_LINE` set:

1. `_endw = _data` — every `sfputc` calls `_sfflsbuf`.
2. `_sfflsbuf`: if `c == '\n'`, triggers flush cycle.
3. `sfwrite` post-loop: scans last bytes for `'\n'`, flushes if found
   (or if ≥ 128 bytes written — `HIFORLINE` threshold).
4. `sfputr` with `rc == '\n'`: the separator write triggers line flush.

The `HIFORLINE` heuristic (128 bytes, `Legacy: sfhdr.h:552`) avoids the
cost of scanning for newlines in large writes — just flush the whole thing.

---

## Direct I/O

`Legacy: sfhdr.h:431-432`

```c
#define SFDIRECT(f,n) (((ssize_t)(n) >= (f)->size) || \
    ((n) >= SFIO_GRAIN && (ssize_t)(n) >= (f)->size/16))
```

Bypasses buffering when the request is large enough relative to the buffer.
Data goes directly from the caller's memory to `sfwr()`. This avoids the
memcpy into the stream buffer for bulk writes.

---

## Lock protocol

Every public write function:
1. `GETLOCAL(f, local)` — extract SFIO_LOCAL.
2. Mode check via `SFMODE(f, local) != SFIO_WRITE && _sfmode(...)`.
3. `SFLOCK(f, local)` — set SFIO_LOCK, collapse `_endw = _endr = _data`.
4. Do work.
5. `SFOPEN(f, local)` — clear lock, restore `_endw` based on mode.

When `local` is true (internal call via SFWR/SFWRITE/etc.), lock/unlock
are no-ops — the outer call holds the lock.

---

## Error returns

| Function | Success | Error |
|----------|---------|-------|
| `sfputc` | byte value (0–255) | -1 via _sfflsbuf |
| `_sfflsbuf(c≥0)` | c | -1 |
| `_sfflsbuf(-1)` | remaining space | -1 |
| `sfwrite` | bytes written (≤ n) | -1 |
| `sfputr` | bytes written | -1 |
| `sfnputc` | n | -1 or partial |
| `sfwr` | bytes written | -1 or 0 |

→ C23: `[[nodiscard]]` on all write functions. `static inline` replacing
the sfputc macro.

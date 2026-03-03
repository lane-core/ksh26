# 06: Lifecycle

Stream creation, opening, closing, buffer management, fd manipulation,
stacking, and swapping. These operations define the stream's identity and
manage transitions between states.

## sfnew(oldf, buf, size, file, flags)

`Legacy: sfio/sfnew.c:28-114`

**Signature:** `Sfio_t *sfnew(Sfio_t *oldf, void *buf, size_t size, int file, int flags)`

Creates or reinitializes a stream.

### Allocation decision tree

1. `oldf` with `SFIO_EOF` set → `SFCLEAR(oldf)`, reuse as fresh struct.
2. `oldf` with `SFIO_AVAIL` → if `SFIO_STATIC`, reuse (sfstdin/out/err).
   If NOT `SFIO_STATIC`, return NULL (non-static AVAIL streams can't be reused).
3. `oldf` is open → close it first, optionally free old buffer.
4. No `oldf` → check if fd 0/1/2 maps to an AVAIL standard stream.
   If so, reuse. Otherwise `malloc(sizeof(Sfio_t))`.

### State after initialization

```c
f->mode  = (SFIO_READ or SFIO_WRITE) | SFIO_INIT;
f->flags = (flags & SFIO_FLAGS) | preserved_MALLOC_STATIC;
f->bits  = SFIO_BOTH if flags has both READ|WRITE;
f->file  = file;
f->endb = f->endr = f->endw = f->next = f->data;  /* all collapsed */
```

`Contract:` Stream is in SFIO_INIT state — lazy initialization deferred to
first I/O via `_sfmode()`. Structurally valid, operationally inert.

### Notify callback

If `_Sfnotify` registered: `(*_Sfnotify)(f, SFIO_NEW, (void*)(long)f->file)`.

### String stream eager init

If `SFIO_STRING` in flags: `_sfmode(f, f->mode & SFIO_RDWR, 0)` called
immediately (no fd to probe, init is cheap).

---

## sfopen(f, string, mode)

`Legacy: sfio/_sfopen.c:30-128`

**Signature:** `Sfio_t *sfopen(Sfio_t *f, const char *string, const char *mode)`

### Mode string parsing (_sftype)

| Char | Effect |
|------|--------|
| `r` | SFIO_READ, O_RDONLY |
| `w` | SFIO_WRITE, O_WRONLY\|O_CREAT\|O_TRUNC |
| `a` | SFIO_WRITE\|SFIO_APPENDWR, O_WRONLY\|O_APPEND\|O_CREAT |
| `+` | Add SFIO_RDWR, O_RDWR |
| `s` | SFIO_STRING |
| `b` | O_BINARY |
| `t` | O_TEXT |
| `e` | O_CLOEXEC |
| `x` | O_EXCL |
| `W` | SFIO_WCWIDTH |

### Operational sequence

1. Parse mode string.
2. If `f` given and `string == NULL` and not string stream → modify existing
   stream flags (change access mode, set O_APPEND/O_BINARY via fcntl).
3. String stream → `sfnew(f, (char*)string, size_or_UNBOUND, -1, sflags)`.
4. File stream → `open(string, oflags, 0666)` with EINTR retry, then
   `sfnew(f, NULL, SFIO_UNBOUND, fd, sflags)`.

→ C23: `[[nodiscard]]` on return value.

---

## _sfmode(f, wanted, local) — mode switching and lazy init

`Legacy: sfio/sfmode.c:291-528`

The central mode-switching function. Three jobs: (a) lazy initialization on
first use, (b) read↔write switching for r+w streams, (c) error dispatch.

### SFIO_INIT path (lazy initialization)

1. `_sfsetpool(f)` — register with `_Sfpool`, install `atexit(_sfcleanup)`.
2. If `wanted == 0`: done (pool registration only).
3. String stream with valid data/size: initialize in-place (set endb, extent, etc.).
4. Otherwise: `SFSETBUF(f, f->data, f->size)` → drives `sfsetbuf()` for
   seekability probe, buffer sizing, mmap eligibility, terminal detection.

### Read → Write transition

- String: `SFSTRSIZE(f)`, set `endb = data + extent`.
- File: flush pending reads isn't needed, but unconsumed buffer must be
  accounted for via seek-back: `here -= (endb - next)`. Reset all pointers.
  Restore coprocess read data if applicable.

### Write → Read transition

- String: set `endb = data + size`.
- File: flush pending writes via `SFFLSBUF(f,-1)`. Reset pointers.
  For seekable: seek to `here` to establish position.
  For mmap: unmap and re-sfsetbuf.

`Polarity:` Mode switching is a cut — restructures the buffer's role from
producing (write) to consuming (read) or vice versa.

### Precondition checks

- If frozen (PUSH/LOCK/PEEK) and not local, or if `f->file < 0` and not
  string: invoke `disc->exceptf(SFIO_LOCKED)` in a loop until unfrozen or error.
- If SFIO_GETR set: restore the separator byte (`next[-1] = getr`).
- If SFIO_POOL: promote to pool head via `_sfpmove(f, 0)`.

---

## sfsetbuf(f, buf, size) — buffer initialization

`Legacy: sfio/sfsetbuf.c:88-410`

**Signature:** `void *sfsetbuf(Sfio_t *f, void *buf, size_t size)`

Called on first I/O (via SFIO_INIT path) or explicitly.

### File stat and seekability probe

`fstat(f->file, &st)` + `lseek(f->file, 0, SEEK_CUR)`:
- Seekable: `f->extent = st.st_size`, `f->here` = current position.
- Unseekable: `f->extent = -1, f->here = 0`.
- Terminal: set `SFIO_LINE | SFIO_WCWIDTH`, bufsize = SFIO_GRAIN.
- `/dev/null`: `SFSETNULL(f)`.

### Buffer size selection (when size == SFIO_UNBOUND)

Priority: reuse old size → 0 for sfstderr → SFIO_GRAIN for strings →
round-up for small files → `max(_Sfpage, bufsize)`.

### Mmap eligibility

`SFIO_MMAP` if: no explicit buf, not string, not r+w, read mode, seekable,
no discipline readf. Size = `SFIO_NMAP * max(_Sfpage, bufsize)`.

### Buffer assignment

```c
f->next = f->data = f->endr = f->endw = (uchar*)buf;
f->endb = buf ? ((mode==READ) ? f->data : f->data+size) : NULL;
```

Read mode: `endb = data` (empty, fill on first read).
Write mode: `endb = data + size` (full buffer available).

**Returns:** old buffer pointer (freed if SFIO_MALLOC and replaced).

---

## sfsetfd(f, newfd) — fd change

`Legacy: sfio/sfsetfd.c:43-125`

### Normal fd change (oldfd ≥ 0, newfd ≥ 0)

`fcntl(oldfd, F_DUPFD, newfd)` then `close(oldfd)`. Finds the **lowest
available fd >= newfd**, not necessarily exactly newfd.

⚠ Hazard: If fd `newfd` is already open, the stream ends up at a
different fd. For exact placement, `dup2` would be needed (sfio uses
`F_DUPFD`).

### Freeze/detach (newfd < 0)

Syncs pending data, unmaps mmap, resets to SFIO_INIT state. The stream
becomes logically uninitialized — next I/O will re-probe.

### Notify

`(*_Sfnotify)(f, SFIO_SETFD, (void*)(long)newfd)` before assignment.

---

## sfstack(f1, f2) — source stacking

`Legacy: sfio/sfstack.c:27-93`

Pushes `f2` onto `f1`. Reads from `f1` drain `f2` first; when `f2` is
exhausted, `_sfexcept` auto-pops and reads resume from the original `f1`.

### Identity-preserving swap

The caller's `f1` pointer must continue to refer to the active stream.
SFIO achieves this by swapping struct contents via `sfswap(f1, f2)`:
after the swap, address `f1` holds `f2`'s state (the new top), and `f2`
holds the original `f1` state (now pushed underneath).

### Push sequence (f2 != NULL)

1. Mode-normalize both streams.
2. Guard: `f2->push != NULL` → can't push an already-pushed stream.
3. Pool management: if either is at pool head, move another stream there.
4. `sfswap(f1, f2)` — swap contents.
5. Swap `rsrv` back (rsrv stays with its original pointer identity).
6. Freeze `f2` with `SFIO_PUSH`, set `f1->push = f2`.

### Pop sequence (f2 == SFIO_POPSTACK / NULL)

1. `f2 = f1->push`. Clear SFIO_PUSH.
2. `sfswap(f1, f2)` — reverse the swap.
3. `f1` now holds the underlying stream. `f2` holds the popped top.
4. Return `f2` (caller may sfclose it).

### Interaction with sfclose

`sfclose` walks the push chain: while `f->push` exists, pops and closes
each pushed stream recursively.

`_sfexcept` auto-pops on EOF: when `f->push` is set and the buffer is
exhausted, pops the stack and returns `SFIO_ESTACK` (retry on underlying).

---

## sfswap(f1, f2) — state exchange

`Legacy: sfio/sfswap.c:30-112`

**Signature:** `Sfio_t *sfswap(Sfio_t *f1, Sfio_t *f2)`

Physically exchanges the contents of two `Sfio_t` structs. Returns `f2`.

### Swap mechanism

```c
Sfio_t tmp;
memcpy(&tmp, f1, sizeof(Sfio_t));
memcpy(f1, f2, sizeof(Sfio_t));
memcpy(f2, &tmp, sizeof(Sfio_t));
```

### What stays with the address vs what moves

| Stays with address | Moves with state |
|-------------------|-----------------|
| `SFIO_STATIC` flag | fd, buffer, disciplines |
| Pool slot (fixed up) | push link, rsrv, proc |
| Mode bits (restored) | here, extent, all cursors |

### NULL destination

If `f2 == NULL`: select an AVAIL standard stream slot (fd 0/1/2), or
malloc a new Sfio_t. Creates a "dead" destination to hold the displaced
state.

`Polarity:` sfswap is the fundamental operation for I/O redirections and
stream stacking. It's a polarity boundary crossing — the identity (address)
stays fixed while the computational content (state) moves.

---

## sfclose(f) — shutdown

`Legacy: sfio/sfclose.c:27-156`

### Sequence

1. Pop full stack: while `f->push`, pop and close each pushed stream.
2. Discipline cleanup: if not in SFIO_INIT, sync.
3. `SFRAISE(f, local ? SFIO_NEW : SFIO_CLOSING, NULL)` — notify disciplines.
   ⚠ Hazard: On a local close (reopening via sfnew), disciplines see
   `SFIO_NEW`, not `SFIO_CLOSING`. A discipline that handles only
   `SFIO_CLOSING` for cleanup will miss this path.
4. Remove from pool.
5. Free buffer (if SFIO_MALLOC), unmap mmap.
6. `(*_Sfnotify)(f, SFIO_CLOSING, (void*)(long)f->file)`.
   Note: buffer is already freed at this point.
7. `close(f->file)`, set `f->file = -1`.
8. `SFKILL(f)` — sets `mode = SFIO_AVAIL | SFIO_LOCK`.
9. Free rsrv, close coprocess via `_sfpclose`.
10. `SFRAISE(f, SFIO_FINAL, NULL)`.
11. If `SFIO_STATIC`: `f->mode = SFIO_AVAIL` (overwrites SFKILL's value,
    dropping the LOCK bit). Enables reuse by sfnew.
    Otherwise: `free(f)`.

### SFIO_AVAIL reuse mechanism

`sfstdin`, `sfstdout`, `sfstderr` are `SFIO_STATIC`. After close, they get
`mode = SFIO_AVAIL` instead of being freed. `sfnew` checks for AVAIL slots
when allocating for fd 0/1/2 — enables reopening standard streams.

---

## _sfcleanup — atexit handler

`Legacy: sfio/sfmode.c:57-98`

Registered on first `_sfsetpool()` call. Sets `_Sfexiting = 1001` to suppress
further buffering, calls `sfsync(NULL)`, then walks all streams: raises
`SFIO_ATEXIT`, unbuffers non-string write streams.

---

## Notify callback invocation points

| Event | Where | Data arg |
|-------|-------|----------|
| `SFIO_NEW` (0) | sfnew.c:108 | fd |
| `SFIO_CLOSING` (4) | sfclose.c:112 | fd (before close) |
| `SFIO_SETFD` (-1) | sfsetfd.c:110 | new fd |

Registered via `sfnotify(callback)`. Single global hook — typically used by
ksh to maintain its sftable/fdstatus arrays (see
[10-ksh-integration](10-ksh-integration.md)).

→ C23: `[[nodiscard]]` on sfopen/sfnew. `nullptr` for SFIO_POPSTACK/SFIO_POPDISC
sentinel values.

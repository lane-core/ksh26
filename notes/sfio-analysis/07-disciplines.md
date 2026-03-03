# 07: Disciplines

Disciplines are SFIO's extension mechanism — a singly-linked stack of
callback structs that intercept read, write, seek, and exception operations.
Each discipline mediates between the stream's buffer and the underlying
data source.

## Sfdisc_t structure

`Legacy: sfio.h:49-55`

```c
struct _sfdisc_s {
    Sfread_f    readf;      /* ssize_t (*)(Sfio_t*, void*, size_t, Sfdisc_t*) */
    Sfwrite_f   writef;     /* ssize_t (*)(Sfio_t*, const void*, size_t, Sfdisc_t*) */
    Sfseek_f    seekf;      /* Sfoff_t (*)(Sfio_t*, Sfoff_t, int, Sfdisc_t*) */
    Sfexcept_f  exceptf;    /* int (*)(Sfio_t*, int, void*, Sfdisc_t*) */
    Sfdisc_t*   disc;       /* next discipline in chain */
};
```

Any callback can be NULL — operations with NULL handlers pass through to
the next discipline (or to the raw syscall at the bottom).

`Polarity:` The discipline stack as a whole mediates between the stream's
buffer (value) and the OS (computation). Individual disciplines are morphisms
within this pipeline — they transform data at the same logical level (bytes
→ bytes). The stack's endpoints are the polarity boundary; the links are not
individually shifts. The exception is `_tmpexcept`, which genuinely changes
the computation substrate (see [09-string-and-temp](09-string-and-temp.md)).

---

## SFDISC traversal macro

`Legacy: sfhdr.h:520-527`

```c
#define SFDISC(f,dc,iof) \
    { Sfdisc_t* d; \
      if(!(dc)) d = (dc) = (f)->disc; \
      else d = (f->bits&SFIO_DCDOWN) ? ((dc) = (dc)->disc) : (dc); \
      while(d && !(d->iof)) d = d->disc; \
      if(d) (dc) = d; \
    }
```

Walks the chain from `dc` (or `f->disc`) to find the first discipline with
a non-NULL handler for operation `iof` (readf/writef/seekf). If
`SFIO_DCDOWN` is set (inside a discipline callback), starts one step down
from the current discipline — this implements continuation-style dispatch.

---

## SFRD/SFWR/SFSK dispatch macros

`Legacy: sfhdr.h:528-542`

```c
#define SFDCRD(f,buf,n,dc,rv) \
    { int dcdown = f->bits&SFIO_DCDOWN; f->bits |= SFIO_DCDOWN; \
      rv = (*dc->readf)(f,buf,n,dc); \
      if(!dcdown) f->bits &= ~SFIO_DCDOWN; }
```

Sets SFIO_DCDOWN before calling the discipline, clears it after (unless it
was already set — handles nested discipline calls). Same pattern for
SFDCWR and SFDCSK.

`Contract:` SFIO_DCDOWN prevents the SFDISC macro from re-walking the chain
from the top — it skips to `dc->disc` instead, ensuring proper bottom-up
discipline traversal.

---

## sfdisc(f, disc) — push and pop

`Legacy: sfio/sfdisc.c:90-251`

### Query: sfdisc(f, (Sfdisc_t*)f)

Returns `f->disc` without modification.

### Push (disc != NULL, disc != SFIO_POPDISC)

1. Mode-normalize the stream.
2. `SFSYNC(f)` — flush/sync buffer.
3. If buffer has data (`n > 0`): notify both existing and incoming
   disciplines with `SFIO_DBUFFER` event. Return NULL if either returns
   negative (positive/zero means OK to proceed).
4. **Buffered-data cache** (read streams with readf): If there is unread
   data and the new discipline has a `readf`, create a `Dccache_t`
   temporary discipline containing a copy of the buffered bytes. Insert
   it **below** the new discipline:
   `f->disc → new-disc → Dccache → old-chain`.
   Its `readf` drains the cache; when exhausted, it self-removes and
   frees itself.
5. Notify current discipline: `(f->disc->exceptf)(f, SFIO_DPUSH, disc, f->disc)`.
   Handle the edge case where the current discipline pops itself in response.
6. Cycle check: walk chain, abort if `disc` already present.
7. Link: `disc->disc = f->disc; f->disc = disc`.
8. If effective read/write/seek functions changed: reinit buffer via `sfsetbuf()`.

### Pop (disc == NULL / SFIO_POPDISC)

1. Guard: if a `Dccache_t` is **directly below** the top discipline
   (`f->disc->disc->readf == _dccaread`), refuse to pop. A Dccache
   deeper in the chain does NOT trigger this guard.
2. Notify: `(d->exceptf)(f, SFIO_DPOP, d->disc, d)`. Return NULL if negative.
3. Unlink: `f->disc = d->disc`.
4. Return `d` (caller may free it).
5. Reinit check as with push.

### Dccache_t — temporary buffered-data discipline

`Legacy: sfio/sfdisc.c:42-88`

```c
typedef struct { Sfdisc_t disc; uchar *data; uchar *endb; } Dccache_t;
```

`_dccaread` serves cached bytes to the new discipline. When cache exhausted,
splices itself out of the chain and `free()`s itself. Ensures the new
discipline gets a seamless data stream including pre-push buffered data.

This solves a subtle ordering problem: without the cache, pushing a
discipline onto a read stream with buffered data would cause those bytes to
be re-read through the new discipline (which might transform them
differently the second time).

---

## _sfexcept — exception handler

`Legacy: sfio/sfexcept.c:25-122`

**Signature:** `int _sfexcept(Sfio_t *f, int type, ssize_t io, Sfdisc_t *disc)`

Called by read/write/seek primitives when an I/O operation returns ≤ 0.

### Parameters

| Parameter | Meaning |
|-----------|---------|
| `type` | SFIO_READ (1), SFIO_WRITE (2), SFIO_SEEK (3) |
| `io` | Raw return: 0 = EOF, negative = error |
| `disc` | Discipline in use at point of failure |

### Return codes

| Code | Value | Meaning |
|------|-------|---------|
| `SFIO_EDONE` | 0 | Stop operation, return what we have |
| `SFIO_EDISC` | 1 | Discipline handled it, resume |
| `SFIO_ESTACK` | 2 | Stack popped, retry on underlying stream |
| `SFIO_ECONT` | 3 | EINTR: clear error, retry syscall |

### Dispatch sequence

1. If local and `io <= 0`: set SFIO_ERROR or SFIO_EOF.
2. **Discipline exception call** (if `disc->exceptf`):
   - Call `ev = (*disc->exceptf)(f, type, &io, disc)`.
   - `ev < 0` → SFIO_EDONE.
   - `ev > 0` → SFIO_EDISC.
   - `ev == 0 && io > 0` → discipline refilled data, return ev.
   - Fall through if `ev == 0 && io <= 0`.
3. **String stream extension** (WRITE/SEEK, local, io ≥ 0):
   - `realloc(f->data, new_size)` rounded to SFIO_GRAIN.
   - Fix up `f->next` offset, update `f->data/endb/size`.
   - Return SFIO_EDISC (retry write into larger buffer).
4. **EINTR handling** (non-string):
   - If `_Sfexiting` or `f->bits & SFIO_ENDING` or `f->flags & SFIO_IOINTR`: SFIO_EDONE (don't retry).
   - Otherwise: clear errno and flags, return SFIO_ECONT.
5. **Stack auto-pop** (`chk_stack`):
   - If local, `f->push` set, buffer exhausted:
     - `pf = (*_Sfstack)(f, NULL)` — pop.
     - `sfclose(pf)`.
     - Return SFIO_ESTACK (retry on underlying).
   - Otherwise: SFIO_EDONE.

---

## Exception event codes

Complete list of events passed to `disc->exceptf` or raised via `sfraise`:

| Code | Value | Source | Meaning |
|------|-------|--------|---------|
| `SFIO_NEW` | 0 | sfclose (local reuse) | Reinitialization |
| `SFIO_READ` | 1 | _sfexcept, sfrd | Read failure |
| `SFIO_WRITE` | 2 | _sfexcept, sfwr | Write failure / buffer extension |
| `SFIO_SEEK` | 3 | _sfexcept, sfsk | Seek failure |
| `SFIO_CLOSING` | 4 | sfclose | About to close |
| `SFIO_DPUSH` | 5 | sfdisc | Discipline being pushed |
| `SFIO_DPOP` | 6 | sfdisc | Discipline being popped |
| `SFIO_DPOLL` | 7 | sfpoll | Poll readiness query |
| `SFIO_DBUFFER` | 8 | sfdisc | Buffer not empty during push/pop |
| `SFIO_SYNC` | 9 | sfsync | Sync start (void\*1) / end (void\*0) |
| `SFIO_PURGE` | 10 | sfpurge | Purge start/end |
| `SFIO_FINAL` | 11 | sfclose | Close done, about to free |
| `SFIO_READY` | 12 | sfpoll | Polled stream ready |
| `SFIO_LOCKED` | 13 | _sfmode | Stream locked, blocking |
| `SFIO_ATEXIT` | 14 | _sfcleanup | Process exiting |
| `SFIO_EVENT` | 100 | user | User-defined events start here |

---

## Discipline stack as polarity boundary

The stack as a whole mediates between two representations:

- The **top** faces the stream's buffer (value-mode: the data
  that the buffer holds).
- The **bottom** faces the OS or another subsystem (computation-mode: the
  actual I/O operations).

Individual disciplines are morphisms within this pipeline — they transform
data at the same logical level (bytes → bytes). The stack's endpoints define
the polarity boundary; each link is a transformation step, not itself a
shift. The exception is `_tmpexcept`, which genuinely shifts polarity by
swapping the computation substrate from memory to fd (see
[09-string-and-temp](09-string-and-temp.md)).

### Dccache as non-associativity witness

The `Dccache_t` mechanism is a concrete instance of the duploid
non-associativity from SPEC.md. When a discipline is pushed onto a stream
with buffered data, those bytes have already passed through the old
discipline chain (computation → value transformation complete). The new
discipline expects to transform raw input. Without the cache:

```
(push-disc ∘ read) ≠ read ∘ (push-disc)
```

The two bracketings yield different results — exactly the non-associativity
of composition across polarity boundaries. `Dccache_t` is the explicit
mediator that restores correct sequencing: it replays already-transformed
bytes without re-transforming them, then seamlessly hands off to the new
discipline chain for fresh data.

### SFIO_DCDOWN traversal state

The `SFIO_DCDOWN` bit (in `f->bits`) tracks which direction we're traversing
the chain. Setting it on entry and clearing on exit is the discipline's
save/restore of traversal state — analogous to a polarity frame.

---

## Key invariants

1. **Cycle-free**: sfdisc push checks for cycles. A discipline cannot appear
   twice in the same chain.

2. **Pre-push sync**: `SFSYNC(f)` before push ensures the new discipline
   doesn't see stale buffer state.

3. **Dccache preserves data ordering**: pushing a discipline with `readf`
   onto a read stream with buffered data doesn't lose or re-transform those
   bytes.

4. **SFIO_DCDOWN is transient**: set on entry to discipline callback, cleared
   on exit. Handles nesting correctly (saves/restores the bit).

5. **Discipline pop returns the discipline**: caller is responsible for
   freeing. SFIO does not free disciplines (they may be stack-allocated or
   shared).

→ C23: Typed enum for exception event codes. `[[nodiscard]]` on `exceptf`
returns. Typed function pointer aliases.

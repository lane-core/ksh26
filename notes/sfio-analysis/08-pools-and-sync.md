# 08: Pools and Sync

Pools coordinate I/O among groups of streams sharing a resource. Sync
flushes buffered data to the underlying fd. Together they enforce ordering
and consistency across related streams.

## Sfpool_t structure

`Legacy: sfhdr.h:268-276`

```c
struct _sfpool_s {
    Sfpool_t*   next;       /* linked list of pools */
    int         mode;       /* SFIO_SHARE or SFIO_AVAIL */
    int         s_sf;       /* allocated size of sf[] */
    int         n_sf;       /* current count of streams */
    Sfio_t**    sf;         /* active array of stream pointers */
    Sfio_t*     array[3];   /* inline storage for ≤ 3 streams */
};
```

Starts with inline `array[3]`; `sf` initially points to `array`. Grows
via malloc when more than 3 streams join. Pools form a singly-linked list
starting at `_Sfpool` (the global discrete pool).

---

## Two tiers of pools

### _Sfpool — the global registry

Every open stream is registered here via `_sfsetpool()` (called during
SFIO_INIT lazy init, `Legacy: sfmode.c:100-146`). This is NOT a coordination
pool — it's a registry that `sfsync(NULL)` uses to find all streams.

### Named pools — user-created via sfpool()

Created by `sfpool(f, pf, mode)`. Hold a set of mutually-exclusive streams.
Only the head (`sf[0]`) is "active" at any time; all others have `SFIO_POOL`
set in their `mode`. Named pools live in the linked list starting at
`_Sfpool.next`.

---

## sfpool(f, pf, mode)

`Legacy: sfio/sfpool.c:207-309`

### Query: sfpool(NULL, pf, mode)

Returns the head of `pf`'s pool. If `pf` is in `_Sfpool` (no named pool),
returns `pf` itself.

### Remove: sfpool(f, NULL, mode)

1. Call `_sfpmove(f, -1)` → `_sfpdelete()`.
2. Re-register `f` in `_Sfpool` via `_sfsetpool(f)`.
3. Return new head of the pool `f` left.

### Add: sfpool(f, pf, mode)

1. If `pf` has a named pool, inherit its mode.
2. If SFIO_SHARE: both must be write mode; flush `f`.
3. Isolate `f` from current pool.
4. If `pf` has no named pool: allocate via `newpool(mode)`, add `pf` as sf[0].
5. Set `f->pool = p`, append `f`.
6. Make `f` the new head via `_sfpmove(f, 0)` → `_sfphead()`.

---

## _sfphead() — pool head promotion

`Legacy: sfio/sfpool.c:77-139`

Makes stream `f` the pool head by flushing the current head and transferring
buffer state.

### Non-shared pool

`SFSYNC(head)` — flush current head to disk.

### Shared write pool (SFIO_SHARE)

The current head's pending buffer data is transferred to `f`:

```
v = head->next - head->data    /* pending bytes in head's buffer */
k = v - (f->endb - f->data)   /* excess beyond f's capacity */
```

If excess: write out `k` bytes directly via SFWR, then memmove the remainder
into `f`'s buffer and set `f->next = f->data + v`.

After transfer:
```
f->mode &= ~SFIO_POOL      /* f is now active (head) */
head->mode |= SFIO_POOL    /* old head is queued */
head->next = head->endr = head->endw = head->data  /* clear ALL cursors */
p->sf[n] = head; p->sf[0] = f  /* swap array slots */
```

`Contract:` Only `sf[0]` has `SFIO_POOL` clear. All other pool members have it
set. I/O attempts on non-head members trigger `_sfpmove(f, 0)` via `_sfmode()`
to promote themselves first.

---

## _sfpdelete() — pool removal

`Legacy: sfio/sfpool.c:142-184`

1. Compact `sf[]` by shifting entries down.
2. Clear `f->pool = NULL`, clear `SFIO_POOL`.
3. If pool now empty: `delpool()` (but NEVER on `_Sfpool` itself — the
   global registry skips `delpool()` and just exits early).
4. Select new head from remaining streams.
5. If only one stream remains: recursively remove it (a pool of one is no pool).

---

## Pool lifecycle: newpool/delpool

`Legacy: sfio/sfpool.c:35-74`

**newpool(mode):** Walk `_Sfpool.next` list for any node with `SFIO_AVAIL`.
Reuse if found. Otherwise malloc new `Sfpool_t`, append to list.

**delpool(p):** Free dynamic `sf` array. Set `p->mode = SFIO_AVAIL`. The
node is NOT freed — stays in the linked list for reuse.

`Contract:` Pool nodes never freed. This prevents dangling pointer walks
during `sfsync(NULL)`, which iterates the pool list and may trigger closes
that free pools mid-walk.

---

## sfsync(f) — single stream

`Legacy: sfio/sfsync.c:76-162`

If `f == NULL`, delegates to `_sfall()` (see below).

Walks `f` and `f->push` (the stack):

### Pre-sync notification

If `SFIO_IOCHECK && disc->exceptf`: call with `SFIO_SYNC, (void*)1` (start).

### Write path

If write mode and buffer has data (or SFIO_HOLE set):

1. Save/clear SFIO_POOL (prevent pool promotion during flush).
2. If `f->next > f->data`: set SFIO_RV, call `SFFLSBUF(f,-1)`.
3. If SFIO_HOLE: seek back one byte, write a single zero byte to
   materialize the sparse region. Clear SFIO_HOLE.
4. Restore SFIO_POOL.

### Read path

If read mode and seekable (extent ≥ 0) and either mmap or has unconsumed
buffer (`f->bits & SFIO_MMAP || f->next < f->endb`):

⚠ Hazard: The mmap flag triggers seek-back even with an empty buffer
(to allow remapping on next read).

```c
f->here -= (f->endb - f->next);   /* back up logical position */
f->endr = f->endw = f->data;       /* close fast-path */
f->mode = SFIO_READ | SFIO_SYNCED | lock; /* mark synced (preserves lock) */
SFSK(f, f->here, SEEK_SET, disc);  /* physically reposition fd */
```

For SHARE non-PUBLIC non-mmap: fully drain buffer (`endb = next = data`),
clear SFIO_SYNCED.

### Post-sync notification

Call `exceptf` with `SFIO_SYNC, (void*)0` (end).

### Pool propagation

If not local and `f` is in a pool but NOT the head: also sync the pool head
via `SFSYNC(f->pool->sf[0])`.

---

## _sfall() — sync all streams

`Legacy: sfio/sfsync.c:28-74`

Called by `sfsync(NULL)`.

### Convergence loop (up to 3 iterations)

```c
for(loop = 0; loop < MAXLOOP; ++loop) {
    for each pool p in _Sfpool linked list:
        for n in range (all of _Sfpool.sf[], only sf[0] of named pools):
            if stream needs sync: sfsync(f)
}
```

Streams are skipped if: SFIO_STRING, SFFROZEN, already SFIO_SYNCED, read
with no unconsumed buffer, write with no pending data.

### Why only sf[0] for named pools?

Only the pool head can do I/O. Other members have empty buffers (enforced
by `_sfphead()`). Syncing the head is sufficient.

### Why 3 iterations?

Syncing one stream can trigger discipline callbacks or pool movement that
leaves another stream needing sync. Three passes is an empirical bound on
convergence.

---

## sfpurge(f) — discard buffer

`Legacy: sfio/sfpurge.c:27-88`

Discards in-memory buffered data WITHOUT flushing to fd.

- Write: `f->next = f->data` (discard pending output). **Data loss.**
- Read: `f->here -= (f->endb - f->next)`, seek to correct position,
  `f->endb = f->next = f->data`.
- Mmap: unmap region, seek to correct position.

Key difference from sfsync: purge throws data away. sfsync writes it.

---

## Pre-fork flush pattern

Before `fork()`, ksh calls `sfsync(NULL)` to flush all SFIO streams.
This prevents buffered data from being duplicated in both parent and child.

In the sfio build, `sfsync(NULL)` handles everything — `fflush(NULL)` is
absent because libast remaps stdio to sfio via `ast_stdio.h`.

For the stdio backend (`KSH_IO_SFIO=0`), both `sfsync(NULL)` AND
`fflush(NULL)` are needed because the two I/O systems maintain separate
buffers.

See [10-ksh-integration](10-ksh-integration.md) for the specific call sites.

---

## Key invariants

1. **Pool head exclusivity.** Only `sf[0]` has `SFIO_POOL` clear. Any I/O on
   a non-head member triggers promotion via `_sfphead()`.

2. **Pool nodes never freed.** Marked `SFIO_AVAIL` for reuse. Prevents
   dangling pointers during `sfsync(NULL)` pool-list walks.

3. **sfsync write: SFIO_POOL cleared transiently.** During SFFLSBUF, the
   pool bit is saved/cleared to prevent re-entrant pool promotion.

4. **sfsync read: seek adjusts fd position.** The fd is repositioned to
   match `f->next` (the unconsumed data boundary), not `f->endb`.

5. **Convergence.** `sfsync(NULL)` runs up to 3 passes. In practice,
   convergence happens in 1–2.

→ C23: Pool mode as typed enum. `[[nodiscard]]` on sfsync return.

# 11: Stk Allocator

The shell's stack allocator. `Stk_t` is structurally an `Sfio_t` — same
three-pointer buffer layout. The stk layer adds a NUL sentinel contract
on top of sfio's write operations that sfio itself does not provide.

## Identity: Stk_t = Sfio_t

`Legacy: stk.h`

```c
typedef struct _stk_s {
    unsigned char *_data;   /* base of current frame */
    unsigned char *_next;   /* write cursor (allocation frontier) */
    unsigned char *_endb;   /* end of current frame */
} Stk_t;
```

This is the same three-pointer prefix as `Sfio_t`. The stk implementation
in `stk.c` operates on these pointers directly, using sfio-style semantics
for buffer management.

## stkstd — the global proxy

`stkstd` is a 24-byte global proxy struct, not a real stream with a full
private tail. `stkinstall()` copies pointers between `stkstd` and private
streams — it replaces sfstack's push/pop model with a pointer-swap model.

---

## Key macros

`Legacy: stk.h`

| Macro | Expansion | Purpose |
|-------|-----------|---------|
| `stkptr(sp, n)` | `((char*)(sp)->_data + (n))` | Pointer at offset n |
| `stktop(sp)` | `((char*)(sp)->_next)` | Current top (write cursor) |
| `stktell(sp)` | `((sp)->_next - (sp)->_data)` | Current offset |
| `stkseek(sp, n)` | `_stkseek(sp, n)` | Set cursor to offset n |

---

## Write operations

All write operations produce data and maintain the NUL sentinel as a
postcondition.

| Function | What it does | Sentinel? |
|----------|-------------|-----------|
| `stkputc(sp, c)` | Write one byte | Yes |
| `stkputs(sp, s)` | Write string (+ optional delimiter) | Yes |
| `stkwrite(sp, buf, n)` | Write n bytes | Yes |
| `stknputc(sp, c, n)` | Write n copies of byte c | Yes |
| `stkvprintf(sp, fmt, ...)` | Formatted write | Yes (via vsnprintf) |

### STK_SENTINEL macro

`Legacy: stk.c:88`

```c
#define STK_SENTINEL(sp) \
    do { if((sp)->_next && (sp)->_next < (sp)->_endb) *(sp)->_next = 0; } while(0)
```

Called at the end of every write operation. Writes a NUL byte at the current
cursor position (`*_next = 0`) without advancing the cursor. This makes the
data between `_data` and `_next` a valid C string at all times.

`Contract:` After any stk write operation, `*_next == 0`. The NUL is NOT
part of the allocated data — it sits at the frontier, one byte beyond the
last written byte. The buffer always has room for it because growth
operations ensure `_next < _endb`.

---

## _stkseek — the critical non-sentinel case

`Legacy: stk.c:342-355`

```c
void *_stkseek(Stk_t *stream, ssize_t n)
{
    /* grow if needed */
    stream->_next = stream->_data + n;
    /* NO sentinel here */
    return stream->_data;
}
```

`_stkseek` deliberately does NOT call `STK_SENTINEL`.

### Why: the sig_number pattern

`Legacy: trap.c`

`sig_number()` uses the stk as a scratchpad with seek-back-and-read:

1. Write uppercase signal name to stk.
2. `stkseek()` back to the start.
3. Read the name via `stkptr()`.

If `_stkseek` wrote a sentinel at the new position, it would overwrite the
first byte of the previously-written name — destroying the data that the
subsequent read expects to find.

This was discovered the hard way: the original implementation wrote a
sentinel in `_stkseek`, causing "bad trap" for all pseudosignals and
1777 test failures.

### Polarity framing

- **Writes** are positive (produce data). Sentinel is a postcondition of
  production.
- **Reads** are negative (observe data). They don't modify the buffer.
- **Seek** is a boundary operation (restructures context without connecting
  a producer to a consumer — not a cut in SPEC.md's sense). It repositions
  the cursor without producing or consuming. A sentinel during a seek
  violates polarity discipline — the byte at `*_next` after a seek belongs
  to previously written data, not to the seek operation.

The test: "does this operation produce new data?" If yes, sentinel. If no
(seek, freeze, copy), no sentinel.

---

## Frame management

### stkalloc(sp, n)

Allocates `n` bytes from the current frame. Advances both `_data` AND
`_next` past the allocation (aligned): `_data = _next = old_data + n`.
Calls `STK_SENTINEL`. Returns pointer to old `_data` (the start of the
allocated region, which is now *below* both cursors).

⚠ Hazard: After `stkalloc`, `_data` points past the returned allocation.
The returned region is no longer part of the "current word" — it's a
frozen allocation.

### stkfreeze(sp, extra)

Freezes the current frame: advances `_data` past the current content
(making it read-only), optionally reserves `extra` bytes in the new frame.
Does NOT call the `STK_SENTINEL` macro. However, when `extra > 0`, it
writes `*top = 0` manually at the current position before advancing —
functionally the same as a sentinel for that specific byte. When `extra == 0`,
no zero-write occurs.

### stklink/stkclose

Link frames for nested scopes (`stklink` increments refcount). `stkclose`
decrements refcount and frees when zero. Bulk free at scope exit.

---

## Relationship to sh.stk

`sh.stk` is the shell's primary stack allocator instance. Used throughout
`macro.c` for expansion workspace:

- Parameter expansion builds strings on the stk.
- Command substitution may push/pop stk frames.
- Arithmetic evaluation uses stk for intermediate results.
- Glob/pattern matching uses stk for workspace.

The stk's bulk-free at scope boundaries (function return, script end) is
the shell's primary memory management strategy for transient string data.

---

## Key invariants

1. **Sentinel after writes:** `*_next == 0` after every write operation.
   This makes stk content a valid C string at all times without explicit
   NUL termination.

2. **No sentinel after seek:** `_stkseek` does NOT write a sentinel.
   Data above `_next` may be valid previously-written content.

3. **No sentinel after freeze (macro):** `stkfreeze` does not call
   `STK_SENTINEL`. But when `extra > 0`, writes `*top = 0` manually.

4. **Growth preserves offset:** When `stkgrow` reallocates, `_next`'s
   offset from `_data` is preserved.

5. **stkstd is a proxy:** 24-byte global, not a real stream. `stkinstall`
   copies pointers between stkstd and private streams.

→ C23: `static inline` accessor functions. `static_assert` on struct
layout. Replace `data[1]` flexible array patterns with true `data[]`.

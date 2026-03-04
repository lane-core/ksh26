# 01: Data Structures

Core SFIO types. Public surface in `sfio.h` / `sfio_s.h`, private fields via
`_SFIO_PRIVATE` in `sfio_t.h`, internal helpers in `sfhdr.h`.

## Sfio_t (stream)

The central type. `struct _sfio_s` has a public prefix (visible to consumers
via `sfio_s.h`) and a private tail (expanded by `_SFIO_PRIVATE` when `sfio_t.h`
is included).

### Public fields (sfio_s.h)

| Field | Type | Purpose |
|-------|------|---------|
| `_next` | `unsigned char*` | Current read/write position in buffer |
| `_endw` | `unsigned char*` | End of writable region |
| `_endr` | `unsigned char*` | End of readable region |
| `_endb` | `unsigned char*` | Physical end of buffer |
| `_push` | `Sfio_t*` | Stream that was pushed onto this one (stacking) |
| `_flags` | `unsigned short` | Public stream flags (SF_READ, SF_WRITE, etc.) |
| `_file` | `short` | File descriptor (-1 for string streams) |
| `_data` | `unsigned char*` | Base of data buffer |
| `_size` | `ssize_t` | Buffer size |
| `_val` | `ssize_t` | Return value / string length (sfvalue() reads this) |

### Private fields (sfio_t.h via _SFIO_PRIVATE)

| Field | Type | Purpose |
|-------|------|---------|
| `extent` | `Sfoff_t` | Current file size |
| `here` | `Sfoff_t` | Current physical file position |
| `ngetr` | `unsigned char` | sfgetr recursion/call count |
| `tiny[1]` | `unsigned char` | 1-byte buffer for unbuffered read streams |
| `bits` | `unsigned short` | Private flags (SFIO_MMAP, SFIO_BOTH, etc.) |
| `mode` | `unsigned int` | Current I/O mode (SFIO_LOCK, SFIO_PEEK, etc.) |
| `disc` | `Sfdisc_t*` | Head of discipline chain |
| `pool` | `Sfpool_t*` | Pool this stream belongs to |
| `rsrv` | `Sfrsrv_t*` | Reserved buffer for sfgetr multi-buffer records |
| `proc` | `Sfproc_t*` | Co-process state |
| `stdio` | `void*` | stdio FILE if dual-mode |
| `lpos` | `Sfoff_t` | Last seek position |
| `iosz` | `size_t` | Preferred I/O size |
| `blksz` | `size_t` | Preferred block size |
| `getr` | `int` | Last sfgetr separator character |
| `pad` | `int` | Alignment padding (64-bit only) |

`Polarity:` The discipline chain (`disc`) mediates between the stream's
internal buffer (value) and external I/O (computation). The stack as a whole
has the structure of a polarity boundary — data crosses from value to
computation through the chain, and failures occur when the crossing discipline
is violated (see Dccache in [07-disciplines](07-disciplines.md)). Individual
disciplines compose like morphisms within this pipeline.

### Static initialization: SFNEW macro (sfio_t.h)

```c
#define SFNEW(data,size,file,type,disc) \
    { (unsigned char*)(data),          /* next  */ \
      (unsigned char*)(data),          /* endw  */ \
      (unsigned char*)(data),          /* endr  */ \
      (unsigned char*)(data),          /* endb  */ \
      NULL,                            /* push  */ \
      (unsigned short)((type)&SFIO_FLAGS), /* flags */ \
      (short)(file),                   /* file  */ \
      (unsigned char*)(data),          /* data  */ \
      (ssize_t)(size),                 /* size  */ \
      (ssize_t)(-1),                   /* val   */ \
      /* private fields zeroed, mode = (type & SFIO_RDWR)|SFIO_INIT */ \
    }
```

`Contract:` All four buffer pointers start equal to `data`. The stream is in
SFIO_INIT state — lazy initialization on first use via `_sfmode()`.

### SFCLEAR macro (sfio_t.h)

Resets all fields. Sets `_file = -1`, `_size = -1`, `_val = -1`, `extent = -1`.
All pointers NULL, all mode/bits zero. Used when recycling a stream.

→ C23: `static_assert` on struct size/offsets to catch layout drift.
`_Alignas` for buffer alignment requirements.

---

## Sfdisc_t (discipline)

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

Disciplines form a singly-linked stack. The `SFDISC()` macro
(`Legacy: sfhdr.h:520-527`) walks the chain to find the first discipline with a
non-NULL handler for a given operation.

`Polarity:` The discipline stack as a whole mediates between the stream's
buffer (value) and the OS (computation), with the structure of a polarity
boundary. Individual disciplines compose like morphisms within this pipeline —
they transform data at the same logical level. The exception is `_tmpexcept`,
which has the structure of a genuine polarity shift: it changes the computation
substrate from string buffer to temp file. The shift direction is
perspective-dependent (see [09-string-and-temp](09-string-and-temp.md) for
analysis); the structural point is the mode change with transparent identity
preservation.

→ C23: Typed function pointer aliases with `[[nodiscard]]` on `exceptf` returns.

---

## Sfpool_t (pool)

`Legacy: sfhdr.h:268-276`

```c
struct _sfpool_s {
    Sfpool_t*   next;       /* linked list of pools */
    int         mode;       /* pool type */
    int         s_sf;       /* allocated size of sf array */
    int         n_sf;       /* number of streams currently in pool */
    Sfio_t**    sf;         /* array of stream pointers */
    Sfio_t*     array[3];   /* inline storage for small pools */
};
```

Starts with inline `array[3]`; `sf` initially points to `array`. Grows via
realloc when more than 3 streams join. The global default pool is
`_Sfpool` (`Legacy: sfhdr.h:394`).

`Contract:` Only the pool head (index 0) may actively write. Non-head streams
are queued; `_sfphead()` promotes a stream to head by flushing the current head
and transferring buffer state.

→ C23: Pool mode as typed enum. `_Alignas` + `static_assert` on inline array.

---

## Sfrsrv_t (reserve buffer)

`Legacy: sfhdr.h:280-284`

```c
struct _sfrsrv_s {
    ssize_t     slen;       /* last string length */
    ssize_t     size;       /* buffer size */
    uchar       data[1];    /* flexible array member (C89 struct hack) */
};
```

Side buffer for `sfgetr()` when a record spans multiple buffer fills. Allocated
via `_sfrsrv()` and attached to `f->rsrv`. The `slen` field tracks the length
of the last record assembled here.

→ C23: Replace `data[1]` with true flexible array member `data[]`.

---

## Sfproc_t (co-process)

`Legacy: sfhdr.h:288-295`

```c
struct _sfproc_s {
    int     pid;        /* process ID */
    uchar*  rdata;      /* read data being cached */
    int     ndata;      /* size of cached data */
    int     size;       /* buffer size */
    int     file;       /* saved file descriptor */
    int     sigp;       /* sigpipe protection needed */
};
```

Used by `sfpopen()` for process-connected streams. Tracks the child PID,
cached unread data, and whether SIGPIPE protection is required.

---

## Sffmt_t (format descriptor)

`Legacy: sfio.h:64-84`

```c
struct _sffmt_s {
    long            version;    /* SFIO_VERSION */
    Sffmtext_f      extf;       /* extension function for custom formats */
    Sffmtevent_f    eventf;     /* event handler */
    Sffmtreload_f   reloadf;    /* reload argv with new type */
    char*           form;       /* format string (stackable) */
    va_list         args;       /* corresponding arg list */
    int             fmt;        /* format character */
    ssize_t         size;       /* object size */
    int             flags;      /* SFFMT_* flags */
    int             width;      /* field width */
    int             precis;     /* precision */
    int             base;       /* conversion base */
    char*           t_str;      /* type string */
    ssize_t         n_str;      /* length of t_str */
    void*           mbs;        /* multibyte state */
};
```

Passed between `sfvprintf`/`sfvscanf` and extension functions. The `extf`
callback allows ksh to extend printf with custom format specifiers (%T for
dates, %H for HTML, etc.).

---

## Argv_t (format argument union)

`Legacy: sfhdr.h:308-328`

Union of all types that can appear as format arguments: `int`, `long`, `short`,
`Sflong_t`, `Sfulong_t`, `Sfdouble_t`, `double`, `float`, `wchar_t`, `char*`,
`void*`, `Sffmt_t*`, plus pointer variants for scanf.

→ C23: Could use `_Generic` dispatch in some paths, but the union is likely
the right structure for the format engine's positional argument array.

---

## Sfextern_t (global state)

`Legacy: sfhdr.h:403-414`

```c
typedef struct _sfextern_s {
    ssize_t         sf_page;    /* system page size */
    Sfpool_t        sf_pool;    /* default pool */
    int             (*sf_pmove)(Sfio_t*, int);
    Sfio_t*         (*sf_stack)(Sfio_t*, Sfio_t*);
    void            (*sf_notify)(Sfio_t*, int, void*);
    int             (*sf_stdsync)(Sfio_t*);
    Sfdisc_t        sf_udisc;   /* default discipline */
    void            (*sf_cleanup)(void);
    int             sf_exiting;
    int             sf_done;
} Sfextern_t;
```

Single global instance `_Sfextern`. Accessed via macros: `_Sfpage`, `_Sfpool`,
`_Sfnotify`, etc. The `sf_notify` callback is how ksh tracks stream events
(see [10-ksh-integration](10-ksh-integration.md)).

---

## Standard streams

Three static `Sfio_t` instances, initialized via `SFNEW`:

| Variable | Global | fd | Mode |
|----------|--------|----|------|
| `sfstdin` | `&_Sfstdin` | 0 | SFIO_READ |
| `sfstdout` | `&_Sfstdout` | 1 | SFIO_WRITE |
| `sfstderr` | `&_Sfstderr` | 2 | SFIO_WRITE |

⚠ Hazard: ksh redirects `sfstderr` to arbitrary fds via `sfsetfd()`.
`sfstderr` is NOT equivalent to stdio's `stderr` (which always maps to fd 2).
See [10-ksh-integration](10-ksh-integration.md).

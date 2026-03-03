# 02: Flags and Modes

Three separate flag namespaces live in different `Sfio_t` fields, plus format
flags and exception event codes. Understanding which namespace a constant
belongs to is critical — wrong-field bugs are silent and devastating.

## Public flags (`_flags` field, `unsigned short`)

`Legacy: sfio.h:122-143`

These are the user-visible stream properties. Passable to `sfnew()` (masked by
`SFIO_FLAGS`) and settable via `sfset()` (masked by `SFIO_SETS`).

| Constant | Octal | Purpose |
|----------|-------|---------|
| `SFIO_READ` | 0000001 | Open for reading |
| `SFIO_WRITE` | 0000002 | Open for writing |
| `SFIO_STRING` | 0000004 | String stream (no fd, resizable buffer) |
| `SFIO_APPENDWR` | 0000010 | Append mode only |
| `SFIO_MALLOC` | 0000020 | Buffer is malloc'd (sfio owns it) |
| `SFIO_LINE` | 0000040 | Line buffering |
| `SFIO_SHARE` | 0000100 | Shared file descriptor |
| `SFIO_EOF` | 0000200 | EOF detected |
| `SFIO_ERROR` | 0000400 | Error occurred |
| `SFIO_STATIC` | 0001000 | Stream struct cannot be freed |
| `SFIO_IOCHECK` | 0002000 | Call exceptf before each I/O |
| `SFIO_PUBLIC` | 0004000 | SFIO_SHARE + follow physical seek |
| `SFIO_WHOLE` | 0020000 | Preserve atomicity of sfwrite/sfputr |
| `SFIO_IOINTR` | 0040000 | Return on interrupts (don't retry EINTR) |
| `SFIO_WCWIDTH` | 0100000 | wcwidth display stream |

### Composite masks

| Mask | Value | Meaning |
|------|-------|---------|
| `SFIO_FLAGS` | 0177177 | All flags passable to `sfnew()` |
| `SFIO_SETS` | 0177163 | Flags settable via `sfset()` |

### Shorthands (sfio_t.h)

| Shorthand | Expansion |
|-----------|-----------|
| `SFIO_RDWR` | `SFIO_READ \| SFIO_WRITE` |
| `SFIO_RDSTR` | `SFIO_READ \| SFIO_STRING` |
| `SFIO_WRSTR` | `SFIO_WRITE \| SFIO_STRING` |
| `SFIO_RDWRSTR` | `SFIO_RDWR \| SFIO_STRING` |

`Contract:` A stream is readable iff `flags & SFIO_READ`, writable iff
`flags & SFIO_WRITE`. Both may be set simultaneously (`SFIO_RDWR`). String
streams have `SFIO_STRING` and `_file == -1`.

→ C23: Typed enum with `unsigned short` underlying type. Eliminates
wrong-field-wrong-flag bugs at compile time.

---

## Private bits (`bits` field, `unsigned short`)

`Legacy: sfhdr.h:127-154`

Internal-only flags. Not accessible through the public API.

| Constant | Octal | Purpose |
|----------|-------|---------|
| `SFIO_MMAP` | 00000001 | Stream is in memory-mapped mode |
| `SFIO_BOTH` | 00000002 | Stream supports both read and write |
| `SFIO_HOLE` | 00000004 | A hole of zeros was created (sparse write) |
| `SFIO_NULL` | 00000010 | Stream is /dev/null |
| `SFIO_SEQUENTIAL` | 00000020 | Sequential access hint |
| `SFIO_JUSTSEEK` | 00000040 | Just did an sfseek |
| `SFIO_PRIVATE` | 00000100 | Private stream (internal to sfio) |
| `SFIO_ENDING` | 00000200 | No re-I/O on interrupts during close |
| `SFIO_WIDE` | 00000400 | In wide mode (stdio compat only) |
| `SFIO_PUTR` | 00001000 | Currently inside sfputr() |

### Temporary bits (cleared by sfclrlock)

| Constant | Octal | Purpose |
|----------|-------|---------|
| `SFIO_TMPBITS` | 00170000 | Mask of all temporary bits |
| `SFIO_DCDOWN` | 00010000 | Recursing down discipline stack |
| `SFIO_WCFORMAT` | 00020000 | wchar_t formatting (stdio only) |
| `SFIO_MVSIZE` | 00040000 | `f->size` was scaled in sfmove() |

### Helper macros

- `SFCLRBITS(f)` — undo SFIO_MVSIZE scaling + clear all SFIO_TMPBITS
- `SFMVSET(f)` — scale `f->size` by SFIO_NMAP and set SFIO_MVSIZE
- `SFMVUNSET(f)` — reverse the scaling if SFIO_MVSIZE was set
- `SFISNULL(f)` — true if stream is /dev/null (`extent < 0 && SFIO_NULL`)
- `SFSETNULL(f)` — mark stream as /dev/null

→ C23: Typed enum with `unsigned short` underlying type. Separate from public
flags — enforced by the type system rather than convention.

---

## Mode flags (`mode` field, `unsigned int`)

`Legacy: sfhdr.h:159-171, sfio_t.h:59`

Track the stream's current operational state. These are the "what is the stream
doing right now" flags.

| Constant | Octal | Purpose |
|----------|-------|---------|
| `SFIO_INIT` | 0000004 | Stream not yet initialized (lazy init) |
| `SFIO_RC` | 0000010 | Peeking for a record (sfgetr context) |
| `SFIO_RV` | 0000020 | Reserve without read/most write |
| `SFIO_LOCK` | 0000040 | Stream locked for I/O operation |
| `SFIO_PUSH` | 0000100 | Stream has been pushed (via sfstack) |
| `SFIO_POOL` | 0000200 | In a pool but not the current head |
| `SFIO_PEEK` | 0000400 | Pending peek (sfreserve data outstanding) |
| `SFIO_PKRD` | 0001000 | Did a peek read |
| `SFIO_GETR` | 0002000 | Did a getr on this stream |
| `SFIO_SYNCED` | 0004000 | Stream was synced |
| `SFIO_STDIO` | 0010000 | Buffer given up to stdio |
| `SFIO_AVAIL` | 0020000 | Was closed, available for reuse |
| `SFIO_LOCAL` | 0100000 | Sentinel for internal/local call |

### Lock/unlock protocol

`Legacy: sfhdr.h:502-511`

```
SFLOCK(f,l):  f->mode |= SFIO_LOCK; f->endr = f->endw = f->data
              (l is IGNORED — always acquires unconditionally)
SFOPEN(f,l):  if l==0: f->mode &= ~(SFIO_LOCK|SFIO_RC|SFIO_RV); restore endr/endw
              if l!=0: no-op (internal recursive call, don't unlock)
```

⚠ Hazard: SFLOCK ignores the `l` parameter entirely — it always acquires.
Only SFOPEN checks `l` to decide whether to release. The `l` parameter
distinguishes external calls (`l=0`, should unlock) from internal recursive
calls (`l=1`, leave locked).

When locked, `endr = endw = data` makes the fast-path macros (`sfputc`,
`sfgetc`) always fall through to the slow path, which checks the lock and
returns an error. This is the concurrency guard.

`Contract:` Every public sfio function calls SFLOCK on entry and SFOPEN on exit.
The SETLOCAL/GETLOCAL mechanism (`Legacy: sfhdr.h:483-484`) distinguishes
internal recursive calls from external ones — only external calls unlock.

### Frozen check

`SFFROZEN(f)` (`Legacy: sfhdr.h:514-516`): returns true if the stream is in
a state that prohibits access — pushed, locked, or peeked. Also handles the
SFIO_STDIO handoff.

### SFMODE macro

`SFMODE(f,l)` (`Legacy: sfhdr.h:503`): extracts the base mode (read/write)
by masking out SFIO_RV, SFIO_RC, and optionally SFIO_LOCK. Used to check
whether the stream is in the right mode for an operation.

→ C23: Typed enum with `unsigned int` underlying type. The three-way
partitioning (flags/bits/mode) becomes three separate enum types — mixing
them is a compile-time error.

---

## Exception event codes

`Legacy: sfio.h:149-162`

Passed to `Sfexcept_f` handlers. The values 0, 1, 2 overlap with SFIO_NEW,
SFIO_READ, SFIO_WRITE by design.

| Code | Value | When raised |
|------|-------|-------------|
| `SFIO_NEW` | 0 | New stream created |
| `SFIO_READ` | 1 | Read exception (also: read event in notify) |
| `SFIO_WRITE` | 2 | Write exception (also: buffer extension request) |
| `SFIO_SEEK` | 3 | Seek error |
| `SFIO_CLOSING` | 4 | Stream about to close |
| `SFIO_DPUSH` | 5 | Discipline being pushed |
| `SFIO_DPOP` | 6 | Discipline being popped |
| `SFIO_DPOLL` | 7 | Polling stream readiness |
| `SFIO_DBUFFER` | 8 | Buffer not empty during push/pop |
| `SFIO_SYNC` | 9 | Start/end of synchronization |
| `SFIO_PURGE` | 10 | sfpurge() called |
| `SFIO_FINAL` | 11 | Close complete except stream free |
| `SFIO_READY` | 12 | Polled stream is ready |
| `SFIO_LOCKED` | 13 | Stream is locked |
| `SFIO_ATEXIT` | 14 | Process is exiting |
| `SFIO_EVENT` | 100 | Start of user-defined event range |

### Exception return codes (internal)

`Legacy: sfhdr.h:478-481`

| Code | Value | Meaning |
|------|-------|---------|
| `SFIO_EDONE` | 0 | Stop operation, return |
| `SFIO_EDISC` | 1 | Discipline says OK, continue normally |
| `SFIO_ESTACK` | 2 | Stack was popped, retry on underlying stream |
| `SFIO_ECONT` | 3 | Continue operation (retry after EINTR) |

→ C23: Both event codes and return codes as typed enums.

---

## Reserve type flags

`Legacy: sfio.h:146-147`

Passed to `sfgetr()`/`sfreserve()` to control locking behavior:

| Flag | Value | Purpose |
|------|-------|---------|
| `SFIO_LOCKR` | 0000010 | Lock the record, preventing further stream access |
| `SFIO_LASTR` | 0000020 | Return the last incomplete record |

---

## Format flags (SFFMT_*)

`Legacy: sfio.h:88-109`

Used in `Sffmt_t.flags` for printf/scanf formatting:

| Flag | Octal | Meaning |
|------|-------|---------|
| `SFFMT_SSHORT` | 000000010 | 'hh' — char |
| `SFFMT_TFLAG` | 000000020 | 't' — ptrdiff_t |
| `SFFMT_ZFLAG` | 000000040 | 'z' — size_t |
| `SFFMT_LEFT` | 000000100 | Left justify |
| `SFFMT_SIGN` | 000000200 | Always show sign |
| `SFFMT_BLANK` | 000000400 | Space if no sign |
| `SFFMT_ZERO` | 000001000 | Zero-pad left |
| `SFFMT_ALTER` | 000002000 | Alternate format (#) |
| `SFFMT_THOUSAND` | 000004000 | Thousand grouping (') |
| `SFFMT_SKIP` | 000010000 | Skip scanf assignment |
| `SFFMT_SHORT` | 000020000 | 'h' — short |
| `SFFMT_LONG` | 000040000 | 'l' — long |
| `SFFMT_LLONG` | 000100000 | 'll' — long long |
| `SFFMT_LDOUBLE` | 000200000 | 'L' — long double |
| `SFFMT_VALUE` | 000400000 | Value is returned |
| `SFFMT_ARGPOS` | 001000000 | Getting arg for $ patterns |
| `SFFMT_IFLAG` | 002000000 | 'I' flag |
| `SFFMT_JFLAG` | 004000000 | 'j' — intmax_t |
| `SFFMT_CENTER` | 010000000 | '=' — center justify |
| `SFFMT_CHOP` | 020000000 | Chop long strings from left |
| `SFFMT_SET` | 037777770 | Mask of flags settable via extf |

### Internal format flags (sfhdr.h)

| Flag | Octal | Meaning |
|------|-------|---------|
| `SFFMT_EFORMAT` | 001000000000 | sfcvt converting %e |
| `SFFMT_MINUS` | 002000000000 | Minus sign present |
| `SFFMT_AFORMAT` | 004000000000 | sfcvt converting %a |
| `SFFMT_UPPER` | 010000000000 | sfcvt uppercase |

### Format element types (sfhdr.h)

| Type | Value | Formats |
|------|-------|---------|
| `SFFMT_INT` | 001 | %d, %i |
| `SFFMT_UINT` | 002 | %u, %o, %x |
| `SFFMT_FLOAT` | 004 | %f, %e, %g |
| `SFFMT_CHAR` | 010 | %c, %C |
| `SFFMT_POINTER` | 020 | %p, %n, %s, %S |
| `SFFMT_CLASS` | 040 | %[ (scanf character class) |

---

## Notify event codes

`Legacy: sfio.h:169-170`

Passed to the `_Sfnotify` callback (registered via `sfnotify()`):

| Code | Value | Meaning |
|------|-------|---------|
| `SFIO_NEW` | 0 | New stream created |
| `SFIO_SETFD` | -1 | About to set the file descriptor |

The third arg to the callback is context-dependent (the old fd for SFIO_SETFD).

---

## Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `SFIO_BUFSIZE` | 8192 | Default buffer size |
| `SFIO_UNBOUND` | -1 | Unbounded buffer size |
| `SFIO_VERSION` | 20240303L | Protocol version for Sffmt_t |

---

## VLE encoding constants

`Legacy: sfio.h:277-286`

Variable-length encoding for portable integer I/O (sfputl/sfgetl/sfputu/sfgetu):

| Constant | Value | Purpose |
|----------|-------|---------|
| `SFIO_SBITS` | 6 | Bits per signed byte |
| `SFIO_UBITS` | 7 | Bits per unsigned byte |
| `SFIO_BBITS` | 8 | Bits per raw byte |
| `SFIO_SIGN` | 64 | Sign bit position |
| `SFIO_MORE` | 128 | Continuation bit |
| `SFIO_BYTE` | 256 | Full byte range |
| `SFIO_U1–U4` | 128^1–128^4 | Threshold values for 1–4 byte encodings |

→ C23: All of these as `constexpr` constants.

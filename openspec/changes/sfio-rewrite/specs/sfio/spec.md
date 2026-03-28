## ADDED Requirements

### Requirement: POSIX Issue 8 fd primitives

The reimplementation SHALL use POSIX Issue 8 fd-level primitives where
available, with configure.sh probes and fallbacks:

| Primitive | Used in | Replaces |
|-----------|---------|----------|
| pipe2(O_CLOEXEC) | sflife.c | pipe() + fcntl |
| dup3(old, new, O_CLOEXEC) | sflife.c:sfsetfd | dup2() + fcntl |
| ppoll(fds, n, ts, sigmask) | sfread.c:sfpkrd | poll() + sigprocmask |
| posix_close(fd, 0) | sflife.c:sfclose | close() |
| mkostemp(tmpl, O_CLOEXEC) | sflife.c:sftmp | mkstemp() + fcntl |

FILE*-based Issue 8 primitives (open_memstream, fmemopen, getdelim)
SHALL NOT be used.

#### Scenario: Atomic fd creation
All fd-creating paths use O_CLOEXEC atomically (no window between
creation and flag set).


### Requirement: C23 typed enums for flag namespaces

The three flag namespaces (public flags, private bits, mode flags) SHALL
use C23 `enum : type` to make cross-namespace mixing a compile-time error.

```c
enum sfio_flags : unsigned short { SF_READ = ..., SF_WRITE = ..., ... };
enum sfio_bits  : unsigned short { SF_DCDOWN = ..., ... };
enum sfio_mode  : unsigned int   { SF_LOCK = ..., SF_GETR = ..., ... };
```

#### Scenario: Type safety
Assigning `SF_LOCK` (mode) to a `_flags` field (sfio_flags) produces a
compiler diagnostic under `-Wenum-conversion`.


### Requirement: Debug buffer invariant assertion

Debug builds SHALL include `sfio_check(f)` validating the five-pointer
buffer invariant after every public function return. This does not exist
in legacy sfio.

#### Scenario: Assertion catches corruption
Deliberately corrupting `f->_next > f->_endb` triggers the assertion
in a debug build.


### Requirement: libc delegation for standard printf

Standard format specifiers (d/i/o/u/x/X/s/c/p/f/e/g/a) SHALL delegate
to libc `vsnprintf` on a temporary buffer. The reimplementation handles
only the %!/extf protocol, format context stacking, and shadow pointer
optimization.

#### Scenario: printf output matches libc
`printf '%e %g %a' 3.14 3.14 3.14` produces output identical to
system printf for standard specifiers.

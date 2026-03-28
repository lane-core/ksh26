## Why

ksh26 inherits AT&T's sfio — 78 files, ~12,800 LOC of '90s buffered I/O
carrying mmap fallbacks, scanf support, float conversion, and platform
probes for dead systems. ksh uses 39 of 77 exported functions. Three prior
attempts to replace sfio with stdio all failed (the buffer IS the API).
A clean-room rewrite preserving the same API eliminates legacy complexity
while keeping ksh's I/O semantics intact.

## What Changes

- Delete `src/lib/libast/sfio/` (78 files, ~12,800 lines)
- Write 7 new source files (~2,600 lines) + 2 headers organized by
  duploid polarity role
- Target POSIX Issue 8 fd primitives (pipe2, dup3, ppoll, posix_close,
  mkostemp, O_CLOFORK) for race-free fd lifecycle
- Delegate standard printf specifiers to libc vsnprintf
- Eliminate ~3,435 lines of unused subsystems (scanf, float conversion,
  mmap, popen, poll, stdio compat, platform probes)
- Zero changes to ksh call sites — same API, same semantics

## Specs Affected

### New
_(none — the sfio spec already exists)_

### Modified
- `sfio`: Implementation changes from legacy to clean-room rewrite.
  All contracts maintained; new verification criteria added.

## Impact

- `src/lib/libast/sfio/` — complete replacement
- `src/lib/libast/include/sfio.h` — rewritten (same public API)
- `configure.sh` — source collection updated
- `ast_stdio.h` — eliminated (stdio interception no longer needed)
- All ≥114 test stamps must pass unchanged (≥110 gate)

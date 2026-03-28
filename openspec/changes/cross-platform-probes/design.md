## Context

iffe (the feature test engine inherited from AT&T AST) supports an
`INSTALLROOT` environment variable. When set, iffe auto-includes
`$INSTALLROOT/src/lib/libast/features/standards` in its compilation
preamble via `iffe.sh` lines 1149-1153. The `standards` probe
(tier 0 in configure.sh) generates `ast_standards.h` which defines
platform-specific feature test macros:

- Linux glibc: `_GNU_SOURCE`, `_FILE_OFFSET_BITS=64`, `_TIME_BITS=64`
- macOS: `_DARWIN_C_SOURCE`
- Others: appropriate equivalents

Without `INSTALLROOT`, probes compile in a bare environment where
glibc hides POSIX.1-2008 struct fields behind feature test macros.

## Goals / Non-Goals

**Goals:**
- All iffe probes compile with the same feature test macros as the
  library code they're probing for.
- `just build-linux` produces a working aarch64-linux binary.
- `just test-linux` passes the full test suite on aarch64-linux.

**Non-Goals:**
- Changing iffe.sh itself (inherited, complex, fragile).
- Adding new probes or removing existing ones.
- x86_64-linux support (requires Rosetta, deferred).

## Decisions

### 1. Set INSTALLROOT in run_iffe_ast

The fix is in `configure.sh`, function `run_iffe_ast`. Before invoking
iffe, export `INSTALLROOT` pointing to the source root:

```sh
export INSTALLROOT="$PWD"
```

iffe.sh checks `$INSTALLROOT/src/lib/libast/features/standards` —
the source probe file, not the generated output. This is always
present in the source tree.

**Why not pass -D_GNU_SOURCE directly?** That's a band-aid for one
platform. `INSTALLROOT` is the mechanism iffe was designed to use,
and it handles all platforms via the `standards` probe.

### 2. Verify probe ordering

`ast_standards.h` is generated in tier 0 (`run_standards`), which
runs before all other probes. The `FEATURE/standards` symlink exists
by the time any tier 1+ probe runs. No ordering change needed.

### 3. Validate on both platforms

After the fix, compare generated headers between darwin and linux:
- `tv.h`: darwin should have `st_mtimespec.tv_nsec`, linux should
  have `st_mtim.tv_nsec`
- `ast_fs.h`: verify `st_blocks`, `st_blksize` present on both

## Risks / Trade-offs

**[Probe result changes on darwin]** → Unlikely. macOS headers don't
gate struct fields behind feature test macros. Adding `_DARWIN_C_SOURCE`
to probes that already work is harmless (it's already defined in the
actual compilation).

**[Probe result changes on Linux]** → This is the point. Results will
change from wrong to correct. Any existing Linux builds (if any) would
need a full reconfigure (`just reconfigure`).

## Why

`just build-linux` fails on aarch64-linux with:
```
tv.h:21:38: error: 'struct stat' has no member named 'st_atimensec'
```

Root cause: `run_iffe_ast` in configure.sh doesn't set `INSTALLROOT`, so iffe
never includes `ast_standards.h` in its probe compilation preamble. That file
defines `_GNU_SOURCE` (glibc), `_DARWIN_C_SOURCE` (macOS), etc. Without it,
glibc hides `st_atim.tv_nsec` behind feature test macros and the `tv` probe
falls through to the wrong branch (`st_atimensec` — ancient BSD).

macOS is unaffected because `st_mtimespec.tv_nsec` is unconditionally exposed
in the BSD ABI. The bug only manifests on Linux where struct stat fields are
gated by feature test macros.

The same `INSTALLROOT` gap affects all iffe probes, not just `tv`. Other
probes (`fs`, `sys`, `param`, `time`, `tvlib`) may silently produce wrong
results on Linux for similar reasons.

## What Changes

- Set `INSTALLROOT` in `run_iffe_ast` so iffe picks up `ast_standards.h`
  (the `FEATURE/standards` file) in all probe compilations.
- Verify that `ast_standards.h` is generated before any probes that depend
  on it (it's tier 0 — already runs first).
- Validate the fix: `just build-linux` succeeds on aarch64-linux, `tv.h`
  contains `st_atim.tv_nsec` (not `st_atimensec`).

## Capabilities

### New Capabilities

### Modified Capabilities
- `build-system`: Fix probe compilation environment so feature detection
  produces correct results on all target platforms.

## Impact

- **configure.sh**: One-line fix in `run_iffe_ast` to set `INSTALLROOT`.
- **All platforms**: Probes now compile with the same feature test macros
  as the actual library code. No behavioral change on macOS (already works).
- **Linux**: `tv.h`, and potentially `ast_fs.h`, `ast_sys.h`, `ast_param.h`
  get correct results instead of silent wrong answers.

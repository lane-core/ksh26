## Why

The test harness (`run-test.sh`, `tests/contexts/`) uses raw POSIX shell with
manual error handling. Silent failures in commands like `mkdir`, `cp`, `date`
produce confusing test results. Trap management is manual save/restore. We
discovered these gaps during NixOS porting — `date: command not found` in
`run-test.sh` failed silently and the root cause took hours to trace.

[modernish](https://github.com/modernish/modernish) by Martijn Dekker (ISC
license) solves these problems with `harden` (make command failures fatal),
stack-based traps, and safe-mode defaults. But the full library is 246 files
/ 1.4MB and deeply coupled — individual modules can't be extracted.

Port the key concepts as ~100-150 lines of self-contained POSIX shell,
attributed to modernish under ISC license.

## What Changes

- Add `tests/lib/safety.sh` — portable shell safety primitives (~45 lines):
  - `die MSG` — fatal exit from any context (subshells, pipes) with `$LINENO`
  - `harden CMD...` — wrap commands so non-zero exit calls `die`
  - `extern CMD` — bypass builtins/functions, call the real PATH binary
  - `pushtrap` / `poptrap` — stack-based trap management (LIFO)
  - Safe mode: `set -o nounset -o noglob` for harness code
  - `pipefail` detection and enablement (ksh/bash; graceful no-op on dash)
- Source `safety.sh` from `run-test.sh` and `tests/contexts/default.sh`
- Add ISC license attribution for modernish concepts

## Capabilities

### New Capabilities
- `test-safety`: Shell safety primitives for the test harness, ported from
  modernish concepts.

### Modified Capabilities
- `workflow`: Test harness gains command hardening and stack-based traps.

## Impact

- **Test harness**: `run-test.sh` and context scripts source `safety.sh`.
  Commands like `mkdir`, `date`, `rm` become hardened — failures are
  immediately fatal with clear diagnostics instead of silently continuing.
- **No build system impact**: `safety.sh` is test-only, not used by
  configure.sh or the build.
- **No runtime impact**: The shell binary is unchanged.
- **License**: ISC attribution added for ported concepts. ISC is compatible
  with EPL-2.0.

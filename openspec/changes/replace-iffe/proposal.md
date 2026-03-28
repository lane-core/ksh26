## Why

iffe is a 4,322-line AT&T shell script that assumes a dead build system (MAM).
We work around its assumptions (`INSTALLROOT`, `-X ast -X std`, workdir
symlink chains) rather than configuring through it. Every cross-platform bug
in configure.sh traces back to iffe's opaque environment setup. The tool
works, but its abstraction cost exceeds its value.

configure.sh already has `probe_c` and `probe_c_output` — the hard primitives.
What's missing is a thin layer of helpers (`probe_hdr`, `probe_lib`, `probe_mem`,
`probe_typ`) and translating each probe's logic into native shell.

## What Changes

- Replace all 57 iffe invocations with native shell probe functions in
  configure.sh.
- Remove `run_iffe`, `run_iffe_ast`, and the INSTALLROOT/workdir machinery.
- Remove `src/cmd/INIT/iffe.sh` from the build (keep in `tests/infra/` for
  regression testing the old path).
- Each probe becomes a named function (e.g., `probe_ast_tv()`) that emits
  the same `#define`/header content as iffe did.
- Keep the tier structure for parallel execution.

## Capabilities

### New Capabilities

### Modified Capabilities
- `build-system`: Replace iffe.sh with native configure.sh probe functions.
  Same outputs, transparent implementation.

## Impact

- **configure.sh**: Major expansion (~300-500 lines of probe helpers + per-probe
  functions). Net reduction when iffe invocation machinery is removed.
- **Build time**: Faster — no fork+exec of iffe per probe, no temp file dance.
  Each probe is a function call, not a subprocess.
- **Portability**: All probe logic visible in one file. No hidden iffe behaviors.
  Platform issues debuggable with `sh -x configure.sh`.
- **iffe.sh**: Removed from build path. Kept at `tests/infra/iffe.sh` for
  regression comparison.
- **Generated headers**: Identical output. Any difference is a bug.

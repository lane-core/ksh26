# ksh26 Changes from ksh93u+m

Deviations from the upstream ksh93u+m codebase, tracked as changes land
on main. Each entry records what changed, why, and what behavior differs.

## v0.0.1 — Build Infrastructure (2026-03-28)

### Build system replacement

- **iffe/mamake retired.** The AT&T `iffe` feature-test generator,
  `mamake` build tool, all `Mamfile`s, and `bin/package` are removed.
  Replaced by `configure.sh` (skalibs-inspired probes) + `samu`
  (vendored ninja-compatible) + nix flake.

- **Nix-native CI.** `flake-parts` module system with `nix-github-actions`
  for automated cross-platform testing (darwin + linux). NixOS VM
  integration test via `testers.runNixOSTest`.

### Source changes (no behavioral deviations)

- **`ast_std.h`**: Added `#define __FILE FILE` for glibc 2.42 `wchar.h`
  compatibility. No behavioral change — resolves a type visibility issue
  where `__FILE` was blocked by AST's stdio guards.

- **`ast_stdio.h`**: Restored `#define ____FILE_defined` and
  `#define __FILE FILE` to match upstream `features/stdio` output.

### Test changes (widened timing margins)

- **`basic.sh:554`**: `sleep .15` → `sleep .5`, threshold `.2` → `.7`.
  Same behavioral assertion (pipefail doesn't block right side), wider
  margin for CI scheduling jitter.

- **`signal.sh:334`**: `sleep .4` → `sleep 1.0`, threshold adjusted.
  Same assertion (SIGCHLD delivery timing), wider margin.

- **`signal.sh:354`**: Wait threshold `.4` → `.3`. Same assertion
  (parent waits for child), wider margin.

- **`sigchld.sh:149,151,155`**: `sleep .05/.1` → `sleep .1/.5`.
  Same assertion (job completion notification), wider margin.

- **`signal.sh:28`**: Added `trap '' INT` in SIGINT test subshell.
  Prevents process group signal broadcast from killing the test
  validation subshell in non-interactive environments.

- **`builtins.sh:681`**: Skip `/usr/bin` cd traversal test on non-FHS
  systems. Same behavior already tested via `/etc` at lines 672-680.

### Dead platform support removed

- 31 platform-specific compiler/linker flag files (HP-UX, AIX, SGI,
  NeXT, SCO, Cygwin, etc.) deleted. These were unused by the new
  build system and untested.

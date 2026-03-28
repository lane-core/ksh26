## Why

ksh26's flake declares `x86_64-linux` and `aarch64-linux` in `supportedSystems`, but
building for those targets from macOS requires a linux builder. Without one, `nix build
.#packages.x86_64-linux.default` fails immediately. Adding nix-darwin's `linux-builder`
module enables true cross-platform validation from Lane's darwin machine — catch
linux-specific regressions without pushing to CI or SSHing to a remote box.

## What Changes

- Add a nix-darwin module (`nix/darwin-linux-builder.nix`) that configures the
  `linux-builder` VM as a remote nix builder.
- Add `just` recipes for cross-platform builds and tests (`just build-linux`,
  `just test-linux`).
- Update `flake.nix` to export the darwin module for linux-builder configuration.
- Document the setup in CLAUDE.md's build/test section.

## Capabilities

### New Capabilities
- `linux-builder`: nix-darwin linux-builder VM configuration and cross-platform
  build/test recipes for ksh26.

### Modified Capabilities
- `build-system`: New cross-platform recipes extend the existing two-path build model.
  The validation path gains linux targets from darwin hosts.

## Impact

- **Nix modules**: New `nix/darwin-linux-builder.nix` module.
- **Flake**: `darwinModules` gains a linux-builder export.
- **Just recipes**: New cross-build recipes in `justfile`.
- **Dependencies**: nix-darwin's `linux-builder` module (QEMU-backed NixOS VM).
  No changes to the ksh26 source code or build system itself.

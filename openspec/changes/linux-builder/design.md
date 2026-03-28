## Context

ksh26's flake declares `supportedSystems` with both darwin and linux targets. The
validation path (`just build`, `just test`) calls `nix build` with a package attribute
matching the local system — e.g., `.#packages.aarch64-darwin.default`. Building for
linux targets from macOS requires a remote builder.

nix-darwin provides `nix.linux-builder` — a QEMU-backed NixOS VM that acts as a
remote builder accessible via the nix daemon. Once enabled, `nix build
.#packages.x86_64-linux.default` transparently offloads compilation to the VM.

Currently the ksh26 flake has no cross-platform recipes, and the existing
`darwinModules.default` only handles `/etc/kshrc` generation.

## Goals / Non-Goals

**Goals:**
- Enable `just build-linux` and `just test-linux` from macOS.
- Export a nix-darwin module that configures linux-builder with
  settings appropriate for ksh26 development (CPU, memory, store sharing).
- Maintain the two-path model: cross-builds are validation-path only
  (nix-backed, content-addressed). No iteration-path cross-building.

**Non-Goals:**
- Cross-compilation (building linux binaries with a cross-compiler on darwin).
  This is remote-native-build via the builder VM.
- CI integration (GitHub Actions, Hydra). This is local development tooling.
- aarch64-linux targets from aarch64-darwin (QEMU arm→arm is slow and
  unreliable for testing). Focus on x86_64-linux.
- Iteration-path cross-builds. `test-one` and `debug` remain local-only.

## Decisions

### 1. Separate nix-darwin module for linux-builder

Export `darwinModules.linux-builder` alongside the existing `darwinModules.default`
(kshrc module). The linux-builder module configures `nix.linux-builder` with
tuned settings for ksh26 compilation.

**Why not inline in the user's darwin config?** The VM settings (cores, memory,
store paths) are ksh26-specific knowledge. Keeping them in the ksh26 flake means
they stay in sync with build requirements and can be updated when the build
changes (e.g., adding parallel test execution).

**Alternative: just document the settings.** Rejected — settings drift from
docs. A module is a living, versionable configuration.

### 2. x86_64-linux only (for now)

The linux-builder VM runs x86_64-linux via QEMU. On Apple Silicon this uses
Rosetta for Linux (fast) or plain QEMU emulation (slow). `aarch64-linux` would
require a separate VM or native arm builder.

Focus on x86_64-linux because:
- It's the most common CI target.
- Rosetta for Linux makes it performant on Apple Silicon.
- Adding aarch64-linux is additive later if needed.

### 3. Just recipes mirror existing validation pattern

New recipes follow the existing naming convention:

| Recipe | Command | Notes |
|--------|---------|-------|
| `build-linux` | `nix build .#packages.x86_64-linux.default` | Cross-build |
| `test-linux` | `nix build .#checks.x86_64-linux.default` | Cross-test |
| `test-linux-asan` | `nix build .#checks.x86_64-linux.asan` | Cross-test + asan |

All validation-path, all nix-backed. Same `--print-build-logs` pattern.

**Pre-flight check:** Recipes verify builder availability before invoking nix,
giving a clear error message pointing to the module setup. Use
`nix store ping --store ssh-ng://linux-builder` or check
`/etc/nix/machines` for a linux builder entry.

### 4. Module structure

```nix
# nix/darwin-linux-builder.nix
{ config, lib, pkgs, ... }:
{
  nix.linux-builder = {
    enable = true;
    maxJobs = 4;
    config = {
      virtualisation.cores = 4;
      virtualisation.memorySize = 4096;  # MB
      virtualisation.rosetta.enable = true;
    };
  };
}
```

Consumers add to their darwin config:
```nix
imports = [ ksh26.darwinModules.linux-builder ];
```

## Risks / Trade-offs

**[VM startup latency]** → First build after reboot waits for VM boot (~10s).
Subsequent builds reuse the running VM. Mitigation: document in CLAUDE.md.

**[Rosetta availability]** → Rosetta for Linux requires macOS 13+ and explicit
opt-in in nix-darwin. Mitigation: module enables it; pre-flight check
verifies builder responsiveness.

**[Store size]** → Linux builder VM has its own nix store. Cross-builds populate
it with linux closures. Mitigation: document `nix.linux-builder.config.nix.gc`
for periodic cleanup.

**[x86_64-only limitation]** → No aarch64-linux validation without a native
builder. Acceptable: x86_64-linux covers the primary CI target. aarch64-linux
can be added via remote builder config later.

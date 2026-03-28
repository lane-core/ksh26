## 1. nix-darwin linux-builder module

- [x] 1.1 Create `nix/darwin-linux-builder.nix` — module that configures `nix.linux-builder` with 4 cores, 4096 MB memory, Rosetta for Linux enabled
- [x] 1.2 Export as `darwinModules.linux-builder` in `flake.nix`
- [x] 1.3 Verify module composes with existing `darwinModules.default` (kshrc) without conflict

## 2. Pre-flight check

- [x] 2.1 Write a `_check-linux-builder` private just recipe that verifies a linux builder is reachable (check `/etc/nix/machines` or `nix store ping`), exits with actionable error if missing

## 3. Cross-platform just recipes

- [x] 3.1 Add `build-linux` recipe — runs pre-flight, then `nix build .#packages.x86_64-linux.default --print-build-logs`, links result to `result-linux`
- [x] 3.2 Add `test-linux` recipe — runs pre-flight, then `nix build .#checks.x86_64-linux.default --print-build-logs`
- [x] 3.3 Add `test-linux-asan` recipe — runs pre-flight, then `nix build .#checks.x86_64-linux.asan --print-build-logs`

## 4. Documentation

- [x] 4.1 Add cross-platform section to CLAUDE.md's build/test table (recipes, prerequisites, workflow)
- [x] 4.2 Update `openspec/specs/build-system/spec.md` with the modified two-path requirement (apply delta from change specs)

## 5. Validation

- [ ] 5.1 Enable linux-builder on Lane's darwin system, run `just build-linux` end-to-end
- [ ] 5.2 Run `just test-linux` end-to-end, verify test results match local test suite
- [ ] 5.3 Verify `just build-linux` without builder gives clear error message

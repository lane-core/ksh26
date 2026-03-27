# nix-darwin module: linux-builder for cross-platform ksh26 builds
#
# Enables the linux-builder VM for `just build-linux` / `just test-linux`
# and NixOS VM integration tests (`just test-nixos-vm`).
# VM resource settings (cores, memory, rosetta) are left to the user's
# nix-darwin config — this module only ensures the builder is present
# with the required system features.
#
# Usage in nix-darwin config:
#   imports = [ ksh26.darwinModules.linux-builder ];
{ ... }:

{
  nix.linux-builder = {
    enable = true;
    # nixos-test: required for testers.runNixOSTest (NixOS VM integration tests)
    supportedFeatures = [ "kvm" "benchmark" "big-parallel" "nixos-test" ];
  };
}

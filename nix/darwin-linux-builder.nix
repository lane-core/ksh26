# nix-darwin module: linux-builder for cross-platform ksh26 builds
#
# Enables the linux-builder VM for `just build-linux` / `just test-linux`.
# VM resource settings (cores, memory, rosetta) are left to the user's
# nix-darwin config — this module only ensures the builder is present.
#
# Usage in nix-darwin config:
#   imports = [ ksh26.darwinModules.linux-builder ];
{ ... }:

{
  nix.linux-builder.enable = true;
}

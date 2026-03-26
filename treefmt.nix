{ pkgs, ... }:
{
  projectRootFile = "flake.nix";

  programs.nixfmt.enable = true;

  # C formatting: clang-format is format-on-changed-only (see `just fmt`).
  # .clang-format exists for editor integration; treefmt doesn't enforce it
  # because the legacy codebase isn't reformatted yet.

  settings.global.excludes = [
    "build/*"
    "arch/*"
    "src/cmd/INIT/*"
  ];
}

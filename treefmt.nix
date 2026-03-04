{ pkgs, ... }:
{
  projectRootFile = "flake.nix";

  programs.nixfmt.enable = true;

  programs.clang-format = {
    enable = true;
    includes = [
      "*.c"
      "*.h"
    ];
  };

  settings.global.excludes = [
    "build/*"
    "arch/*"
    "src/cmd/INIT/*"
  ];
}

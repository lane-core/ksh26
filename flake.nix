{
  description = "ksh26 — the KornShell, redesigned";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    nix-vm-test.url = "github:numtide/nix-vm-test";
    nix-github-actions.url = "github:nix-community/nix-github-actions";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    nix-vm-test.inputs.nixpkgs.follows = "nixpkgs";
    nix-github-actions.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      imports =
        with builtins;
        map (fn: ./nix/modules/${fn}) (attrNames (readDir ./nix/modules));

      flake = {
        overlays.default = final: prev: {
          ksh26 = inputs.self.packages.${final.system}.default;
          ksh = final.ksh26;
        };
        homeManagerModules.default = import ./nix/hm-module.nix;
        darwinModules.default = import ./nix/darwin-module.nix;
        darwinModules.linux-builder = import ./nix/darwin-linux-builder.nix;
        nixosModules.default = import ./nix/nixos-module.nix;
      };
    };
}

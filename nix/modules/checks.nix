{ inputs, ... }:

{
  perSystem =
    {
      pkgs,
      lib,
      self',
      config,
      ...
    }:
    let
      treefmtEval = inputs.treefmt-nix.lib.evalModule pkgs ./../../treefmt.nix;
    in
    {
      checks =
        {
          default = self'.packages.checked;
          fast = self'.packages.checked-fast;
          asan = self'.packages.checked-asan;
          formatting = treefmtEval.config.build.check inputs.self;
        }
        // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          nixos = self'.packages.nixos-test;
        };

      formatter = treefmtEval.config.build.wrapper;
    };
}

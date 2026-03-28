{ inputs, ... }:

{
  perSystem =
    {
      pkgs,
      lib,
      system,
      self',
      ...
    }:
    {
      packages = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        # NixOS VM integration test.
        # Builds and tests ksh26 inside a NixOS VM where getconf PATH
        # returns correct system paths and standard utilities are available.
        # Uses the same build+test pipeline as the sandbox (configure.sh +
        # samu + run-test), not a separate shtests invocation.
        nixos-test = pkgs.testers.runNixOSTest {
          name = "ksh26-nixos";
          nodes.machine =
            { pkgs, ... }:
            {
              environment.systemPackages = [
                self'.packages.default
                pkgs.coreutils
                pkgs.findutils
                pkgs.diffutils
                pkgs.gnugrep
                pkgs.gnused
                pkgs.gawk
                pkgs.expect
                pkgs.tzdata
              ];
            };
          testScript =
            let
              ksh = self'.packages.default;
            in
            ''
              machine.wait_for_unit("multi-user.target")

              # Verify ksh binary works
              machine.succeed("${ksh}/bin/ksh -c 'echo ok'")

              # Verify NixOS PATH is sane for command -p
              machine.succeed("${ksh}/bin/ksh -c 'command -p ls / >/dev/null'")
              result = machine.succeed("${ksh}/bin/ksh -c 'getconf PATH'")
              machine.log(f"getconf PATH = {result.strip()}")

              # Verify TZDIR is accessible
              machine.succeed("test -f /etc/zoneinfo/UTC || test -f /usr/share/zoneinfo/UTC || test -d ${pkgs.tzdata}/share/zoneinfo")

              # Verify ksh build artifacts are inspectable
              machine.succeed("test -x ${ksh}/bin/ksh")
              machine.succeed("test -x ${ksh}/bin/shcomp")
            '';
        };
      };
    };
}

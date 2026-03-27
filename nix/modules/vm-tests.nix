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
        # NixOS VM integration test — authoritative linux test.
        # Runs the full test suite inside a NixOS VM where getconf PATH
        # returns correct system paths and all standard utilities are
        # available. Replaces sandbox checkPhase as the linux test gate.
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
              testSrc = inputs.self;
            in
            ''
              machine.wait_for_unit("multi-user.target")

              # Verify ksh works and PATH is sane
              machine.succeed("${ksh}/bin/ksh -c 'command -p ls / >/dev/null'")
              machine.succeed("${ksh}/bin/ksh -c 'getconf PATH'")

              # Set up test environment
              machine.succeed("cp -r ${testSrc}/src/cmd/ksh26/tests /tmp/ksh-tests")
              machine.succeed("chmod -R u+w /tmp/ksh-tests")
              machine.succeed("mkdir -p /tmp/ksh-run")

              # Run the test suite via shtests
              machine.succeed(
                "cd /tmp/ksh-run && "
                "SHELL=${ksh}/bin/ksh "
                "tmp=/tmp/ksh-run "
                "${ksh}/bin/ksh /tmp/ksh-tests/shtests "
                "--all 2>&1 | tee /tmp/ksh-test.log"
              )
            '';
        };
      };
    };
}

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
      memoryHook = ''
        case "$(uname -s)" in
        Linux) ulimit -v 2097152 2>/dev/null ;;
        esac
      '';
    in
    {
      devShells = {
        default = pkgs.mkShell {
          packages =
            [
              pkgs.just
              pkgs.git
              pkgs.pkg-config
              pkgs.ccache
              pkgs.dash
              pkgs.expect
              treefmtEval.config.build.wrapper
            ]
            ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
              pkgs.lldb
            ]
            ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
              pkgs.gdb
              pkgs.valgrind
            ];
          inputsFrom = [ self'.packages.default ];
          shellHook = memoryHook;
        };

        agent = pkgs.mkShell {
          inputsFrom = [ config.devShells.default ];
          env.CC = "ccache cc";
          shellHook =
            memoryHook
            + ''
              _ht="$(uname -s | tr 'A-Z' 'a-z').$(uname -m | sed 's/arm64/arm64-64/;s/x86_64/x86_64-64/;s/aarch64/aarch64-64/')"
              echo "ksh26 agent shell — $(git rev-parse --short HEAD) on $(git branch --show-current) [$_ht]"
              if [[ ! -f "build/$_ht/build.ninja" ]]; then
                echo "Running initial configure..."
                just configure
              fi
            '';
        };
      };
    };
}

{
  description = "ksh26 — independent fork of ksh93u+m";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";

  outputs =
    {
      self,
      nixpkgs,
      treefmt-nix,
    }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      treefmtEval = forAllSystems (
        system: treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${system} ./treefmt.nix
      );
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          ksh26 = { doCheck ? true }:
            let
              hostType = 
                let
                  inherit (pkgs.stdenv.hostPlatform.parsed) kernel cpu;
                  os = kernel.name;
                  arch = 
                    if cpu.name == "aarch64" then "arm64"
                    else if cpu.name == "x86_64" then "x86_64"
                    else if pkgs.lib.hasPrefix "i" cpu.name && pkgs.lib.hasSuffix "86" cpu.name then "i386"
                    else cpu.name;
                  bits = toString cpu.bits;
                in "${os}.${arch}-${bits}";
            in
            pkgs.stdenv.mkDerivation {
              pname = "ksh26";
              version = "0.1.0-alpha";

              src = self;

              nativeBuildInputs = [
                pkgs.scdoc
              ] ++ pkgs.lib.optionals doCheck [
                pkgs.expect
                pkgs.parallel
              ];

              buildInputs = [
                pkgs.utf8proc
              ]
              ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
                pkgs.libiconv
              ];

              dontConfigure = true;
              HOSTTYPE = hostType;

              buildPhase = ''
                runHook preBuild

                # Bootstrap samu
                mkdir -p build/$HOSTTYPE/bin
                $CC -o build/$HOSTTYPE/bin/samu src/cmd/INIT/samu/*.c

                # Configure (feature probes + generate build.ninja)
                sh configure.sh

                # Build
                ./build/$HOSTTYPE/bin/samu -C build/$HOSTTYPE

                runHook postBuild
              '';

              inherit doCheck;

              checkPhase = pkgs.lib.optionalString doCheck ''
                runHook preCheck

                # Sanity check: ensure we have expected test count
                stamp_count=$(grep '^build test: phony' build/$HOSTTYPE/build.ninja \
                  | tr ' ' '\n' | grep -c '\.stamp$' || true)
                if (( stamp_count < 114 )); then
                  echo "FAIL: expected >=114 test stamps, found $stamp_count" >&2
                  exit 1
                fi

                # Run all tests
                ./build/$HOSTTYPE/bin/samu -k 0 -C build/$HOSTTYPE test

                # Aggregate and print summary from per-test result files
                # (Per-test files reduce parallel write contention vs single summary.log)
                result_dir="build/$HOSTTYPE/test/results"
                if [ -d "$result_dir" ]; then
                  # Single-pass awk: count pass/fail/skip and format failures
                  awk '
                    /^ok / { pass++; print > "/dev/stderr"; next }
                    /^not ok / { fail++; sub(/^not ok - /, "  FAIL: "); print > "/dev/stderr"; next }
                    /# SKIP/ { skip++ }
                    END {
                      total = pass + fail + skip
                      printf "---\n%d/%d pass", pass, total > "/dev/stderr"
                      if (skip > 0) printf ", %d skipped", skip > "/dev/stderr"
                      print "" > "/dev/stderr"
                    }
                  ' "$result_dir"/*.txt 2>&1
                fi

                runHook postCheck
              '';

              installPhase = ''
                runHook preInstall
                install -Dm755 build/$HOSTTYPE/bin/ksh "$out/bin/ksh"
                install -Dm755 build/$HOSTTYPE/bin/shcomp "$out/bin/shcomp"
                install -Dm755 build/$HOSTTYPE/bin/pty "$out/bin/pty"
                runHook postInstall
              '';

              passthru.shellPath = "/bin/ksh";

              meta = with pkgs.lib; {
                description = "ksh26 — independent fork of the KornShell (ksh93u+m)";
                homepage = "https://github.com/lane-core/ksh";
                license = licenses.epl20;
                platforms = platforms.unix;
                mainProgram = "ksh";
              };
            };
        in
        {
          # Default: build only (fast, for end users)
          default = ksh26 { doCheck = false; };

          # Full validation: build + test (for CI)
          checked = ksh26 { doCheck = true; };

          build-debug = (ksh26 { doCheck = false; }).overrideAttrs (old: {
            pname = "ksh26-debug";
            buildPhase = ''
              runHook preBuild
              mkdir -p build/$HOSTTYPE/bin
              $CC -o build/$HOSTTYPE/bin/samu src/cmd/INIT/samu/*.c
              sh configure.sh --debug
              ./build/$HOSTTYPE/bin/samu -C build/$HOSTTYPE-debug
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              install -Dm755 build/$HOSTTYPE-debug/bin/ksh "$out/bin/ksh"
              install -Dm755 build/$HOSTTYPE-debug/bin/shcomp "$out/bin/shcomp"
              install -Dm755 build/$HOSTTYPE-debug/bin/pty "$out/bin/pty"
              runHook postInstall
            '';
          });

          build-asan = (ksh26 { doCheck = false; }).overrideAttrs (old: {
            pname = "ksh26-asan";
            buildPhase = ''
              runHook preBuild
              mkdir -p build/$HOSTTYPE/bin
              $CC -o build/$HOSTTYPE/bin/samu src/cmd/INIT/samu/*.c
              sh configure.sh --asan
              ./build/$HOSTTYPE/bin/samu -C build/$HOSTTYPE-asan
              runHook postBuild
            '';
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              stamp_count=$(grep '^build test: phony' build/$HOSTTYPE-asan/build.ninja \
                | tr ' ' '\n' | grep -c '\.stamp$' || true)
              if (( stamp_count < 114 )); then
                echo "FAIL: expected >=114 test stamps, found $stamp_count" >&2
                exit 1
              fi
              export ASAN_OPTIONS="halt_on_error=1:detect_leaks=0"
              ./build/$HOSTTYPE/bin/samu -k 0 -C build/$HOSTTYPE-asan test
              # Aggregate results from per-test result files
              result_dir="build/$HOSTTYPE-asan/test/results"
              if [ -d "$result_dir" ]; then
                awk '
                  /^ok / { pass++; print > "/dev/stderr"; next }
                  /^not ok / { fail++; sub(/^not ok - /, "  FAIL: "); print > "/dev/stderr"; next }
                  /# SKIP/ { skip++ }
                  END {
                    total = pass + fail + skip
                    printf "---\n%d/%d pass", pass, total > "/dev/stderr"
                    if (skip > 0) printf ", %d skipped", skip > "/dev/stderr"
                    print "" > "/dev/stderr"
                  }
                ' "$result_dir"/*.txt 2>&1
              fi
              runHook postCheck
            '';
            installPhase = ''
              runHook preInstall
              install -Dm755 build/$HOSTTYPE-asan/bin/ksh "$out/bin/ksh"
              install -Dm755 build/$HOSTTYPE-asan/bin/shcomp "$out/bin/shcomp"
              install -Dm755 build/$HOSTTYPE-asan/bin/pty "$out/bin/pty"
              runHook postInstall
            '';
          });
        }
      );

      overlays.default = final: prev: {
        ksh26 = self.packages.${prev.stdenv.hostPlatform.system}.default;
        ksh = final.ksh26;
      };

      homeManagerModules.default = import ./nix/hm-module.nix;
      darwinModules.default = import ./nix/darwin-module.nix;
      nixosModules.default = import ./nix/nixos-module.nix;

      formatter = forAllSystems (system: treefmtEval.${system}.config.build.wrapper);

      apps = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          diagnose = {
            type = "app";
            program = toString (pkgs.writeShellScript "ksh26-diagnose" ''
              set -eu
              test_name="''${1:-}"
              locale="''${2:-C}"

              if [ -z "$test_name" ]; then
                echo "Usage: nix run .#diagnose -- <test-name> [locale]"
                echo ""
                echo "Per Immutable Test Sanctity (CLAUDE.md): investigates context"
                echo "deficiencies, never test logic."
                exit 1
              fi

              echo "=== ksh26 Test Failure Diagnosis ==="
              echo "Test: $test_name (mode: $locale)"
              echo ""

              if [ ! -f "tests/shell/''${test_name}.sh" ]; then
                echo "ERROR: Test not found: tests/shell/''${test_name}.sh"
                exit 1
              fi

              echo "Context adaptations:"
              for ctx in default tty fixtures timing; do
                [ -f "tests/contexts/''${ctx}.sh" ] && echo "  [✓] contexts/''${ctx}.sh"
              done
              echo ""

              nix build .#checks.${system}.default --print-build-logs 2>&1 || true

              echo ""
              echo "=== Investigation ==="
              echo "1. Run outside Nix: just test-one $test_name $locale"
              echo "2. Check contexts: cat tests/contexts/*.sh"
              echo "3. Debug: just debug $test_name"
            '');
          };
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          memoryHook = ''
            case "$(uname -s)" in
            Linux) ulimit -v 2097152 2>/dev/null ;;
            esac
          '';
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.just
              pkgs.git
              pkgs.pkg-config
              pkgs.ccache
              pkgs.dash
              pkgs.expect
              treefmtEval.${system}.config.build.wrapper
            ]
            ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
              pkgs.lldb
            ]
            ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
              pkgs.gdb
              pkgs.valgrind
            ];
            inputsFrom = [ self.packages.${system}.default ];
            shellHook = memoryHook;
          };

          agent = pkgs.mkShell {
            inputsFrom = [ self.devShells.${system}.default ];
            env.CC = "ccache cc";
            shellHook = memoryHook + ''
              _ht="$(uname -s | tr 'A-Z' 'a-z').$(uname -m | sed 's/aarch64/arm64/;s/i.86/i386/')-$(getconf LONG_BIT 2>/dev/null || echo 64)"
              echo "ksh26 agent shell — $(git rev-parse --short HEAD) on $(git branch --show-current) [$_ht]"
              if [[ ! -f "build/$_ht/build.ninja" ]]; then
                echo "Running initial configure..."
                just configure
              fi
            '';
          };
        }
      );

      checks = forAllSystems (
        system:
        {
          # Default check: full build + test
          default = self.packages.${system}.checked;

          # Formatting check
          formatting = treefmtEval.${system}.config.build.check self;

          # ASan check (separate derivation with sanitizers)
          asan = self.packages.${system}.build-asan;
        }
      );
    };
}

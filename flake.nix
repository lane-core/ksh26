{
  description = "ksh26 — the KornShell, redesigned";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      treefmt-nix,
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Map nix platform to the HOSTTYPE that configure.sh computes via uname.
      # Darwin uname -m reports "arm64" (not "aarch64"); Linux reports "aarch64".
      hostTypeFor =
        pkgs:
        let
          inherit (pkgs.stdenv.hostPlatform) isDarwin;
          inherit (pkgs.stdenv.hostPlatform.parsed) kernel cpu;
          os = kernel.name;
          arch = if cpu.name == "aarch64" && isDarwin then "arm64" else cpu.name;
          bits = toString cpu.bits;
        in
        "${os}.${arch}-${bits}";

      treefmtEval = forAllSystems (
        system: treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${system} ./treefmt.nix
      );
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          hostType = hostTypeFor pkgs;

          # Core build function. All variants go through here.
          mkKsh =
            {
              variant ? "",
              configureFlags ? [ ],
              doCheck ? false,
              extraCheckSetup ? "",
            }:
            let
              buildDir = "build/${hostType}${variant}";
              flagStr = builtins.concatStringsSep " " configureFlags;
            in
            pkgs.stdenv.mkDerivation {
              pname = "ksh26${variant}";
              version = "0.1.0-alpha";

              src = self;

              nativeBuildInputs = pkgs.lib.optionals doCheck [
                pkgs.expect
              ] ++ pkgs.lib.optionals doCheck [
                pkgs.tzdata
              ];

              buildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
                pkgs.libiconv
              ];

              dontConfigure = true;

              buildPhase = ''
                runHook preBuild

                # Bootstrap samu (vendored ninja)
                mkdir -p ${buildDir}/bin
                $CC -o ${buildDir}/bin/samu src/cmd/INIT/samu/*.c

                # Configure (feature probes + generate build.ninja)
                # Modernish needs DEFPATH to find standard utilities.
                # In nix build sandboxes, getconf PATH returns paths
                # that don't exist (/usr/bin, /bin). Pass the sandbox
                # PATH so modernish can find awk, sed, etc.
                _Msh_DEFPATH="$PATH" sh configure.sh ${flagStr}

                # Build
                ./${buildDir}/bin/samu -f ${buildDir}/build.ninja

                runHook postBuild
              '';

              inherit doCheck;

              checkPhase = pkgs.lib.optionalString doCheck ''
                runHook preCheck

                ${extraCheckSetup}

                # Sanity check: ensure we have expected test count
                stamp_count=$(grep '^build test: phony' ${buildDir}/build.ninja \
                  | tr ' ' '\n' | grep -c '\.stamp$' || true)
                if (( stamp_count < 112 )); then
                  echo "FAIL: expected >=112 test stamps, found $stamp_count" >&2
                  exit 1
                fi

                # Make timezone data available for printf %T tests
                # Darwin sandbox may not expose /usr/share/zoneinfo
                export TZDIR="''${TZDIR:-${pkgs.tzdata}/share/zoneinfo}"

                # Run all tests (-k 0 = continue on failure, collect all results)
                ./${buildDir}/bin/samu -k 0 -f ${buildDir}/build.ninja test || true

                # Aggregate results from per-test result files.
                # All tests are gated — no sandbox-unreliable exemptions.
                # 56 tests × 2 locales = 112 stamps, all must pass.
                result_dir="${buildDir}/test/results"
                if [ -d "$result_dir" ] && ls "$result_dir"/*.txt >/dev/null 2>&1; then
                  min_pass=112

                  awk -v min_pass="$min_pass" '
                    /^ok / { pass++; print; next }
                    /^not ok / {
                      fail++
                      fail_names = fail_names " " $4
                      print
                      next
                    }
                    END {
                      printf "---\n%d/%d tests pass\n", pass, pass + fail
                      if (fail > 0) printf "failures:%s\n", fail_names
                      if (pass < min_pass) {
                        printf "FAIL: expected >=%d tests to pass, got %d\n", min_pass, pass > "/dev/stderr"
                        exit 1
                      }
                    }
                  ' "$result_dir"/*.txt
                fi

                runHook postCheck
              '';

              installPhase = ''
                runHook preInstall
                install -Dm755 ${buildDir}/bin/ksh "$out/bin/ksh"
                install -Dm755 ${buildDir}/bin/shcomp "$out/bin/shcomp"
                install -Dm755 ${buildDir}/bin/pty "$out/bin/pty"

                # Export build artifacts for inspection (FEATURE files,
                # test logs, generated headers, sysdeps).
                mkdir -p "$out/build-artifacts/feat"
                for lib in libast ksh26 libcmd pty; do
                  if [ -d "${buildDir}/feat/$lib/FEATURE" ]; then
                    mkdir -p "$out/build-artifacts/feat/$lib/FEATURE"
                    cp ${buildDir}/feat/$lib/FEATURE/* \
                      "$out/build-artifacts/feat/$lib/FEATURE/" 2>/dev/null || true
                  fi
                  # Copy generated headers (ast_*.h, sig.h, etc.) — files only, skip symlinks
                  for f in ${buildDir}/feat/$lib/*.h; do
                    [ -f "$f" ] && [ ! -L "$f" ] && cp "$f" "$out/build-artifacts/feat/$lib/" 2>/dev/null || true
                  done
                done
                cp ${buildDir}/sysdeps "$out/build-artifacts/" 2>/dev/null || true
                cp ${buildDir}/probe_defs.h "$out/build-artifacts/" 2>/dev/null || true
                cp -r ${buildDir}/test "$out/build-artifacts/" 2>/dev/null || true

                runHook postInstall
              '';

              passthru.shellPath = "/bin/ksh";

              meta = with pkgs.lib; {
                description = "ksh26 — the KornShell, redesigned";
                homepage = "https://github.com/lane-core/ksh26";
                license = licenses.epl20;
                platforms = platforms.unix;
                mainProgram = "ksh";
              };
            };
        in
        {
          # Build only (fast, for end users)
          default = mkKsh { };

          # Build + test (for CI / validation)
          checked = mkKsh { doCheck = true; };

          # Debug build
          build-debug = mkKsh {
            variant = "-debug";
            configureFlags = [ "--debug" ];
          };

          # Sanitizer build (no tests)
          build-asan = mkKsh {
            variant = "-asan";
            configureFlags = [ "--asan" ];
          };

          # Sanitizer build + test
          checked-asan = mkKsh {
            variant = "-asan";
            configureFlags = [ "--asan" ];
            doCheck = true;
            extraCheckSetup = ''
              export ASAN_OPTIONS="halt_on_error=1:detect_leaks=0"
            '';
          };

          # Debug crash investigation: build with -g, run failing tests
          # under gdb to capture backtraces. Output goes to $out/crash-report.
          crash-debug = let
            inherit (pkgs) stdenv;
          in stdenv.mkDerivation {
            pname = "ksh26-crash-debug";
            version = "0.1.0-alpha";
            src = self;
            nativeBuildInputs = [ pkgs.expect pkgs.tzdata pkgs.gdb ];
            buildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
              pkgs.libiconv
            ];
            dontConfigure = true;
            buildPhase = let
              buildDir = "build/${hostType}-debug";
            in ''
              mkdir -p ${buildDir}/bin
              $CC -o ${buildDir}/bin/samu src/cmd/INIT/samu/*.c
              _Msh_DEFPATH="$PATH" sh configure.sh --debug
              ./${buildDir}/bin/samu -f ${buildDir}/build.ninja
            '';
            doCheck = true;
            checkPhase = let
              buildDir = "build/${hostType}-debug";
            in ''
              mkdir -p $out

              # Set up minimal test environment matching run-test
              export SHELL="${buildDir}/bin/ksh"
              export SHCOMP="${buildDir}/bin/shcomp"
              export SHTESTS_COMMON="src/cmd/ksh26/tests/_common"
              export ENV=/./dev/null

              for test in namespace leaks; do
                echo "=== Testing $test.C.UTF-8 ===" | tee -a $out/crash-report.txt

                # Create per-test temp dir and cd into it (run-test does this)
                _tmp=$(mktemp -d)
                _tmp=$(cd -P "$_tmp" && pwd)
                _src=$(pwd)

                # Run under gdb with test environment
                (
                  cd "$_tmp"
                  HOME="$_tmp" tmp="$_tmp" LANG=C.UTF-8 \
                    SHTESTS_COMMON="$_src/src/cmd/ksh26/tests/_common" \
                    SHELL="$_src/$SHELL" \
                    SHCOMP="$_src/$SHCOMP" \
                    timeout 60 gdb -batch \
                    -ex "set confirm off" \
                    -ex "set print frame-arguments all" \
                    -ex run \
                    -ex "bt full" \
                    -ex "info registers" \
                    -ex "thread apply all bt" \
                    -ex quit \
                    --args "$_src/$SHELL" "$_src/src/cmd/ksh26/tests/$test.sh" \
                    2>&1 || true
                ) | tee -a $out/crash-report.txt

                rm -rf "$_tmp"
                echo "" >> $out/crash-report.txt
              done
            '';
            installPhase = ''
              # $out already has crash-report.txt from checkPhase
              test -f $out/crash-report.txt || echo "no crash report" > $out/crash-report.txt
            '';
          };
        }
      );

      checks = forAllSystems (system: {
        default = self.packages.${system}.checked;
        asan = self.packages.${system}.checked-asan;
        formatting = treefmtEval.${system}.config.build.check self;
      });

      formatter = forAllSystems (system: treefmtEval.${system}.config.build.wrapper);

      overlays.default = final: prev: {
        ksh26 = self.packages.${final.system}.default;
        ksh = final.ksh26;
      };

      homeManagerModules.default = import ./nix/hm-module.nix;
      darwinModules.default = import ./nix/darwin-module.nix;
      darwinModules.linux-builder = import ./nix/darwin-linux-builder.nix;
      nixosModules.default = import ./nix/nixos-module.nix;

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
              _ht="$(uname -s | tr 'A-Z' 'a-z').$(uname -m | sed 's/arm64/arm64-64/;s/x86_64/x86_64-64/;s/aarch64/aarch64-64/')"
              echo "ksh26 agent shell — $(git rev-parse --short HEAD) on $(git branch --show-current) [$_ht]"
              if [[ ! -f "build/$_ht/build.ninja" ]]; then
                echo "Running initial configure..."
                just configure
              fi
            '';
          };
        }
      );
    };
}

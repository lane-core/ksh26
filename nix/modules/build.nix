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
    let
      # Map nix platform to the HOSTTYPE that configure.sh computes via uname.
      hostType =
        let
          inherit (pkgs.stdenv.hostPlatform) isDarwin;
          inherit (pkgs.stdenv.hostPlatform.parsed) kernel cpu;
          os = kernel.name;
          arch = if cpu.name == "aarch64" && isDarwin then "arm64" else cpu.name;
          bits = toString cpu.bits;
        in
        "${os}.${arch}-${bits}";

      # Build ksh26. Always succeeds and is cached — no tests here.
      mkKsh =
        {
          variant ? "",
          configureFlags ? [ ],
        }:
        let
          buildDir = "build/${hostType}${variant}";
          flagStr = builtins.concatStringsSep " " configureFlags;
        in
        pkgs.stdenv.mkDerivation {
          pname = "ksh26${variant}";
          version = "0.1.0-alpha";

          src = inputs.self;

          buildInputs = lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
            pkgs.libiconv
          ];

          configurePhase = ''
            runHook preConfigure
            mkdir -p ${buildDir}/bin
            $CC -o ${buildDir}/bin/samu src/cmd/INIT/samu/*.c
            _Msh_DEFPATH="$PATH" sh configure.sh ${flagStr}
            runHook postConfigure
          '';

          buildPhase = ''
            runHook preBuild
            ./${buildDir}/bin/samu -C ${buildDir}
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            install -Dm755 ${buildDir}/bin/ksh "$out/bin/ksh"
            install -Dm755 ${buildDir}/bin/shcomp "$out/bin/shcomp"
            install -Dm755 ${buildDir}/bin/pty "$out/bin/pty"
            runHook postInstall
          '';

          postInstall = ''
            mkdir -p "$out/build-artifacts/feat"
            for l in libast ksh26 libcmd pty; do
              if [ -d "${buildDir}/feat/$l/FEATURE" ]; then
                mkdir -p "$out/build-artifacts/feat/$l/FEATURE"
                cp ${buildDir}/feat/$l/FEATURE/* \
                  "$out/build-artifacts/feat/$l/FEATURE/" 2>/dev/null || true
              fi
              for f in ${buildDir}/feat/$l/*.h; do
                [ -f "$f" ] && [ ! -L "$f" ] && cp "$f" "$out/build-artifacts/feat/$l/" 2>/dev/null || true
              done
            done
            cp ${buildDir}/sysdeps "$out/build-artifacts/" 2>/dev/null || true
            cp ${buildDir}/probe_defs.h "$out/build-artifacts/" 2>/dev/null || true
            cp -r ${buildDir}/log "$out/build-artifacts/" 2>/dev/null || true

            # Export the build directory for test derivations
            cp -r ${buildDir}/bin "$out/build-artifacts/"
            cp ${buildDir}/build.ninja "$out/build-artifacts/"
            cp ${buildDir}/test-env.sh "$out/build-artifacts/"
          '';

          passthru = {
            shellPath = "/bin/ksh";
            inherit configureFlags hostType buildDir;
          };

          meta = with lib; {
            description = "ksh26 — the KornShell, redesigned";
            homepage = "https://github.com/lane-core/ksh26";
            license = licenses.epl20;
            platforms = platforms.unix;
            mainProgram = "ksh";
          };
        };

      # Test ksh26. Separate derivation that depends on the build.
      # The build is cached — only tests rerun.
      mkTest =
        {
          ksh,
          variant ? "",
          checkCategory ? "",
          extraCheckSetup ? "",
        }:
        let
          buildDir = "build/${hostType}${variant}";
          testTarget = if checkCategory != "" then "test-${checkCategory}" else "test";
        in
        pkgs.stdenv.mkDerivation {
          pname = "ksh26-tests${variant}${lib.optionalString (checkCategory != "") "-${checkCategory}"}";
          version = "0.1.0-alpha";

          src = inputs.self;

          nativeBuildInputs = [
            pkgs.expect
            pkgs.tzdata
          ];

          buildInputs = lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
            pkgs.libiconv
          ];

          # Rebuild: bootstrap samu + configure + build (needed for test rules in build.ninja)
          configurePhase = ''
            runHook preConfigure
            mkdir -p ${buildDir}/bin
            $CC -o ${buildDir}/bin/samu src/cmd/INIT/samu/*.c
            _Msh_DEFPATH="$PATH" sh configure.sh ${builtins.concatStringsSep " " (ksh.passthru.configureFlags or [])}
            runHook postConfigure
          '';

          buildPhase = ''
            runHook preBuild
            ./${buildDir}/bin/samu -C ${buildDir}
            runHook postBuild
          '';

          doCheck = true;

          preCheck = ''
            export TZDIR="''${TZDIR:-${pkgs.tzdata}/share/zoneinfo}"
            ${extraCheckSetup}
          '';

          checkPhase = ''
            runHook preCheck

            stamp_count=$(grep -c '^build test/.*\.stamp:' ${buildDir}/build.ninja || true)
            if (( stamp_count == 0 )); then
              echo "FAIL: no test stamps found in build.ninja" >&2
              exit 1
            fi

            ./${buildDir}/bin/samu -k 0 -C ${buildDir} ${testTarget} || true

            result_dir="${buildDir}/test/results"
            pass=0 fail=0
            if [ -d "$result_dir" ] && ls "$result_dir"/*.txt >/dev/null 2>&1; then
              while read -r line; do
                case "$line" in
                'ok '*)     pass=$((pass + 1)); echo "$line" ;;
                'not ok '*) fail=$((fail + 1)); echo "$line" ;;
                esac
              done < <(cat "$result_dir"/*.txt)
            fi
            echo "---"
            echo "$pass/$stamp_count tests pass"
            if (( pass + fail != stamp_count )); then
              echo "FAIL: $((stamp_count - pass - fail)) tests did not report results" >&2
              exit 1
            fi
            ${if pkgs.stdenv.hostPlatform.isDarwin then ''
            if (( fail > 0 )); then
              echo "FAIL: $fail tests failed" >&2
              exit 1
            fi
            '' else ''
            # Linux: report only (NixOS PATH issues may cause known failures)
            ''}

            runHook postCheck
          '';

          installPhase = ''
            mkdir -p "$out"
            cp -r ${buildDir}/test "$out/" 2>/dev/null || true
            echo "$pass/$stamp_count" > "$out/summary.txt"
          '';
        };

    in
    {
      _module.args.mkKsh = mkKsh;
      _module.args.mkTest = mkTest;
      _module.args.hostType = hostType;

      packages = {
        default = mkKsh { };
        build-debug = mkKsh {
          variant = "-debug";
          configureFlags = [ "--debug" ];
        };
        build-asan = mkKsh {
          variant = "-asan";
          configureFlags = [ "--asan" ];
        };

        # Test derivations — separate from build, can fail without losing the binary
        checked = mkTest { ksh = self'.packages.default; };
        checked-fast = mkTest { ksh = self'.packages.default; checkCategory = "fast"; };
        checked-asan = mkTest {
          ksh = self'.packages.build-asan;
          variant = "-asan";
          extraCheckSetup = ''
            export ASAN_OPTIONS="halt_on_error=1:detect_leaks=0"
          '';
        };

        crash-debug =
          let
            buildDir = "build/${hostType}-debug";
          in
          pkgs.stdenv.mkDerivation {
            pname = "ksh26-crash-debug";
            version = "0.1.0-alpha";
            src = inputs.self;
            nativeBuildInputs = [
              pkgs.expect
              pkgs.tzdata
              pkgs.gdb
            ];
            buildInputs = lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
              pkgs.libiconv
            ];
            configurePhase = ''
              runHook preConfigure
              mkdir -p ${buildDir}/bin
              $CC -o ${buildDir}/bin/samu src/cmd/INIT/samu/*.c
              _Msh_DEFPATH="$PATH" sh configure.sh --debug
              runHook postConfigure
            '';
            buildPhase = ''
              runHook preBuild
              ./${buildDir}/bin/samu -C ${buildDir}
              runHook postBuild
            '';
            doCheck = true;
            checkPhase = ''
              mkdir -p $out
              export SHELL="${buildDir}/bin/ksh"
              export SHCOMP="${buildDir}/bin/shcomp"
              export SHTESTS_COMMON="src/cmd/ksh26/tests/_common"
              export ENV=/./dev/null

              for test in namespace leaks; do
                echo "=== Testing $test.C.UTF-8 ===" | tee -a $out/crash-report.txt
                _tmp=$(mktemp -d)
                _tmp=$(cd -P "$_tmp" && pwd)
                _src=$(pwd)
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
              test -f $out/crash-report.txt || echo "no crash report" > $out/crash-report.txt
            '';
          };
      };
    };
}

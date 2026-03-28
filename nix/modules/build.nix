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
      # Darwin uname -m reports "arm64" (not "aarch64"); Linux reports "aarch64".
      hostType =
        let
          inherit (pkgs.stdenv.hostPlatform) isDarwin;
          inherit (pkgs.stdenv.hostPlatform.parsed) kernel cpu;
          os = kernel.name;
          arch = if cpu.name == "aarch64" && isDarwin then "arm64" else cpu.name;
          bits = toString cpu.bits;
        in
        "${os}.${arch}-${bits}";

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

          src = inputs.self;

          nativeBuildInputs = lib.optionals doCheck [
            pkgs.expect
            pkgs.tzdata
          ];

          buildInputs = lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
            pkgs.libiconv
          ];

          dontConfigure = true;

          buildPhase = ''
            runHook preBuild

            mkdir -p ${buildDir}/bin
            echo "[bootstrap] compiling samu"
            $CC -o ${buildDir}/bin/samu src/cmd/INIT/samu/*.c

            _Msh_DEFPATH="$PATH" sh configure.sh ${flagStr}

            echo "[build] compiling ksh26"
            ./${buildDir}/bin/samu -f ${buildDir}/build.ninja

            runHook postBuild
          '';

          inherit doCheck;

          checkPhase = lib.optionalString doCheck ''
            runHook preCheck

            ${extraCheckSetup}

            # Make timezone data available for printf %T tests
            # Darwin sandbox may not expose /usr/share/zoneinfo
            export TZDIR="''${TZDIR:-${pkgs.tzdata}/share/zoneinfo}"

            # Count test stamps from generated build.ninja
            stamp_count=$(grep '^build test: phony' ${buildDir}/build.ninja \
              | tr ' ' '\n' | grep -c '\.stamp$' || true)
            if (( stamp_count == 0 )); then
              echo "FAIL: no test stamps found in build.ninja" >&2
              exit 1
            fi

            # Run all tests (-k 0 = continue on failure, collect all results)
            ./${buildDir}/bin/samu -k 0 -f ${buildDir}/build.ninja test || true

            # Aggregate and report test results.
            # Darwin: any failure is fatal.
            # Linux: report only — NixOS lacks FHS paths, VM tests are authoritative.
            result_dir="${buildDir}/test/results"
            if [ -d "$result_dir" ] && ls "$result_dir"/*.txt >/dev/null 2>&1; then
              awk '
                /^ok / { pass++; print; next }
                /^not ok / { fail++; fail_names = fail_names " " $4; print; next }
                END {
                  printf "---\n%d/%d tests pass\n", pass, pass + fail
                  if (fail > 0) printf "failures:%s\n", fail_names
                }
              ' "$result_dir"/*.txt
              ${if pkgs.stdenv.hostPlatform.isDarwin then ''
              # Gate: any failure is fatal on darwin
              if grep -q '^not ok' "$result_dir"/*.txt; then
                echo "FAIL: not all tests passed" >&2
                exit 1
              fi
              '' else ''
              # Linux: report only (VM tests are authoritative)
              ''}
            fi

            runHook postCheck
          '';

          installPhase = ''
            runHook preInstall
            install -Dm755 ${buildDir}/bin/ksh "$out/bin/ksh"
            install -Dm755 ${buildDir}/bin/shcomp "$out/bin/shcomp"
            install -Dm755 ${buildDir}/bin/pty "$out/bin/pty"

            # Export build artifacts for inspection
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
            cp -r ${buildDir}/test "$out/build-artifacts/" 2>/dev/null || true

            runHook postInstall
          '';

          passthru.shellPath = "/bin/ksh";

          meta = with lib; {
            description = "ksh26 — the KornShell, redesigned";
            homepage = "https://github.com/lane-core/ksh26";
            license = licenses.epl20;
            platforms = platforms.unix;
            mainProgram = "ksh";
          };
        };
    in
    {
      _module.args.mkKsh = mkKsh;
      _module.args.hostType = hostType;

      packages = {
        default = mkKsh { };
        checked = mkKsh { doCheck = true; };
        build-debug = mkKsh {
          variant = "-debug";
          configureFlags = [ "--debug" ];
        };
        build-asan = mkKsh {
          variant = "-asan";
          configureFlags = [ "--asan" ];
        };
        checked-asan = mkKsh {
          variant = "-asan";
          configureFlags = [ "--asan" ];
          doCheck = true;
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
            dontConfigure = true;
            buildPhase = ''
              mkdir -p ${buildDir}/bin
              $CC -o ${buildDir}/bin/samu src/cmd/INIT/samu/*.c
              _Msh_DEFPATH="$PATH" sh configure.sh --debug
              ./${buildDir}/bin/samu -f ${buildDir}/build.ninja
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

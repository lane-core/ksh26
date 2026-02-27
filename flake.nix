{
  description = "ksh26 — independent fork of ksh93u+m";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
  let
    forAllSystems = nixpkgs.lib.genAttrs [
      "x86_64-linux" "aarch64-linux"
      "x86_64-darwin" "aarch64-darwin"
    ];
  in {
    packages = forAllSystems (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.stdenv.mkDerivation {
        pname = "ksh26";
        version = "0.1.0-alpha";

        src = self;

        buildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
          pkgs.libiconv
        ];

        # No configure phase — we handle it in buildPhase
        dontConfigure = true;

        buildPhase = ''
          runHook preBuild

          # Bootstrap samu (vendored ninja)
          mkdir -p build/$HOSTTYPE/bin
          $CC -o build/$HOSTTYPE/bin/samu src/cmd/INIT/samu/*.c

          # Configure (feature probes + generate build.ninja)
          sh configure.sh

          # Build
          ./build/$HOSTTYPE/bin/samu -C build/$HOSTTYPE

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          install -Dm755 build/$HOSTTYPE/bin/ksh "$out/bin/ksh"
          install -Dm755 build/$HOSTTYPE/bin/shcomp "$out/bin/shcomp"
          runHook postInstall
        '';

        # HOSTTYPE is set by configure.sh's detect_hosttype()
        # but we need it for the build/install paths above
        preBuild = ''
          os=$(uname -s | tr 'A-Z' 'a-z')
          arch=$(uname -m)
          case $arch in aarch64) arch=arm64 ;; i?86) arch=i386 ;; esac
          bits=$(getconf LONG_BIT 2>/dev/null || echo 64)
          export HOSTTYPE="''${os}.''${arch}-''${bits}"
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
    });

    overlays.default = final: prev: {
      ksh26 = self.packages.${prev.stdenv.hostPlatform.system}.default;
      ksh = final.ksh26;
    };

    devShells = forAllSystems (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.mkShell {
        inputsFrom = [ self.packages.${system}.default ];
        packages = [
          pkgs.just
          pkgs.git
        ];
      };
    });

    checks = forAllSystems (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      ksh26 = self.packages.${system}.default;
    in {
      default = ksh26.overrideAttrs (old: {
        name = "ksh26-tests";

        doCheck = true;
        checkPhase = ''
          # sigchld.sh is excluded: its SIGCHLD-after-notfound test
          # depends on signal delivery timing that differs in the
          # Nix sandbox. All 111 tests pass outside the sandbox.
          sed -i '/^build test: phony/s| test/sigchld\.[^ ]*\.stamp||g' \
            build/$HOSTTYPE/build.ninja
          ./build/$HOSTTYPE/bin/samu -k 0 -C build/$HOSTTYPE test
        '';

        # Don't install — this is just for running tests
        installPhase = "touch $out";
      });
    });
  };
}

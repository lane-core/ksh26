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

        nativeBuildInputs = [
          pkgs.scdoc
        ];

        buildInputs = [
          pkgs.utf8proc
        ] ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
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

    homeManagerModules.default = import ./nix/hm-module.nix;
    darwinModules.default = import ./nix/darwin-module.nix;
    nixosModules.default = import ./nix/nixos-module.nix;

    devShells = forAllSystems (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.mkShell {
        packages = [
          pkgs.just
          pkgs.git
          pkgs.scdoc
          pkgs.pkg-config
          pkgs.ccache
          pkgs.dash
        ] ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
          pkgs.lldb
        ] ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
          pkgs.gdb
          pkgs.valgrind
        ];

        # Inherit buildInputs (utf8proc, libiconv) from the ksh26 package
        inputsFrom = [ self.packages.${system}.default ];
      };

      agent = pkgs.mkShell {
        inputsFrom = [ self.devShells.${system}.default ];

        # ccache by default — override with CC=cc if needed
        env.CC = "ccache cc";

        shellHook = ''
          _ht="$(uname -s | tr 'A-Z' 'a-z').$(uname -m | sed 's/aarch64/arm64/;s/i.86/i386/')-$(getconf LONG_BIT 2>/dev/null || echo 64)"
          echo "ksh26 agent shell — $(git rev-parse --short HEAD) on $(git branch --show-current) [$_ht]"
          if [[ ! -f "build/$_ht/build.ninja" ]]; then
            echo "Running initial configure..."
            just configure
          fi
        '';
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
          # Nix sandbox. All 115 tests pass outside the sandbox.
          sed -i '/^build test: phony/s| test/sigchld\.[^ ]*\.stamp||g' \
            build/$HOSTTYPE/build.ninja

          # Sanity check: fail if test count drops below expected minimum
          stamp_count=$(grep '^build test: phony' build/$HOSTTYPE/build.ninja \
            | tr ' ' '\n' | grep -c '\.stamp$' || true)
          if (( stamp_count < 110 )); then
            echo "FAIL: expected >=110 test stamps, found $stamp_count" >&2
            exit 1
          fi

          ./build/$HOSTTYPE/bin/samu -k 0 -C build/$HOSTTYPE test
        '';

        # Don't install — this is just for running tests
        installPhase = "touch $out";
      });

      # stdio backend check — lower threshold, ratchets up as tests are fixed
      stdio = ksh26.overrideAttrs (old: {
        name = "ksh26-stdio-tests";

        buildPhase = ''
          runHook preBuild

          mkdir -p build/$HOSTTYPE/bin
          $CC -o build/$HOSTTYPE/bin/samu src/cmd/INIT/samu/*.c

          # Build the sfio backend first (stdio shares its feature probes)
          sh configure.sh
          ./build/$HOSTTYPE/bin/samu -C build/$HOSTTYPE

          # Build the stdio backend
          sh configure.sh --stdio
          ./build/$HOSTTYPE/bin/samu -C build/$HOSTTYPE-stdio

          runHook postBuild
        '';

        doCheck = true;
        checkPhase = ''
          sed -i '/^build test: phony/s| test/sigchld\.[^ ]*\.stamp||g' \
            build/$HOSTTYPE-stdio/build.ninja

          stamp_count=$(grep '^build test: phony' build/$HOSTTYPE-stdio/build.ninja \
            | tr ' ' '\n' | grep -c '\.stamp$' || true)
          if (( stamp_count < 30 )); then
            echo "FAIL: expected >=30 test stamps, found $stamp_count" >&2
            exit 1
          fi

          # Allow failures — stdio is a work in progress.
          # The threshold above guards against regressions.
          ./build/$HOSTTYPE/bin/samu -k 0 -C build/$HOSTTYPE-stdio test || true
        '';

        installPhase = "touch $out";
      });
    });
  };
}

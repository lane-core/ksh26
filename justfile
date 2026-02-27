# ksh26 build system porcelain
#
# Three layers:
#   just       — user-facing recipes (this file)
#   configure  — ksh script that probes platform + emits build.ninja
#   samu       — vendored ninja implementation, executes build.ninja
#
# Usage: just build | just test | just clean | just install

HOSTTYPE := env("HOSTTYPE", `bin/package host type`)
BUILDDIR := "build" / HOSTTYPE
SAMU := BUILDDIR / "bin" / "samu"

# Build ksh26 (default recipe)
build: bootstrap
    @test -f {{BUILDDIR}}/build.ninja \
        || ksh configure.ksh
    {{SAMU}} -C {{BUILDDIR}}

# Bootstrap just the build tool
bootstrap:
    @mkdir -p {{BUILDDIR}}/bin
    @test -x {{SAMU}} \
        || cc -o {{SAMU}} src/cmd/INIT/samu/*.c

# (Re)run feature detection and generate build.ninja
configure: bootstrap
    ksh configure.ksh

# Run all regression tests in parallel via samu
# -k 0 = keep going on failure so all tests run
test: build
    {{SAMU}} -k 0 -C {{BUILDDIR}} test

# Run tests sequentially via legacy shtests harness
test-serial: build
    HOSTTYPE={{HOSTTYPE}} \
    PACKAGEROOT="$PWD" \
    INSTALLROOT="$PWD/{{BUILDDIR}}" \
    LD_LIBRARY_PATH="" \
    SHELL={{BUILDDIR}}/bin/ksh \
    KSH={{BUILDDIR}}/bin/ksh \
    bin/shtests

# Remove build artifacts for this host
clean:
    rm -rf {{BUILDDIR}}

# Remove all build artifacts
cleanall:
    rm -rf build

# Install ksh and shcomp
install prefix="/usr/local": build
    install -d {{prefix}}/bin
    install -m 755 {{BUILDDIR}}/bin/ksh {{prefix}}/bin/ksh
    install -m 755 {{BUILDDIR}}/bin/shcomp {{prefix}}/bin/shcomp

# ksh26 build system porcelain
#
# Three layers:
#   just       — user-facing recipes (this file)
#   configure  — ksh script that probes platform + emits build.ninja
#   samu       — vendored ninja implementation, executes build.ninja
#
# Usage: just build | just test | just clean | just install
#        just build-stdio | just test-stdio | just clean-stdio
#
# Override: CC=clang just build
#          CC="ccache cc" just build    (compiler caching)

HOSTTYPE := env("HOSTTYPE", `uname -s | tr 'A-Z' 'a-z' | tr -d '\n'; printf '.'; uname -m | sed 's/aarch64/arm64/;s/i.86/i386/' | tr -d '\n'; printf -- '-'; getconf LONG_BIT 2>/dev/null || echo 64`)
BUILDDIR := "build" / HOSTTYPE
STDIODIR := "build" / (HOSTTYPE + "-stdio")
SAMU := BUILDDIR / "bin" / "samu"

# Build ksh26 (default recipe)
build: bootstrap
    @test -f {{BUILDDIR}}/build.ninja \
        -a {{BUILDDIR}}/build.ninja -nt configure.sh \
        || sh configure.sh
    {{SAMU}} -C {{BUILDDIR}}

# Bootstrap just the build tool
bootstrap:
    @mkdir -p {{BUILDDIR}}/bin
    @test -x {{SAMU}} \
        || cc -o {{SAMU}} src/cmd/INIT/samu/*.c

# (Re)run feature detection and generate build.ninja
# Probes are cached — only stale probes rerun (~5s when nothing changed)
configure: bootstrap
    sh configure.sh

# Force all probes to rerun (ignores cache)
reconfigure: bootstrap
    sh configure.sh --force

# Run all regression tests in parallel via samu
# -k 0 = keep going on failure so all tests run
test: build
    {{SAMU}} -k 0 -C {{BUILDDIR}} test

# Run a single test: just test-one basic
test-one name locale="C": build
    {{SAMU}} -C {{BUILDDIR}} test/{{name}}.{{locale}}.stamp

# Pass arbitrary args to samu
samu *args: bootstrap
    {{SAMU}} -C {{BUILDDIR}} {{args}}

# Show the most recent test failure logs
log:
    @find {{BUILDDIR}}/test -name '*.log' 2>/dev/null | xargs ls -t 2>/dev/null | head -5 | xargs cat 2>/dev/null || echo "No test logs found."

# Build man pages from scdoc sources (no C build dependency)
doc:
    #!/bin/sh
    set -e
    SCDOC=""
    if command -v scdoc >/dev/null 2>&1; then
        SCDOC=scdoc
    elif [ -x {{BUILDDIR}}/deps/scdoc/scdoc ]; then
        SCDOC={{BUILDDIR}}/deps/scdoc/scdoc
    else
        printf '%s\n' "scdoc not found, fetching ..."
        mkdir -p {{BUILDDIR}}/deps
        git clone --depth 1 --branch 1.11.3 \
            https://github.com/ddevault/scdoc.git \
            {{BUILDDIR}}/deps/scdoc 2>/dev/null
        make -C {{BUILDDIR}}/deps/scdoc
        SCDOC={{BUILDDIR}}/deps/scdoc/scdoc
    fi
    mkdir -p {{BUILDDIR}}/man/man1 {{BUILDDIR}}/man/man3
    for scd in doc/*.scd; do
        [ -f "$scd" ] || continue
        base=$(basename "$scd" .scd)
        section=${base##*.}
        "$SCDOC" < "$scd" > "{{BUILDDIR}}/man/man${section}/${base}"
        printf '%s\n' "  DOC $base"
    done

# Generate compile_commands.json for clangd/LSP
# Uses samu's built-in compdb — no build or bear needed
compile-commands: bootstrap
    @test -f {{BUILDDIR}}/build.ninja \
        -a {{BUILDDIR}}/build.ninja -nt configure.sh \
        || sh configure.sh
    @{{SAMU}} -C {{BUILDDIR}} -t compdb cc > compile_commands.json
    @printf '%s\n' "wrote compile_commands.json ($(grep -c '"file"' compile_commands.json) entries)"

# Remove build artifacts: just clean [stage]
# Stages: test, obj, lib, bin, all (default: all)
clean stage="all":
    #!/bin/sh
    case "{{stage}}" in
    test) rm -rf "{{BUILDDIR}}/test" ;;
    obj)  rm -rf "{{BUILDDIR}}/obj" ;;
    lib)  rm -rf "{{BUILDDIR}}/lib" ;;
    bin)  rm -f "{{BUILDDIR}}/bin/ksh" "{{BUILDDIR}}/bin/shcomp" ;;
    all)  rm -rf "{{BUILDDIR}}" ;;
    *)    printf 'unknown stage: %s\nstages: test obj lib bin all\n' "{{stage}}" >&2; exit 1 ;;
    esac

# Remove all build artifacts (every host)
cleanall:
    rm -rf build

# Install ksh and shcomp
install prefix="/usr/local": build
    install -d {{prefix}}/bin
    install -m 755 {{BUILDDIR}}/bin/ksh {{prefix}}/bin/ksh
    install -m 755 {{BUILDDIR}}/bin/shcomp {{prefix}}/bin/shcomp

# ── stdio backend (KSH_IO_SFIO=0) ────────────────────────────────

# Build ksh26 with stdio backend
build-stdio: bootstrap
    @test -f {{STDIODIR}}/build.ninja \
        -a {{STDIODIR}}/build.ninja -nt configure.sh \
        || sh configure.sh --stdio
    {{SAMU}} -C {{STDIODIR}}

# Run tests against the stdio build
test-stdio: build-stdio
    {{SAMU}} -k 0 -C {{STDIODIR}} test

# Remove stdio build artifacts
clean-stdio:
    rm -rf {{STDIODIR}}

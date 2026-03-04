# ksh26 build system porcelain
#
# Two paths:
#   Validation — nix-backed, content-addressed (just build, just test)
#   Iteration  — local samu, devshell-only (just test-one, just debug)
#
# Validation recipes call nix directly — no `nix develop` wrapper needed.
# Iteration recipes require the devshell toolchain.
#
# Usage: just build | just test | just clean
#        just errors | just failures | just log
#        just check | just check-asan | just check-all
#
# Override (iteration only): CC=clang just _dev-build

HOSTTYPE := env("HOSTTYPE", `uname -s | tr 'A-Z' 'a-z' | tr -d '\n'; printf '.'; uname -m | sed 's/aarch64/arm64/;s/i.86/i386/' | tr -d '\n'; printf -- '-'; getconf LONG_BIT 2>/dev/null || echo 64`)
BUILDDIR := "build" / HOSTTYPE
SAMU := BUILDDIR / "bin" / "samu"

# ── Validation (nix-backed, content-addressed) ───────────────
# Any source change → derivation hash changes → nix rebuilds.
# No changes → ~2-5s cache hit. No stale builds possible.

# Build ksh26 (content-addressed — any source change triggers rebuild)
build:
    nix build .#build --print-build-logs

# Run all regression tests (content-addressed)
test:
    nix build .#checks."$(nix eval --raw nixpkgs#system)".default --print-build-logs

# Build with debug flags
build-debug:
    nix build .#build-debug --print-build-logs

# Build with sanitizers
build-asan:
    nix build .#build-asan --print-build-logs

# Run tests with sanitizers
test-asan:
    nix build .#checks."$(nix eval --raw nixpkgs#system)".asan --print-build-logs

# ── CI checks (nix sandbox) ─────────────────────────────────

# Run the same checks CI runs (build + full test suite in nix sandbox)
check:
    nix build .#checks."$(nix eval --raw nixpkgs#system)".default --print-build-logs

# Run asan checks in nix sandbox
check-asan:
    nix build .#checks."$(nix eval --raw nixpkgs#system)".asan --print-build-logs

# Run all CI checks
check-all:
    nix flake check --print-build-logs

# ── Iteration (local samu, devshell-only) ─────────────────────
# These use timestamp-based caching for speed. Not for validation —
# use `just build` / `just test` for that.

# Bootstrap just the build tool
bootstrap:
    @mkdir -p {{BUILDDIR}}/bin
    @test -x {{SAMU}} \
        || cc -o {{SAMU}} src/cmd/INIT/samu/*.c

# Private: local build for interactive recipes
[private]
_dev-build: bootstrap
    #!/usr/bin/env bash
    set -euo pipefail
    dir="{{BUILDDIR}}"
    if [[ ! -f "$dir/build.ninja" || configure.sh -nt "$dir/build.ninja" ]]; then
        sh configure.sh
    fi
    mkdir -p "$dir/log"
    {{SAMU}} -C "$dir" 2>&1 | tee "$dir/log/build.log"

# (Re)run feature detection and generate build.ninja
configure: bootstrap
    sh configure.sh

# Force all probes to rerun (ignores cache)
reconfigure: bootstrap
    sh configure.sh --force

# Run a single test: just test-one basic
test-one name locale="C": _dev-build
    {{SAMU}} -C {{BUILDDIR}} test/{{name}}.{{locale}}.stamp

# Run a test N times to detect flakiness
test-repeat name n="10" locale="C": _dev-build
    #!/usr/bin/env bash
    set -uo pipefail
    pass=0 fail=0
    for i in $(seq 1 {{n}}); do
        rm -f "{{BUILDDIR}}/test/{{name}}.{{locale}}.stamp"
        if {{SAMU}} -C "{{BUILDDIR}}" "test/{{name}}.{{locale}}.stamp" >/dev/null 2>&1; then
            ((pass++))
        else
            ((fail++))
        fi
    done
    printf '%s.%s: %d/%d pass' "{{name}}" "{{locale}}" "$pass" "{{n}}"
    (( fail > 0 )) && printf ' (FLAKY)\n' && exit 1 || printf ' (STABLE)\n'

# Run a test under the debugger
debug name locale="C": _dev-build
    #!/bin/sh
    export SHELL="{{BUILDDIR}}/bin/ksh"
    export SHCOMP="{{BUILDDIR}}/bin/shcomp"
    export SHTESTS_COMMON="$PWD/tests/shell/_common"
    export ENV=/./dev/null
    . "{{BUILDDIR}}/test-env.sh"
    case "{{locale}}" in
    C)       unset LANG LC_ALL 2>/dev/null ;;
    C.UTF-8) export LANG=C.UTF-8; unset LC_ALL 2>/dev/null ;;
    esac
    case "$(uname -s)" in
    Darwin) lldb -- "{{BUILDDIR}}/bin/ksh" "tests/shell/{{name}}.sh" ;;
    *)      gdb --args "{{BUILDDIR}}/bin/ksh" "tests/shell/{{name}}.sh" ;;
    esac

# Run iffe regression tests
test-iffe:
    sh tests/infra/iffe.sh

# Pass arbitrary args to samu
samu *args: bootstrap
    {{SAMU}} -C {{BUILDDIR}} {{args}}

# ── Diagnostics ──────────────────────────────────────────────

# Show errors from last build
errors dir=BUILDDIR:
    @grep -iE 'error[: ]|undefined|fatal' "{{dir}}/log/build.log" 2>/dev/null \
        || echo "No errors (or no build log). Run: just build"

# Show warnings from last build
warnings dir=BUILDDIR:
    @grep -i 'warning:' "{{dir}}/log/build.log" 2>/dev/null \
        || echo "No warnings (or no build log)."

# Show failed tests with their individual logs
failures dir=BUILDDIR:
    #!/bin/sh
    summary="{{dir}}/test/summary.log"
    # Fall back to previous summary if current was cleared by a no-op test run
    if [ ! -f "$summary" ] && [ -f "{{dir}}/test/summary.prev" ]; then
        summary="{{dir}}/test/summary.prev"
    fi
    if [ ! -f "$summary" ]; then
        echo "No test summary. Run: just test"; exit 1
    fi
    non_pass=$(grep '^not ok' "$summary" || true)
    if [ -n "$non_pass" ]; then
        printf '%s\n' "$non_pass" | sort
    else
        echo "(all pass)"
    fi
    for f in $(find "{{dir}}/test" -name '*.stamp.log' 2>/dev/null | sort); do
        printf '\n== %s ==\n' "$(basename "$f" .stamp.log)"
        cat "$f"
    done

# Show build or test logs: just log [build|test] [name]
log what="all" name="":
    #!/bin/sh
    dir="{{BUILDDIR}}"
    case "{{what}}" in
    build)
        cat "$dir/log/build.log" 2>/dev/null || echo "No build log." ;;
    test)
        if [ -n "{{name}}" ]; then
            f=$(find "$dir/test" -name '{{name}}*.stamp.log' 2>/dev/null | head -1)
            [ -n "$f" ] && cat "$f" || echo "No log for {{name}}"
        else
            just failures "$dir"
        fi ;;
    *)
        [ -f "$dir/log/build.log" ] && { printf '=== Build (last 20) ===\n'; tail -20 "$dir/log/build.log"; }
        if [ -f "$dir/test/summary.log" ] || [ -f "$dir/test/summary.prev" ]; then
            printf '\n=== Tests ===\n'; just failures "$dir"
        fi ;;
    esac

# ── Code tools ───────────────────────────────────────────────

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
    for scd in man/*.scd; do
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

# ── Clean ────────────────────────────────────────────────────

# Remove build artifacts: just clean [stage]
# Stages: test, obj, lib, bin, log, all (default: all)
clean stage="all":
    #!/bin/sh
    case "{{stage}}" in
    test) rm -rf "{{BUILDDIR}}/test" ;;
    obj)  rm -rf "{{BUILDDIR}}/obj" ;;
    lib)  rm -rf "{{BUILDDIR}}/lib" ;;
    bin)  rm -f "{{BUILDDIR}}/bin/ksh" "{{BUILDDIR}}/bin/shcomp" ;;
    log)  rm -rf "{{BUILDDIR}}/log" ;;
    all)  rm -rf "{{BUILDDIR}}" ;;
    *)    printf 'unknown stage: %s\nstages: test obj lib bin log all\n' "{{stage}}" >&2; exit 1 ;;
    esac

# Remove debug build artifacts
clean-debug:
    rm -rf build/{{HOSTTYPE}}-debug

# Remove asan build artifacts
clean-asan:
    rm -rf build/{{HOSTTYPE}}-asan

# Remove all build artifacts (every host)
cleanall:
    rm -rf build

# Install ksh and shcomp (from nix build output)
install prefix="/usr/local": build
    install -d {{prefix}}/bin
    install -m 755 result/bin/ksh {{prefix}}/bin/ksh
    install -m 755 result/bin/shcomp {{prefix}}/bin/shcomp

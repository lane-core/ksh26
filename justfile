# ksh26 build system porcelain
#
# Usage:
#   just build [darwin|linux] [--asan] [--debug]
#   just test  [darwin|linux] [--asan] [--one NAME] [--repeat NAME] [--verbose]
#   just test  --category fast # run a test category (local samu)
#   just test  --debug NAME   # run single test under lldb/gdb (local only)
#
# Platform is auto-detected from uname. Explicit platform triggers
# cross-build when different from host (e.g. `just test linux` on darwin
# uses the linux builder).

set shell := ["bash", "-euo", "pipefail", "-c"]

HOSTTYPE := env("HOSTTYPE", shell("echo $(uname -s | tr A-Z a-z).$(uname -m | sed 's/arm64/arm64-64/;s/x86_64/x86_64-64/;s/aarch64/aarch64-64/')"))
BUILDDIR := "build" / HOSTTYPE
SAMU_SRC := "src/cmd/INIT/samu"
SAMU     := BUILDDIR / "bin/samu"
NINJA    := BUILDDIR / "build.ninja"
TESTS    := "src/cmd/ksh26/tests"

# ── Shared helpers ──────────────────────────────────────────────
# Bash functions sourced by build/test dispatchers.

_helpers := '
_host() { uname -s | tr A-Z a-z; }
_arch() { uname -m | sed "s/arm64/aarch64/"; }
_nix_system() {
    local plat="${1:-$(_host)}"
    case "$plat" in
    darwin) echo "$(_arch)-darwin" ;;
    linux)
        if [ "$(_host)" = darwin ]; then
            echo "aarch64-linux"
        else
            echo "$(_arch)-linux"
        fi ;;
    *) echo "error: unknown platform: $plat" >&2; return 1 ;;
    esac
}
_is_cross() {
    [ "${1:-$(_host)}" != "$(_host)" ]
}
_require_builder() {
    local plat="$1"
    if [ "$(_host)" = darwin ] && [ "$plat" = linux ]; then
        grep -q linux /etc/nix/machines 2>/dev/null \
            || { echo "error: no linux builder in /etc/nix/machines" >&2; return 1; }
    else
        echo "error: no $plat builder from $(_host)" >&2; return 1
    fi
}
_nix_build() {
    nix build ".#$1" --print-build-logs "${@:2}"
}
'

# ── Build ───────────────────────────────────────────────────────

# Build ksh26: just build [darwin|linux] [--asan] [--debug]
build *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    eval '{{ _helpers }}'
    platform= variant=
    for arg in {{ ARGS }}; do
        case "$arg" in
        darwin|linux) platform="$arg" ;;
        --asan)       variant=asan ;;
        --debug)      variant=debug ;;
        *) echo "error: unknown argument: $arg" >&2; exit 1 ;;
        esac
    done
    : "${platform:=$(_host)}"
    if _is_cross "$platform"; then _require_builder "$platform"; fi
    sys=$(_nix_system "$platform")
    case "$variant" in
    asan)  attr="packages.${sys}.build-asan" ;;
    debug) attr="packages.${sys}.build-debug" ;;
    *)     attr="packages.${sys}.default" ;;
    esac
    if _is_cross "$platform"; then
        _nix_build "$attr" --out-link "result-${platform}"
    else
        _nix_build "$attr"
    fi

# ── Test ────────────────────────────────────────────────────────

# Test ksh26: just test [darwin|linux] [--asan] [--one NAME] [--debug NAME] [--repeat NAME] [--verbose]
test *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    eval '{{ _helpers }}'
    platform= variant= one= debug_test= repeat_test= verbose= category=
    for arg in {{ ARGS }}; do
        case "$arg" in
        darwin|linux) platform="$arg" ;;
        --asan)       variant=asan ;;
        --verbose)    verbose=1 ;;
        --one)        one=_next ;;
        --debug)      debug_test=_next ;;
        --repeat)     repeat_test=_next ;;
        --category)   category=_next ;;
        *)
            if [ "$one" = _next ]; then one="$arg"
            elif [ "$debug_test" = _next ]; then debug_test="$arg"
            elif [ "$repeat_test" = _next ]; then repeat_test="$arg"
            elif [ "$category" = _next ]; then category="$arg"
            else echo "error: unknown argument: $arg" >&2; exit 1; fi ;;
        esac
    done
    # Validate flags that require a following argument
    if [ "$one" = _next ] || [ "$debug_test" = _next ] || [ "$repeat_test" = _next ] || [ "$category" = _next ]; then
        echo "error: --one/--debug/--repeat/--category requires an argument" >&2; exit 1
    fi
    : "${platform:=$(_host)}"
    if _is_cross "$platform"; then _require_builder "$platform"; fi
    sys=$(_nix_system "$platform")
    # Single test — local samu (native only)
    if [ -n "$one" ]; then
        if _is_cross "$platform"; then
            echo "error: --one requires native platform" >&2; exit 1
        fi
        just _dev-build
        "{{ BUILDDIR }}/bin/samu" -C "{{ BUILDDIR }}" "test/${one}.C.stamp"
        exit $?
    fi
    # Debug — launch debugger (native only)
    if [ -n "$debug_test" ]; then
        just debug "$debug_test"
        exit $?
    fi
    # Repeat — flakiness detection (native only)
    if [ -n "$repeat_test" ]; then
        just _test-repeat "$repeat_test"
        exit $?
    fi
    # Category — run a subset of tests
    if [ -n "$category" ]; then
        if _is_cross "$platform"; then
            # Cross: use nix check for the category
            _nix_build "checks.${sys}.${category}"
        else
            # Native: local samu
            just _dev-build
            "{{ BUILDDIR }}/bin/samu" -C "{{ BUILDDIR }}" "test-${category}"
        fi
        exit $?
    fi
    # Full suite via nix
    attr="checks.${sys}.${variant:-default}"
    _nix_build "$attr"
    if [ -n "$verbose" ]; then
        echo "=== Build Artifacts ==="
        for f in result/build-artifacts/log/*; do
            [ -f "$f" ] && echo "--- $(basename "$f") ---" && cat "$f"
        done 2>/dev/null || echo "(no artifacts — build may have failed)"
    fi

# All nix checks (tests + formatting, all platforms)
check-all:
    nix flake check --print-build-logs

# ── Iteration (local samu, devshell-only) ─────────────────────
# These use timestamp-based caching for speed. Not for validation.

# Bootstrap samu from vendored source
[private]
bootstrap:
    @mkdir -p "{{ BUILDDIR }}/bin"
    @if [[ ! -x "{{ SAMU }}" ]]; then \
        cc -o "{{ SAMU }}" {{ SAMU_SRC }}/*.c; \
        echo "samu bootstrapped → {{ SAMU }}"; \
    fi

# Private: local build for interactive recipes
[private]
_dev-build: bootstrap
    #!/usr/bin/env bash
    set -euo pipefail
    dir="{{ BUILDDIR }}"
    if [[ ! -f "$dir/build.ninja" || configure.sh -nt "$dir/build.ninja" ]]; then
        sh configure.sh
    fi
    mkdir -p "$dir/log"
    {{ SAMU }} -C "$dir" 2>&1 | tee "$dir/log/build.log"

# Run configure.sh to generate build.ninja
configure: bootstrap
    @CC="${CC:-cc}" ./configure.sh

# Force full reconfigure (clear cache)
reconfigure: bootstrap
    @CC="${CC:-cc}" ./configure.sh --force

# Private: repeat test N times
[private]
_test-repeat NAME N="10" LOCALE="C": _dev-build
    #!/usr/bin/env bash
    set -uo pipefail
    pass=0 fail=0
    for i in $(seq 1 {{ N }}); do
        rm -f "{{ BUILDDIR }}/test/{{ NAME }}.{{ LOCALE }}.stamp"
        if {{ SAMU }} -C "{{ BUILDDIR }}" "test/{{ NAME }}.{{ LOCALE }}.stamp" >/dev/null 2>&1; then
            ((pass++))
        else
            ((fail++))
        fi
    done
    printf '%s.%s: %d/%d pass' "{{ NAME }}" "{{ LOCALE }}" "$pass" "{{ N }}"
    (( fail > 0 )) && printf ' (FLAKY)\n' && exit 1 || printf ' (STABLE)\n'

# Debug a test under lldb/gdb
debug NAME LOCALE="C": _dev-build
    #!/bin/sh
    export SHELL="{{ BUILDDIR }}/bin/ksh"
    export SHCOMP="{{ BUILDDIR }}/bin/shcomp"
    export SHTESTS_COMMON="$PWD/{{ TESTS }}/_common"
    export ENV=/./dev/null
    . "{{ BUILDDIR }}/test-env.sh"
    case "{{ LOCALE }}" in
    C)       unset LANG LC_ALL 2>/dev/null ;;
    C.UTF-8) export LANG=C.UTF-8; unset LC_ALL 2>/dev/null ;;
    esac
    case "$(uname -s)" in
    Darwin) lldb -- "{{ BUILDDIR }}/bin/ksh" "{{ TESTS }}/{{ NAME }}.sh" ;;
    *)      gdb --args "{{ BUILDDIR }}/bin/ksh" "{{ TESTS }}/{{ NAME }}.sh" ;;
    esac

# Pass arbitrary args to samu
samu *ARGS: bootstrap
    {{ SAMU }} -C {{ BUILDDIR }} {{ ARGS }}

# Generate compile_commands.json for clangd/LSP
compile-commands: bootstrap
    @test -f {{ NINJA }} \
        && test {{ NINJA }} -nt configure.sh \
        || sh configure.sh
    @{{ SAMU }} -C {{ BUILDDIR }} -t compdb cc_ast cc_cmd cc_dll cc_ksh cc_pty > compile_commands.json
    @printf '%s\n' "wrote compile_commands.json ($(grep -c '"file"' compile_commands.json) entries)"

# ── Diagnostics ─────────────────────────────────────────────────

# Show build errors from log (no rebuild)
errors DIR=BUILDDIR:
    @grep -iE 'error[: ]|undefined|fatal' "{{ DIR }}/log/build.log" 2>/dev/null \
        || echo "No errors (or no build log). Run: just build"

# Show build warnings from log
warnings DIR=BUILDDIR:
    @grep -i 'warning:' "{{ DIR }}/log/build.log" 2>/dev/null \
        || echo "No warnings (or no build log)."

# Show failed tests with their individual logs
failures DIR=BUILDDIR:
    #!/bin/sh
    result_dir="{{ DIR }}/test/results"
    if [ -d "$result_dir" ] && ls "$result_dir"/*.txt >/dev/null 2>&1; then
        non_pass=$(grep -l '^not ok' "$result_dir"/*.txt 2>/dev/null || true)
        if [ -n "$non_pass" ]; then
            for f in $non_pass; do cat "$f"; done | sort
        else
            echo "(all pass)"
        fi
        for f in $(find "{{ DIR }}/test" -name '*.stamp.log' 2>/dev/null | sort); do
            printf '\n== %s ==\n' "$(basename "$f" .stamp.log)"
            cat "$f"
        done
    else
        echo "No test results. Run: just test"
    fi

# Show build or test logs: just log [build|test] [name]
log KIND="all" NAME="":
    #!/bin/sh
    dir="{{ BUILDDIR }}"
    case "{{ KIND }}" in
    build)
        cat "$dir/log/build.log" 2>/dev/null || echo "No build log." ;;
    test)
        if [ -n "{{ NAME }}" ]; then
            found=false
            for f in "$dir"/test/"{{ NAME }}"*.stamp.log; do
                [ -f "$f" ] || continue
                echo "=== $(basename "$f" .stamp.log) ==="
                cat "$f"
                echo
                found=true
            done
            $found || echo "No log for {{ NAME }}"
        else
            just failures "$dir"
        fi ;;
    *)
        [ -f "$dir/log/build.log" ] && { printf '=== Build (last 20) ===\n'; tail -20 "$dir/log/build.log"; }
        result_dir="$dir/test/results"
        if [ -d "$result_dir" ] && ls "$result_dir"/*.txt >/dev/null 2>&1; then
            printf '\n=== Tests ===\n'; just failures "$dir"
        fi ;;
    esac

# Comprehensive test failure diagnosis
diagnose NAME LOCALE="C": _dev-build
    #!/bin/sh
    set -eu
    dir="{{ BUILDDIR }}"
    test_name="{{ NAME }}"
    mode="{{ LOCALE }}"
    stamp="$dir/test/${test_name}.${mode}.stamp"
    log="${stamp}.log"
    echo "=== ksh26 Test Failure Diagnosis ==="
    echo "Test: $test_name (mode: $mode)"
    echo ""
    if [ ! -f "{{ TESTS }}/${test_name}.sh" ]; then
        echo "ERROR: Test file not found: {{ TESTS }}/${test_name}.sh"
        ls {{ TESTS }}/*.sh | sed 's|.*/||; s/\.sh$//' | column -c 80
        exit 1
    fi
    rm -f "$stamp"
    {{ SAMU }} -C "$dir" "test/${test_name}.${mode}.stamp" 2>&1 || true
    echo ""
    if [ -f "$stamp" ]; then
        echo "Result: PASSED"
    else
        echo "Result: FAILED"
        [ -f "$log" ] && cat "$log"
    fi

# ── Maintenance ─────────────────────────────────────────────────

# Clean build artifacts (default: all)
clean STAGE="all":
    #!/bin/sh
    case "{{ STAGE }}" in
    test) rm -rf "{{ BUILDDIR }}/test" ;;
    obj)  rm -rf "{{ BUILDDIR }}/obj" ;;
    lib)  rm -rf "{{ BUILDDIR }}/lib" ;;
    bin)  rm -f "{{ BUILDDIR }}/bin/ksh" "{{ BUILDDIR }}/bin/shcomp" ;;
    log)  rm -rf "{{ BUILDDIR }}/log" ;;
    all)  rm -rf "{{ BUILDDIR }}" ;;
    *)    printf 'unknown stage: %s\nstages: test obj lib bin log all\n' "{{ STAGE }}" >&2; exit 1 ;;
    esac

# Remove all build artifacts (every host)
cleanall:
    rm -rf build

# Format changed C files (staged + unstaged vs HEAD)
fmt:
    #!/bin/sh
    files=$(git diff --name-only --diff-filter=ACMR HEAD -- '*.c' '*.h' 2>/dev/null)
    files="$files $(git diff --name-only --diff-filter=ACMR --cached -- '*.c' '*.h' 2>/dev/null)"
    files=$(printf '%s\n' $files | sort -u | grep -v '^$' || true)
    if [ -z "$files" ]; then
        echo "no changed C files"
        exit 0
    fi
    echo "$files" | xargs clang-format -i
    echo "$files" | while read -r f; do printf '  FMT %s\n' "$f"; done

# Check formatting of changed C files (no modification)
fmt-check:
    #!/bin/sh
    files=$(git diff --name-only --diff-filter=ACMR HEAD -- '*.c' '*.h' 2>/dev/null)
    files="$files $(git diff --name-only --diff-filter=ACMR --cached -- '*.c' '*.h' 2>/dev/null)"
    files=$(printf '%s\n' $files | sort -u | grep -v '^$' || true)
    if [ -z "$files" ]; then
        echo "no changed C files"
        exit 0
    fi
    echo "$files" | xargs clang-format --dry-run --Werror

# Install ksh and shcomp (from nix build output)
install prefix="/usr/local": build
    install -d {{prefix}}/bin
    install -m 755 result/bin/ksh {{prefix}}/bin/ksh
    install -m 755 result/bin/shcomp {{prefix}}/bin/shcomp
    install -m 755 result/bin/pty {{prefix}}/bin/pty

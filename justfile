# ksh26 build system porcelain
#
# Two paths:
#   Validation — nix-backed, content-addressed (just build, just test)
#   Iteration  — local samu, devshell-only (just test-one, just debug)
#
# Validation recipes call nix directly — no `nix develop` wrapper needed.
# Iteration recipes require the devshell toolchain.

set shell := ["bash", "-euo", "pipefail", "-c"]

HOSTTYPE := env("HOSTTYPE", shell("echo $(uname -s | tr A-Z a-z).$(uname -m | sed 's/arm64/arm64-64/;s/x86_64/x86_64-64/;s/aarch64/aarch64-64/')"))
BUILDDIR := "build" / HOSTTYPE
SAMU_SRC := "src/cmd/INIT/samu"
SAMU     := BUILDDIR / "bin/samu"
NINJA    := BUILDDIR / "build.ninja"
TESTS    := "src/cmd/ksh26/tests"

# ── Validation (nix-backed, content-addressed) ───────────────
# Any source change → derivation hash changes → nix rebuilds.
# No changes → ~2-5s cache hit. No stale builds possible.

# Build ksh26 via nix (content-addressed, hermetic)
build:
    nix build .#default --print-build-logs

# Run full test suite via nix
test:
    nix build .#checked --print-build-logs

# Build with debug flags
build-debug:
    nix build .#build-debug --print-build-logs

# Build with sanitizers
build-asan:
    nix build .#build-asan

# Run tests with sanitizers
test-asan:
    nix build .#checked-asan --print-build-logs


# All nix checks (tests + formatting)
check-all:
    nix flake check --print-build-logs

# ── Cross-platform (linux from darwin, nix-backed) ────────────
# Requires a linux builder (nix-darwin linux-builder VM or remote).
# Setup: import ksh26.darwinModules.linux-builder in your darwin config.

# Private: verify a linux builder is reachable
[private]
_check-linux-builder:
    #!/usr/bin/env bash
    set -euo pipefail
    case "$(uname -s)" in
    Darwin) ;;
    *) echo "already on linux — use 'just build' / 'just test' directly" >&2; exit 1 ;;
    esac
    if grep -q 'linux' /etc/nix/machines 2>/dev/null; then
        exit 0
    fi
    echo "error: no linux builder found in /etc/nix/machines" >&2
    exit 1

# Build ksh26 for aarch64-linux from darwin
build-linux: _check-linux-builder
    nix build .#packages.aarch64-linux.default --print-build-logs --out-link result-linux

# Run full test suite on aarch64-linux from darwin
test-linux: _check-linux-builder
    nix build .#checks.aarch64-linux.default --print-build-logs

# Run tests with sanitizers on aarch64-linux from darwin
test-linux-asan: _check-linux-builder
    nix build .#checks.aarch64-linux.asan --print-build-logs

# Run full test suite inside a NixOS VM (authoritative linux test)
test-nixos-vm: _check-linux-builder
    nix build .#checks.aarch64-linux.nixos --print-build-logs


# Run advisory tests on aarch64-linux (nix sandbox — may flake)
test-linux-advisory-sandbox: _check-linux-builder
    nix build .#checks.aarch64-linux.advisory --print-build-logs

# ── Linux VM testing (SSH to builder VM, outside nix sandbox) ─
# Runs tests directly on the linux-builder VM, outside the nix
# sandbox. Requires: build-linux first, SSH key at ~/.ssh/linux-builder.

_linux-ssh := "ssh -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -i ~/.ssh/linux-builder -p 31022 builder@localhost"
_linux-scp := "scp -o IdentitiesOnly=yes -i ~/.ssh/linux-builder -P 31022"

# Sync built binary + tests to the linux builder
_linux-sync: build-linux
    #!/usr/bin/env bash
    set -euo pipefail
    {{ _linux-ssh }} 'rm -rf /tmp/ksh26-test && mkdir -p /tmp/ksh26-test/bin'
    {{ _linux-scp }} result-linux/bin/ksh result-linux/bin/shcomp builder@localhost:/tmp/ksh26-test/bin/
    {{ _linux-scp }} -r src/cmd/ksh26/tests builder@localhost:/tmp/ksh26-test/

# Run advisory tests on Linux VM (no sandbox)
test-linux-advisory: _linux-sync
    #!/usr/bin/env bash
    set -uo pipefail
    {{ _linux-ssh }} '
    export SHELL=/tmp/ksh26-test/bin/ksh
    export SHCOMP=/tmp/ksh26-test/bin/shcomp
    export SHTESTS_COMMON="/tmp/ksh26-test/tests/_common"
    export ENV=/./dev/null
    advisory="signal sigchld basic options"
    pass=0 fail=0 total=0
    for name in $advisory; do
      for locale in C C.UTF-8; do
        total=$((total + 1))
        case $locale in
        C)       unset LANG LC_ALL 2>/dev/null ;;
        C.UTF-8) export LANG=C.UTF-8; unset LC_ALL 2>/dev/null ;;
        esac
        export tmp=$(mktemp -d /tmp/ksh26-adv.XXXXXX)
        export HOME="$tmp"
        cd "$tmp"
        if timeout 60 "$SHELL" "/tmp/ksh26-test/tests/${name}.sh" >/dev/null 2>&1; then
          pass=$((pass + 1))
          printf "ok - %s.%s\n" "$name" "$locale"
        else
          fail=$((fail + 1))
          printf "FAIL - %s.%s\n" "$name" "$locale"
          timeout 60 "$SHELL" "/tmp/ksh26-test/tests/${name}.sh" 2>&1 | grep "FAIL:" | head -5
        fi
        cd /; rm -rf "$tmp"
      done
    done
    echo "---"
    printf "%d/%d advisory tests pass (virtual machine)\n" "$pass" "$total"
    [ "$fail" -eq 0 ]
    '

# Run a single test on real Linux hardware
test-linux-one NAME LOCALE="C": _linux-sync
    #!/usr/bin/env bash
    set -uo pipefail
    {{ _linux-ssh }} '
    export SHELL=/tmp/ksh26-test/bin/ksh
    export SHCOMP=/tmp/ksh26-test/bin/shcomp
    export SHTESTS_COMMON="/tmp/ksh26-test/tests/_common"
    export ENV=/./dev/null
    export tmp=$(mktemp -d /tmp/ksh26-one.XXXXXX)
    export HOME="$tmp"
    case "{{ LOCALE }}" in
    C)       unset LANG LC_ALL 2>/dev/null ;;
    C.UTF-8) export LANG=C.UTF-8; unset LC_ALL 2>/dev/null ;;
    esac
    cd "$tmp"
    timeout 120 "$SHELL" "/tmp/ksh26-test/tests/{{ NAME }}.sh" 2>&1
    rc=$?
    cd /; rm -rf "$tmp"
    exit $rc
    '

# Run full test suite on real Linux hardware
test-linux-real: _linux-sync
    #!/usr/bin/env bash
    set -uo pipefail
    {{ _linux-ssh }} '
    export SHELL=/tmp/ksh26-test/bin/ksh
    export SHCOMP=/tmp/ksh26-test/bin/shcomp
    export SHTESTS_COMMON="/tmp/ksh26-test/tests/_common"
    export ENV=/./dev/null
    tests=$(ls /tmp/ksh26-test/tests/*.sh | grep -v _common | sort)
    pass=0 fail=0 total=0
    for test_script in $tests; do
      name=$(basename "$test_script" .sh)
      for locale in C C.UTF-8; do
        total=$((total + 1))
        case $locale in
        C)       unset LANG LC_ALL 2>/dev/null ;;
        C.UTF-8) export LANG=C.UTF-8; unset LC_ALL 2>/dev/null ;;
        esac
        export tmp=$(mktemp -d /tmp/ksh26-full.XXXXXX)
        export HOME="$tmp"
        cd "$tmp"
        if timeout 120 "$SHELL" "$test_script" >/dev/null 2>&1; then
          pass=$((pass + 1))
          printf "ok - %s.%s\n" "$name" "$locale"
        else
          fail=$((fail + 1))
          printf "FAIL - %s.%s\n" "$name" "$locale"
          timeout 120 "$SHELL" "$test_script" 2>&1 | grep "FAIL:" | head -3
        fi
        cd /; rm -rf "$tmp"
      done
    done
    echo "---"
    printf "%d/%d tests pass (virtual machine)\n" "$pass" "$total"
    [ "$fail" -eq 0 ] || exit 1
    '

# ── Iteration (local samu, devshell-only) ─────────────────────
# These use timestamp-based caching for speed. Not for validation —
# use `just build` / `just test` for that.

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

# Run a single test: just test-one basic
test-one NAME LOCALE="C": _dev-build
    {{ SAMU }} -C {{ BUILDDIR }} test/{{ NAME }}.{{ LOCALE }}.stamp

# Run a test N times to detect flakiness
test-repeat NAME N="10" LOCALE="C": _dev-build
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

# Run advisory tests on virtual machine (not nix sandbox).
# These are gated out of `just test` due to sandbox timing jitter
# but must pass here to confirm correct functionality.
test-advisory: _dev-build
    #!/usr/bin/env bash
    set -uo pipefail
    advisory=(signal sigchld basic options)
    pass=0 fail=0 total=0
    for name in "${advisory[@]}"; do
        for locale in C C.UTF-8; do
            ((total++))
            rm -f "{{ BUILDDIR }}/test/${name}.${locale}.stamp"
            if {{ SAMU }} -j1 -C "{{ BUILDDIR }}" "test/${name}.${locale}.stamp" >/dev/null 2>&1; then
                ((pass++))
                printf 'ok - %s.%s\n' "$name" "$locale"
            else
                ((fail++))
                printf 'FAIL - %s.%s\n' "$name" "$locale"
                # show the failure details
                cat "{{ BUILDDIR }}/test/${name}.${locale}.stamp.log" 2>/dev/null | grep 'FAIL:' || true
            fi
        done
    done
    echo "---"
    printf '%d/%d advisory tests pass\n' "$pass" "$total"
    (( fail > 0 )) && exit 1 || exit 0

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

# Run iffe regression tests
test-iffe: _dev-build
    sh tests/infra/iffe.sh
    @echo "── sfio regression tests ──"
    cc -std=c23 -g -O0 \
        -I {{ BUILDDIR }}/feat/libast/std \
        -I {{ BUILDDIR }}/feat/libast \
        -I src/lib/libast/sfio \
        -I src/lib/libast/include \
        -o {{ BUILDDIR }}/bin/sfio_test \
        tests/infra/sfio/sfio_test.c \
        -L {{ BUILDDIR }}/lib -last -lcmd -last -liconv -lm
    {{ BUILDDIR }}/bin/sfio_test

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
# Per Immutable Test Sanctity (CLAUDE.md): investigates context deficiencies, not test logic
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
    echo "Stamp: $stamp"
    echo ""

    # Check if test exists
    if [ ! -f "{{ TESTS }}/${test_name}.sh" ]; then
        echo "ERROR: Test file not found: {{ TESTS }}/${test_name}.sh"
        echo "Available tests:"
        ls {{ TESTS }}/*.sh | sed 's|.*/||; s/\.sh$//' | column -c 80
        exit 1
    fi

    # Run the test and capture full output
    echo "=== Running test with instrumentation ==="
    rm -f "$stamp"
    {{ SAMU }} -C "$dir" "test/${test_name}.${mode}.stamp" 2>&1 || true

    echo ""
    echo "=== Exit Status Analysis ==="
    if [ -f "$stamp" ]; then
        echo "Result: PASSED (stamp exists)"
    else
        echo "Result: FAILED (no stamp)"
        if [ -f "$log" ]; then
            echo ""
            echo "=== Raw Test Output ==="
            cat "$log"
            echo ""
            echo "=== Error Pattern Analysis ==="
            if grep -q 'FAIL:' "$log" 2>/dev/null; then
                fail_count=$(grep -c 'FAIL:' "$log")
                echo "Found $fail_count assertion failures:"
                grep 'FAIL:' "$log" | head -10
            fi
            if grep -q 'SEGV\|segmentation fault' "$log" 2>/dev/null; then
                echo "CRASH: Segmentation fault detected"
            fi
            if grep -q 'timeout' "$log" 2>/dev/null; then
                echo "TIMEOUT: Test did not complete within time limit"
            fi
        else
            echo "No log file found at: $log"
        fi
    fi

    echo ""
    echo "=== Environment ==="
    echo "HOSTTYPE: {{ HOSTTYPE }}"
    echo "SHELL: $dir/bin/ksh"
    if [ -x "$dir/bin/ksh" ]; then
        echo "KSH_VERSION: $($dir/bin/ksh -c 'echo "$KSH_VERSION"' 2>/dev/null || echo 'unknown')"
    fi

    echo ""
    echo "=== Context Adaptations ==="
    for ctx in default tty fixtures timing; do
        if [ -f "tests/contexts/${ctx}.sh" ]; then
            echo "  [ok] contexts/${ctx}.sh"
        else
            echo "  [--] contexts/${ctx}.sh missing"
        fi
    done

    echo ""
    echo "=== Investigation Steps (per CLAUDE.md) ==="
    echo "1. Reproduce outside harness: just test-one $test_name $mode"
    echo "2. Check context deficiencies: cat tests/contexts/*.sh"
    echo "3. Compare with nix: just test"
    echo ""
    echo "Passes outside harness but fails inside → add context adaptation"
    echo "Fails in both → real bug, fix src/cmd/ksh26/"

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

# Remove debug build artifacts
clean-debug:
    rm -rf build/{{HOSTTYPE}}-debug

# Remove asan build artifacts
clean-asan:
    rm -rf build/{{HOSTTYPE}}-asan

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

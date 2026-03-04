# ksh26 build system porcelain
#
# Three layers:
#   just       — user-facing recipes (this file)
#   configure  — ksh script that probes platform + emits build.ninja
#   samu       — vendored ninja implementation, executes build.ninja
#
# Usage: just build | just test | just clean
#        just errors | just failures | just log
#        just check | just check-asan | just check-all
#
# Override: CC=clang just build
#          CC="ccache cc" just build    (compiler caching)

HOSTTYPE := env("HOSTTYPE", `uname -s | tr 'A-Z' 'a-z' | tr -d '\n'; printf '.'; uname -m | sed 's/aarch64/arm64/;s/i.86/i386/' | tr -d '\n'; printf -- '-'; getconf LONG_BIT 2>/dev/null || echo 64`)
BUILDDIR := "build" / HOSTTYPE
DEBUGDIR := "build" / (HOSTTYPE + "-debug")
ASANDIR  := "build" / (HOSTTYPE + "-asan")
SAMU := BUILDDIR / "bin" / "samu"
_IN_NIX := env("IN_NIX_SHELL", "")

# Warn if building outside nix devshell (soft gate — continues anyway)
[private]
_nix-warn:
    @if [ -z "{{_IN_NIX}}" ] && command -v nix >/dev/null 2>&1; then \
        printf '\033[33mwarning:\033[0m not in nix devshell — build may use host toolchain\n' >&2; \
        printf '  run: nix develop -c just <recipe>\n' >&2; \
    fi

# Bootstrap just the build tool
bootstrap:
    @mkdir -p {{BUILDDIR}}/bin
    @test -x {{SAMU}} \
        || cc -o {{SAMU}} src/cmd/INIT/samu/*.c

# ── Build ────────────────────────────────────────────────────────

# Internal: build with logging and auto-reconfigure
[private]
_build dir flags="": bootstrap
    #!/usr/bin/env bash
    set -euo pipefail
    dir="{{dir}}"
    if [[ ! -f "$dir/build.ninja" || configure.sh -nt "$dir/build.ninja" ]]; then
        sh configure.sh {{flags}}
    fi
    mkdir -p "$dir/log"
    {{SAMU}} -C "$dir" 2>&1 | tee "$dir/log/build.log"

# Build ksh26 (default recipe)
build: _nix-warn (_build BUILDDIR)

# Build with debug flags: no optimization, full debug info
build-debug: _nix-warn (_build DEBUGDIR "--debug")

# Build with sanitizers: catches use-after-free, buffer overflow, UB
build-asan: _nix-warn (_build ASANDIR "--asan")

# (Re)run feature detection and generate build.ninja
# Probes are cached — only stale probes rerun (~5s when nothing changed)
configure: _nix-warn bootstrap
    sh configure.sh

# Force all probes to rerun (ignores cache)
reconfigure: _nix-warn bootstrap
    sh configure.sh --force

# ── Test ─────────────────────────────────────────────────────────

# Internal: run tests with logging, summary, and regression detection
[private]
_test dir:
    #!/usr/bin/env bash
    set -uo pipefail
    dir="{{dir}}"
    mkdir -p "$dir/log" "$dir/test"
    summary="$dir/test/summary.log"
    # Save previous for regression detection
    [[ -f "$summary" ]] && cp "$summary" "${summary%.log}.prev" || true
    rm -f "$summary"
    t=$SECONDS
    rc=0
    {{SAMU}} -k 0 -C "$dir" test 2>&1 | tee "$dir/log/test.log" || rc=$?
    elapsed=$(( SECONDS - t ))
    # Summary
    if [[ -f "$summary" && -s "$summary" ]]; then
        printf '\n'
        sort "$summary" | grep -v '^PASS' || true
        total=$(wc -l < "$summary" | tr -d ' ')
        pass=$(grep -c '^PASS' "$summary" || true)
        printf -- '---\n%d/%d pass (%ds)\n' "$pass" "$total" "$elapsed"
        # Regression detection (only counts tests that ran both times)
        prev="${summary%.log}.prev"
        if [[ -f "$prev" && -s "$prev" ]]; then
            regressed=$(awk '
                FILENAME==ARGV[1] && /^PASS/ { prev[$2]=1 }
                FILENAME==ARGV[2] && !/^PASS/ { cur[$2]=1 }
                END { for (t in cur) if (t in prev) n++; print n+0 }
            ' "$prev" "$summary")
            improved=$(awk '
                FILENAME==ARGV[1] && !/^PASS/ { prev[$2]=1 }
                FILENAME==ARGV[2] && /^PASS/ { cur[$2]=1 }
                END { for (t in cur) if (t in prev) n++; print n+0 }
            ' "$prev" "$summary")
            if (( regressed > 0 || improved > 0 )); then
                printf 'vs previous:'
                (( regressed > 0 )) && printf ' %d regressed' "$regressed"
                (( improved > 0 )) && printf ' %d improved' "$improved"
                printf '\n'
            fi
        fi
    else
        printf '\n---\n0 tests ran — stamps current, use: just clean test && just test\n'
    fi
    exit $rc

# Run all regression tests in parallel
test: build (_test BUILDDIR)

# Run a single test: just test-one basic
test-one name locale="C": build
    {{SAMU}} -C {{BUILDDIR}} test/{{name}}.{{locale}}.stamp

# Run tests against the debug build
test-debug: build-debug (_test DEBUGDIR)

# Run tests against the asan build
test-asan: build-asan (_test ASANDIR)

# Run iffe regression tests
test-iffe: _nix-warn
    sh tests/infra/iffe.sh

# Run tests sequentially via legacy shtests harness
test-serial: build
    HOSTTYPE={{HOSTTYPE}} \
    PACKAGEROOT="$PWD" \
    INSTALLROOT="$PWD/{{BUILDDIR}}" \
    LD_LIBRARY_PATH="" \
    SHELL={{BUILDDIR}}/bin/ksh \
    KSH={{BUILDDIR}}/bin/ksh \
    bin/shtests

# Pass arbitrary args to samu
samu *args: bootstrap
    {{SAMU}} -C {{BUILDDIR}} {{args}}

# ── Diagnostics ──────────────────────────────────────────────────

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
    non_pass=$(grep -v '^PASS' "$summary" || true)
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

# ── Investigation ────────────────────────────────────────────────

# Run a test N times to detect flakiness
test-repeat name n="10" locale="C": build
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
debug name locale="C": build
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

# ── Code tools ───────────────────────────────────────────────────

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

# ── Clean ────────────────────────────────────────────────────────

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
    rm -rf {{DEBUGDIR}}

# Remove asan build artifacts
clean-asan:
    rm -rf {{ASANDIR}}

# Remove all build artifacts (every host)
cleanall:
    rm -rf build

# Install ksh and shcomp
install prefix="/usr/local": build
    install -d {{prefix}}/bin
    install -m 755 {{BUILDDIR}}/bin/ksh {{prefix}}/bin/ksh
    install -m 755 {{BUILDDIR}}/bin/shcomp {{prefix}}/bin/shcomp

# ── CI checks (nix sandbox) ─────────────────────────────────────

# Run the same checks CI runs (build + full test suite in nix sandbox)
check:
    nix build .#checks."$(nix eval --raw nixpkgs#system)".default --print-build-logs

# Run asan checks in nix sandbox
check-asan:
    nix build .#checks."$(nix eval --raw nixpkgs#system)".asan --print-build-logs

# Run all CI checks
check-all:
    nix flake check --print-build-logs

# ── Test summaries (quiet mode) ──────────────────────────────────
# These run tests silently and print categorized results.
# Different from `just test` which shows inline output + summary.

# Show categorized test results (pass/segv/abrt/fail counts)
[no-exit-message]
test-summary dir=BUILDDIR: (_run-summary dir)

[no-exit-message]
test-debug-summary: (_run-summary DEBUGDIR)

[no-exit-message]
test-asan-summary: (_run-summary ASANDIR)

# Internal: run tests then print summary for a given build dir
# Reconfigures if run-test.sh is stale (older than configure.sh).
[private]
_run-summary dir: bootstrap
    #!/bin/sh
    set -e
    d="{{dir}}"
    samu="{{SAMU}}"
    # Ensure runner exists and is up to date
    if [ ! -f "$d/run-test.sh" ] || [ configure.sh -nt "$d/run-test.sh" ]; then
        printf '%s\n' "Reconfiguring $d (run-test.sh stale)..." >&2
        case "$d" in
        *-asan*)  sh configure.sh --asan ;;
        *-debug*) sh configure.sh --debug ;;
        *)        sh configure.sh ;;
        esac
    fi
    summary="$d/test/summary.log"
    rm -f "$summary"
    "$samu" -k 0 -C "$d" test 2>/dev/null || true
    if [ ! -f "$summary" ]; then
        printf '%s\n' "No summary found at $summary"
        exit 1
    fi
    # Sort: PASS first, then failures grouped by type
    sort -k1,1 "$summary" | awk '
        { print }
        /^PASS/  { pass++ }
        /^SEGV/  { segv++ }
        /^ABRT/  { abrt++ }
        /^FAIL/  { fail++ }
        /^TIME/  { time++ }
        /^KILL/  { kill++ }
        END {
            printf "---\n"
            printf "%d pass", pass+0
            if (segv) printf ", %d segfault", segv
            if (abrt) printf ", %d abort", abrt
            if (fail) printf ", %d fail", fail
            if (time) printf ", %d timeout", time
            if (kill) printf ", %d killed", kill
            printf "\n"
        }
    '


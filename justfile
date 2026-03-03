# ksh26 build system porcelain
#
# Three layers:
#   just       — user-facing recipes (this file)
#   configure  — ksh script that probes platform + emits build.ninja
#   samu       — vendored ninja implementation, executes build.ninja
#
# Usage: just build | just test | just clean | just install
#        just build-stdio | just test-stdio | just clean-stdio
#        just build-debug | just build-asan
#        just test-summary | just test-compare
#
# Override: CC=clang just build
#          CC="ccache cc" just build    (compiler caching)

HOSTTYPE := env("HOSTTYPE", `uname -s | tr 'A-Z' 'a-z' | tr -d '\n'; printf '.'; uname -m | sed 's/aarch64/arm64/;s/i.86/i386/' | tr -d '\n'; printf -- '-'; getconf LONG_BIT 2>/dev/null || echo 64`)
BUILDDIR := "build" / HOSTTYPE
STDIODIR := "build" / (HOSTTYPE + "-stdio")
DEBUGDIR := "build" / (HOSTTYPE + "-debug")
ASANDIR  := "build" / (HOSTTYPE + "-asan")
STDIO_DEBUGDIR := "build" / (HOSTTYPE + "-stdio-debug")
STDIO_ASANDIR  := "build" / (HOSTTYPE + "-stdio-asan")
SAMU := BUILDDIR / "bin" / "samu"
_IN_NIX := env("IN_NIX_SHELL", "")

# Warn if building outside nix devshell (soft gate — continues anyway)
[private]
_nix-warn:
    @if [ -z "{{_IN_NIX}}" ] && command -v nix >/dev/null 2>&1; then \
        printf '\033[33mwarning:\033[0m not in nix devshell — build may use host toolchain\n' >&2; \
        printf '  run: nix develop -c just <recipe>\n' >&2; \
    fi

# Build ksh26 (default recipe)
build: _nix-warn bootstrap
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
configure: _nix-warn bootstrap
    sh configure.sh

# Force all probes to rerun (ignores cache)
reconfigure: _nix-warn bootstrap
    sh configure.sh --force

# Run all regression tests in parallel via samu
# -k 0 = keep going on failure so all tests run
test: build
    {{SAMU}} -k 0 -C {{BUILDDIR}} test

# Run a single test: just test-one basic
test-one name locale="C": build
    {{SAMU}} -C {{BUILDDIR}} test/{{name}}.{{locale}}.stamp

# Run tests sequentially via legacy shtests harness
test-serial: build
    HOSTTYPE={{HOSTTYPE}} \
    PACKAGEROOT="$PWD" \
    INSTALLROOT="$PWD/{{BUILDDIR}}" \
    LD_LIBRARY_PATH="" \
    SHELL={{BUILDDIR}}/bin/ksh \
    KSH={{BUILDDIR}}/bin/ksh \
    bin/shtests

# Run I/O benchmarks comparing sfio vs stdio backends
bench: build build-stdio
    ksh bench/io-bench.ksh {{BUILDDIR}}/bin/ksh {{STDIODIR}}/bin/ksh

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

# Run the same checks CI runs (build + full test suite in nix sandbox)
check:
    nix build .#checks."$(nix eval --raw nixpkgs#system)".default --print-build-logs

# ── stdio backend (KSH_IO_SFIO=0) ────────────────────────────────

# Build ksh26 with stdio backend
build-stdio: _nix-warn bootstrap
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

# ── Debug build (-O0 -g) ─────────────────────────────────────────

# Build with debug flags: no optimization, full debug info
build-debug: _nix-warn bootstrap
    @test -f {{DEBUGDIR}}/build.ninja \
        -a {{DEBUGDIR}}/build.ninja -nt configure.sh \
        || sh configure.sh --debug
    {{SAMU}} -C {{DEBUGDIR}}

test-debug: build-debug
    {{SAMU}} -k 0 -C {{DEBUGDIR}} test

clean-debug:
    rm -rf {{DEBUGDIR}}

# ── ASAN build (AddressSanitizer + UBSan) ────────────────────────

# Build with sanitizers: catches use-after-free, buffer overflow, UB
build-asan: _nix-warn bootstrap
    @test -f {{ASANDIR}}/build.ninja \
        -a {{ASANDIR}}/build.ninja -nt configure.sh \
        || sh configure.sh --asan
    {{SAMU}} -C {{ASANDIR}}

test-asan: build-asan
    {{SAMU}} -k 0 -C {{ASANDIR}} test

clean-asan:
    rm -rf {{ASANDIR}}

# ── Combined variants (stdio + debug/asan) ───────────────────────

build-stdio-debug: _nix-warn bootstrap
    @test -f {{STDIO_DEBUGDIR}}/build.ninja \
        -a {{STDIO_DEBUGDIR}}/build.ninja -nt configure.sh \
        || sh configure.sh --stdio --debug
    {{SAMU}} -C {{STDIO_DEBUGDIR}}

test-stdio-debug: build-stdio-debug
    {{SAMU}} -k 0 -C {{STDIO_DEBUGDIR}} test

build-stdio-asan: _nix-warn bootstrap
    @test -f {{STDIO_ASANDIR}}/build.ninja \
        -a {{STDIO_ASANDIR}}/build.ninja -nt configure.sh \
        || sh configure.sh --stdio --asan
    {{SAMU}} -C {{STDIO_ASANDIR}}

test-stdio-asan: build-stdio-asan
    {{SAMU}} -k 0 -C {{STDIO_ASANDIR}} test

# ── Test summaries ───────────────────────────────────────────────

# Show categorized test results (pass/segv/abrt/fail counts)
[no-exit-message]
test-summary dir=BUILDDIR: (_run-summary dir)

[no-exit-message]
test-stdio-summary: (_run-summary STDIODIR)

[no-exit-message]
test-debug-summary: (_run-summary DEBUGDIR)

[no-exit-message]
test-asan-summary: (_run-summary ASANDIR)

[no-exit-message]
test-stdio-asan-summary: (_run-summary STDIO_ASANDIR)

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
        *-stdio-asan*) sh configure.sh --stdio --asan ;;
        *-stdio-debug*) sh configure.sh --stdio --debug ;;
        *-stdio*) sh configure.sh --stdio ;;
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

# ── Comparative test report ──────────────────────────────────────

# Side-by-side sfio vs stdio test results
[no-exit-message]
test-compare: bootstrap
    #!/bin/sh
    set -e
    sfio="{{BUILDDIR}}"
    stdio="{{STDIODIR}}"
    samu="{{SAMU}}"

    # Run both test suites, collecting summaries
    for d in "$sfio" "$stdio"; do
        rm -f "$d/test/summary.log"
    done

    printf '%s\n' "Running sfio tests..."
    "$samu" -k 0 -C "$sfio" test 2>/dev/null || true
    printf '%s\n' "Running stdio tests..."
    "$samu" -k 0 -C "$stdio" test 2>/dev/null || true

    sfio_sum="$sfio/test/summary.log"
    stdio_sum="$stdio/test/summary.log"

    if [ ! -f "$sfio_sum" ] || [ ! -f "$stdio_sum" ]; then
        printf '%s\n' "Missing summary file(s). Run just build && just build-stdio first." >&2
        exit 1
    fi

    # Join on test name, show side by side
    awk '
        BEGIN { printf "%-30s  %-6s  %-6s\n", "TEST", "sfio", "stdio"; printf "%-30s  %-6s  %-6s\n", "----", "----", "-----" }
        FILENAME == ARGV[1] { sfio[$2] = $1; next }
        FILENAME == ARGV[2] { stdio[$2] = $1 }
        END {
            # Collect all test names
            for (t in sfio) tests[t] = 1
            for (t in stdio) tests[t] = 1
            n = asorti(tests, sorted)
            sp = 0; ss = 0; sv = 0; sa = 0; sf = 0
            for (i = 1; i <= n; i++) {
                t = sorted[i]
                s1 = (t in sfio) ? sfio[t] : "---"
                s2 = (t in stdio) ? stdio[t] : "---"
                # Only show lines where results differ or stdio fails
                if (s1 != s2) printf "%-30s  %-6s  %-6s\n", t, s1, s2
                if (s1 == "PASS") sp++
                if (s2 == "PASS") ss++
                else if (s2 == "SEGV") sv++
                else if (s2 == "ABRT") sa++
                else sf++
            }
            printf "---\n"
            printf "sfio: %d pass | stdio: %d pass", sp, ss
            if (sv) printf ", %d segv", sv
            if (sa) printf ", %d abrt", sa
            if (sf) printf ", %d fail", sf
            printf "\n"
        }
    ' "$sfio_sum" "$stdio_sum"

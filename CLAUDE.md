# ksh26 — Project Instructions

## Build & Test

Unified porcelain via `just`:

```sh
just test                        # auto-detect platform, full nix test suite
just test linux                  # cross to linux (from darwin) or native
just test --asan                 # sanitizer variant
just test --category fast        # fast subset (local samu)
just test --one basic            # single test (local samu)
just test --debug basic          # run under lldb/gdb
just test --verbose              # show build artifacts after test

just build                       # auto-detect platform
just build --debug / --asan      # variants

just check-all                   # nix flake check (all platforms + formatting)
```

**Validation discipline:**
- `just test` is the ONLY validation command — never `./configure.sh` or `samu` standalone
- Always tee: `just test 2>&1 | tee /tmp/ksh-test.log` — never grep/tail build output
- Never re-run without a source change — read the log
- Both `just test` AND `just test linux` before every commit

## Code Style

- C23 (`-std=c23`), GCC 14+ / Clang 18+
- Tabs (8-space width), opening braces on own line, `/* */` comments only
- Format with `just fmt`

## Serena Workflow (C Source Refactoring)

Use serena's semantic tools for navigating and editing C source. This is critical
for the ksh26 refactoring work (Layers 1-4) where files are 500-3000 lines.

### Navigation (read code without loading entire files)

```
get_symbols_overview  FILE              → list all functions/variables in a file
find_symbol           NAME [--body]     → read a specific function's source
find_referencing_symbols NAME FILE      → find all callers of a function
search_for_pattern    REGEX [--path]    → regex search with file filtering
```

### Editing (precise symbol-level modifications)

```
replace_symbol_body   NAME FILE BODY    → rewrite a function entirely
insert_after_symbol   NAME FILE BODY    → add new code after a symbol
insert_before_symbol  NAME FILE BODY    → add new code before a symbol
rename_symbol         NAME FILE NEWNAME → rename across entire codebase
```

### When to use serena vs standard tools

| Task | Tool |
|------|------|
| Read a C function | `find_symbol` with `include_body=true` |
| Find all callers before modifying | `find_referencing_symbols` |
| Rename a C identifier everywhere | `rename_symbol` |
| Rewrite a function body | `replace_symbol_body` |
| Add a new function | `insert_after_symbol` |
| Search for a pattern in C code | `search_for_pattern` with `restrict_search_to_code_files=true` |
| Edit shell scripts | standard `Read` + `Edit` tools |
| Edit nix files | standard `Read` + `Edit` tools |
| Find files by name | `Glob` tool |
| Search file contents | `Grep` tool |

### Refactoring workflow

Before modifying any C function:
1. `get_symbols_overview` on the file — understand the function landscape
2. `find_symbol` with `include_body=true` — read the function to modify
3. `find_referencing_symbols` — check all callers for compatibility
4. Make the change (`replace_symbol_body` or `Edit`)
5. `just test` — validate

## Probe System

- 58 probes in `build/configure/probes/*.sh`
- Primitives (`_mc_compile`, `probe_link`, etc.) → stderr to `/dev/null` (expected failures)
- Delegates (`probe_run`) → stderr to `$LOGDIR/probe.log` (logged for inspection)
- `-include FEATURE/standards` before `-include stdio.h` for glibc `_GNU_SOURCE` ordering

## Test Infrastructure

- Tests in `src/cmd/ksh26/tests/*.sh` — use `err_exit` pattern from `_common`
- Categories: `tests/categories.sh` (timing, signals, fast, etc.)
- Expected failures: `tests/expected-failures.sh` (xfail per test/line/platform)
- Contexts: `tests/contexts/` (default.sh, tty.sh, paths.sh, timing.sh)
- Test results: `$BUILDDIR/test/results/*.txt` — pass+fail counted against stamp_count

## Zero-Failure Policy

Any test failure is a regression until proven otherwise. Assume YOU broke it.
Never hardcode counts or thresholds — compute at runtime.

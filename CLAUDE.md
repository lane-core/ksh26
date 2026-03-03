# ksh26

Independent fork of ksh93u+m (upstream: `ksh93/ksh`), redesigned to
modern standards. Guided by System L / duploid theory (see `REDESIGN.md`).

## Branches

| Branch | Purpose |
|--------|---------|
| `main` | Primary development branch. |
| `legacy` | Tracks upstream `ksh93/ksh` dev. Pre-fork state. |
| `fix/*` | Bugfix branches off legacy, submitted as PRs to upstream. |

## Building and testing

**All build and test commands MUST run inside `nix develop`.** The flake provides
the complete toolchain (compiler, linker, pkg-config, utf8proc, libiconv). Do not
use host tools. The justfile warns if you're outside a nix shell; treat this as
an error.

```sh
# ── Standard workflow (one-shot commands) ────────────────────────
nix develop -c just build          # build ksh26
nix develop -c just test           # parallel test suite (115 tests)
nix develop -c just test-one basic # run a single test
nix develop -c just configure      # (re)run feature detection
nix develop -c just reconfigure    # force all probes to rerun

# ── Interactive session ──────────────────────────────────────────
nix develop .#agent                # enter agent shell (auto-configures)
just build                         # then run recipes directly
just test

# ── Validation before committing ─────────────────────────────────
just check                         # build + full test suite in nix sandbox
                                   # (same derivation CI runs — does not
                                   # require being inside nix develop)
```

### Build system

Three layers: `just` (porcelain) → `configure.sh` (probes + generates
`build.ninja`) → `samu` (vendored ninja, executes `build.ninja`). Output goes to
`build/$HOSTTYPE/`. Feature probes are cached — reconfigure takes ~5s when
nothing changed.

### Recipes

| Recipe | Purpose |
|--------|---------|
| `just build` | Build ksh26 (default) |
| `just test` | Run all 115 tests in parallel (with summary) |
| `just test-one NAME [LOCALE]` | Run a single test (`C` or `C.UTF-8`) |
| `just errors [DIR]` | Show build errors from log (no re-build) |
| `just warnings [DIR]` | Show build warnings from log |
| `just failures [DIR]` | Show failed tests with individual logs |
| `just log [build\|test] [NAME]` | Show build/test logs |
| `just test-repeat NAME [N] [LOCALE]` | Run a test N times for flakiness |
| `just debug NAME [LOCALE]` | Run a test under lldb/gdb |
| `just check` | Build + test in nix sandbox (CI parity) |
| `just check-asan` | Asan check in nix sandbox |
| `just check-stdio` | Stdio check in nix sandbox |
| `just check-all` | All nix checks (`nix flake check`) |
| `just configure` | (Re)run feature detection |
| `just reconfigure` | Force all probes to rerun |
| `just compile-commands` | Generate `compile_commands.json` for clangd/LSP |
| `just build-stdio` | Build with stdio backend (`KSH_IO_SFIO=0`) |
| `just test-stdio` | Test the stdio build |
| `just build-stdio-debug` | stdio with `-O0` for debugger stepping |
| `just build-stdio-asan` | stdio + AddressSanitizer + UBSan |
| `just test-stdio-summary` | Categorized stdio results (PASS/SEGV/ABRT/FAIL) |
| `just test-stdio-asan-summary` | Same, for stdio-asan build |
| `just test-compare` | Side-by-side sfio vs stdio results |

### Adding tests

Tests live in `src/cmd/ksh26/tests/`. Drop a `.sh` file, reconfigure, done —
`configure.sh` discovers all `*.sh` files automatically and generates both
`C` and `C.UTF-8` locale variants. No manifest to update.

Use the `err_exit` pattern:
```ksh
. "${SHTESTS_COMMON:-${0%/*}/_common}"
[[ $(some_command) == expected ]] || err_exit "description of failure"
exit $((Errors<125?Errors:125))
```

### Devshells

| Shell | Purpose |
|-------|---------|
| `default` | Full build+test environment. stdenv (cc, ld, ar), just, git, scdoc, pkg-config, ccache. lldb on Darwin; gdb + valgrind on Linux. Dependencies (utf8proc, libiconv) inherited from the package via `inputsFrom`. |
| `agent` | Extends default. Auto-detects HOSTTYPE and runs `just configure` on entry if no `build.ninja` exists. Use for automated agents. |

### Debugging

Inside `nix develop`:
- **Darwin**: `lldb -- build/$HOSTTYPE/bin/ksh -c '...'`
- **Linux**: `gdb --args build/$HOSTTYPE/bin/ksh -c '...'`; `valgrind build/$HOSTTYPE/bin/ksh -c '...'`
- **Compiler cache**: on by default in agent shell (`CC="ccache cc"`); opt out with `CC=cc just build`
- **LSP/clangd**: `just compile-commands` (generates `compile_commands.json` via samu)

### Cross-platform checks

```sh
just check                                   # local system (same as CI)
nix build .#checks.x86_64-linux.default      # explicit Linux (remote builder)
```

The check derivation excludes `sigchld.sh` (signal timing in Nix sandbox) and
asserts ≥110 test stamps as a regression guard against build.ninja generation bugs.

## Agent build/test workflow

Named recipes exist for every common operation. Use them.

| Need | Recipe | NOT this |
|------|--------|----------|
| Build | `just build` | — |
| See build errors | `just errors` | `just build 2>&1 \| grep error` |
| See build warnings | `just warnings` | `just build 2>&1 \| grep warning` |
| Full build log | `just log build` | re-running the build |
| Test | `just test` | — |
| See test failures | `just failures` | `just test 2>&1 \| grep FAIL` |
| Specific test log | `just log test NAME` | `cat build/.../test/NAME...` |
| CI validation | `just check` | — |
| Sanitizer check | `just check-asan` | ad-hoc asan invocations |
| All CI checks | `just check-all` | — |
| Flaky test? | `just test-repeat NAME` | loop in shell |
| Debug a test | `just debug NAME` | manual lldb/gdb setup |

Build output is logged to `build/$HOSTTYPE/log/build.log`. Test output is logged
to `build/$HOSTTYPE/log/test.log`. Per-test failure logs are in
`build/$HOSTTYPE/test/*.stamp.log`. The `just test` summary includes regression
detection against the previous run.

### Noticed issues → TODO.md

When you notice something that should be fixed but isn't part of the current task,
add it to `TODO.md` with a brief description, severity, and enough context for
someone to pick it up later. Don't fix it inline — capture it and move on.

## Coding conventions

- Indent with tabs (8-space width)
- Opening braces on own line
- `/* */` comments only (no `//`)
- C23 dialect (GCC 14+ / Clang 18+)
- Each upstream PR is squashed into a single commit

## Merge flow: legacy → main

Bugfixes are developed on `fix/*` branches off `legacy` and submitted as PRs to
upstream (`ksh93/ksh`). When fixes land on legacy, they should be evaluated for
incorporation into main.

### When a legacy fix applies cleanly

Cherry-pick or merge. No special documentation needed beyond the commit message.

```sh
git cherry-pick <commit>    # if it applies cleanly
```

### When a legacy fix doesn't apply

When main has diverged enough that a legacy fix can't be cherry-picked, document
the situation. Create a note in `notes/divergences/` with:

- **What the dev fix does**: commit hash, summary, which files it touches
- **Why it doesn't apply**: what ksh26 changed that conflicts
- **Whether ksh26 needs it**: is the bug structurally prevented by the refactor,
  or does it need an equivalent fix?
- **ksh26 equivalent**: if a fix is needed, what's the ksh26-native approach?

Example filename: `NNN-short-description.md`

### Structural prevention

Some legacy bugfixes will be unnecessary on main because the refactored
architecture prevents the bug class entirely. These are worth documenting as
evidence that the refactor is working — they're the payoff.

Template:

```markdown
# NNN: <short description>

## Dev fix
Commit: <hash>
Files: <list>
Summary: <what it fixes>

## ksh26 status: structurally prevented
The polarity frame API (sh_polarity_enter / sh_polarity_leave)
handles this boundary crossing. The manual save/restore that the dev
fix adds is unnecessary because [specific reason].
```

## Documentation workflow

The main branch maintains two companion documents:

- **SPEC.md** — The stable theoretical analysis. Sequent calculus correspondence,
  duploid framework, critical pair diagnosis, boundary violation taxonomy. This
  is the reference document; it changes only when the theory itself is refined.
- **REDESIGN.md** — The living implementation tracker. Records what has been built,
  which call sites are converted, direction status, divergences from dev. Update
  this as work progresses.

When implementing a direction or converting a call site, update REDESIGN.md to
reflect the new state. When a legacy bugfix is handled differently (or structurally
prevented) on main, add a note to `notes/divergences/` and update the
divergence table in REDESIGN.md.

## Reference papers

Theoretical background for the ksh26 refactor lives in `~/src/ksh/`:

- `dissection-of-l.gist.txt` — Dissection of L (System L / duploid structure)
- `wadler-cbv-dual-cbn-reloaded.pdf` — Wadler, "Call-by-value is dual to call-by-name, reloaded"

See also `SPEC.md` and `REDESIGN.md` for the full theoretical analysis
and implementation status.

## Key source files

| File | Role | Polarity relevance |
|------|------|--------------------|
| `src/cmd/ksh26/sh/xec.c` | Main eval (sh_exec, sh_debug) | Computation mode; polarity boundaries at trap dispatch |
| `src/cmd/ksh26/sh/name.c` | Name resolution (nv_create, nv_open) | Value mode; sh.prefix management |
| `src/cmd/ksh26/sh/macro.c` | Parameter expansion | Value mode (word expansion) |
| `src/cmd/ksh26/include/shell.h` | Shell_t struct, sh_scoped | Global state; polarity-sensitive fields |
| `src/cmd/ksh26/include/fault.h` | checkpt, push/pop context | Continuation stack |
| `src/cmd/ksh26/include/shnodes.h` | Shnode_t AST union, type tags | Two-sorted syntax |

## Polarity-sensitive global state

These `Shell_t` fields require save/restore discipline at polarity boundaries:

| Field | Type | Purpose |
|-------|------|---------|
| `sh.prefix` (shell.h:342) | `char*` | Compound assignment context marker |
| `sh.st` (shell.h:319) | `struct sh_scoped` | Scoped interpreter state |
| `sh.jmplist` (shell.h:350) | `sigjmp_buf*` | Continuation stack head |
| `sh.var_tree` (shell.h:283) | `Dt_t*` | Current variable scope |

## Bug documentation

Bugs specific to ksh26 go in `notes/bugs/`, following the same format as
the parent project's `bugs/` directory (self-contained reproducer scripts
with header comments, analysis, and workaround). These are separate from
upstream bugs.

# ksh26

Independent fork of ksh93u+m (originated from `ksh93/ksh`), redesigned to
modern standards. Guided by System L / duploid theory (see `REDESIGN.md`).

This is a fully independent project — not a tracking fork. There are no
merges from upstream. The `legacy` branch preserves the pre-fork state as
a reference point for divergence documentation, not as a merge source.

## Branches

| Branch | Purpose |
|--------|---------|
| `main` | Primary development branch. |
| `legacy` | Frozen pre-fork state. Reference for divergence documentation. |

## Building and testing

Two paths: **validation** (nix-backed, content-addressed) and **iteration**
(local samu, devshell-only).

```sh
# ── Validation (works anywhere, no nix develop needed) ───────────
just build                         # build ksh26 via nix (content-addressed)
just test                          # full test suite via nix
just build-debug                   # build with debug flags
just build-asan                    # build with sanitizers
just test-asan                     # test with sanitizers

# ── Iteration (requires nix develop) ─────────────────────────────
nix develop -c just test-one basic # run a single test (local samu)
nix develop -c just debug basic    # interactive debugger
nix develop -c just configure      # (re)run feature detection

# ── Interactive session ──────────────────────────────────────────
nix develop .#agent                # enter agent shell (auto-configures)
just test-one basic                # iteration recipes directly
just debug basic                   # debugger directly
```

Validation recipes call `nix build` internally — any source change triggers
a full rebuild, no changes means ~2-5s cache hit. No stale builds possible.
Iteration recipes use timestamp-based samu caching for sub-second rebuilds.

### Build system

Four layers: `just` (porcelain) → `nix build` (validation) or `samu`
(iteration) → `configure.sh` (probes + generates `build.ninja`) → `samu`
(vendored ninja, executes `build.ninja`). Validation output goes to `result/`;
iteration output goes to `build/$HOSTTYPE/`.

### Recipes

**Validation** (nix-backed, no devshell needed):

| Recipe | Purpose |
|--------|---------|
| `just build` | Build ksh26 (content-addressed via nix) |
| `just test` | Run all regression tests (content-addressed via nix) |
| `just build-debug` | Build with debug flags |
| `just build-asan` | Build with sanitizers |
| `just test-asan` | Run tests with sanitizers |
| `just check` | Same as `just test` (alias for CI familiarity) |
| `just check-asan` | Same as `just test-asan` |
| `just check-all` | All nix checks (`nix flake check`) |

**Iteration** (local samu, requires devshell):

| Recipe | Purpose |
|--------|---------|
| `just test-one NAME [LOCALE]` | Run a single test (`C` or `C.UTF-8`) |
| `just test-repeat NAME [N] [LOCALE]` | Run a test N times for flakiness |
| `just debug NAME [LOCALE]` | Run a test under lldb/gdb |
| `just configure` | (Re)run feature detection |
| `just reconfigure` | Force all probes to rerun |
| `just compile-commands` | Generate `compile_commands.json` for clangd/LSP |
| `just test-iffe` | Run iffe regression tests (18 test groups) |

**Diagnostics** (work with iteration build logs):

| Recipe | Purpose |
|--------|---------|
| `just errors [DIR]` | Show build errors from log (no re-build) |
| `just warnings [DIR]` | Show build warnings from log |
| `just failures [DIR]` | Show failed tests with individual logs |
| `just log [build\|test] [NAME]` | Show build/test logs |

### Adding tests

Tests live in `tests/shell/`. Drop a `.sh` file, reconfigure, done —
`configure.sh` discovers all `*.sh` files automatically and generates both
`C` and `C.UTF-8` locale variants. No manifest to update.

Build infrastructure tests (iffe, etc.) live in `tests/infra/`.

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

The check derivation asserts ≥114 test stamps as a regression guard against
build.ninja generation bugs.

## Agent build/test workflow

`just build` and `just test` are nix-backed — they work anywhere (no `nix
develop` wrapper needed) and are content-addressed (no stale builds possible).
Use them for all validation. Use iteration recipes (`test-one`, `debug`) inside
`nix develop` for fast edit-test cycles.

| Need | Recipe | Notes |
|------|--------|-------|
| Build | `just build` | Nix-backed, produces `result/bin/` |
| Test | `just test` | Nix-backed, full suite with summary |
| Single test | `just test-one NAME` | Devshell, local samu |
| Debug a test | `just debug NAME` | Devshell, local samu + lldb/gdb |
| Sanitizer check | `just test-asan` | Nix-backed |
| All CI checks | `just check-all` | Nix-backed |
| Flaky test? | `just test-repeat NAME` | Devshell, local samu |
| Iffe tests | `just test-iffe` | — |

Iteration build logs go to `build/$HOSTTYPE/log/`. Diagnostics recipes
(`just errors`, `just warnings`, `just failures`, `just log`) work with
iteration build output.

### Noticed issues → TODO.md

When you notice something that should be fixed but isn't part of the current task,
add it to `TODO.md` with a brief description, severity, and enough context for
someone to pick it up later. Don't fix it inline — capture it and move on.

## Pre-commit review protocol

Every commit requires a correctness review before staging. No exceptions —
documentation-only changes still get reference accuracy checks.

### Mechanism

- **Non-trivial changes** (multi-file, approach-level, new subsystem work):
  spawn a `feature-dev:code-reviewer` agent. The agent reviews the full diff
  against the checklist below and returns a verdict.
- **Small changes** (single-file fixes, typo corrections, config tweaks):
  the committing agent runs through the checklist inline before staging.

The threshold is judgment-based: if you'd want a second pair of eyes on it
in a human team, use the agent. When in doubt, use the agent.

### Checklist

1. **Task completion**: Does the diff accomplish what was requested? Read the
   task description or conversation context and verify each stated requirement
   against the actual changes. Flag anything claimed-but-missing or
   present-but-unrequested.

2. **Correctness against project materials**: Cross-reference the diff against:
   - This file (CLAUDE.md) — conventions, contracts, known pitfalls
   - SPEC.md / REDESIGN.md — theoretical constraints, implementation status
   - Source comments and headers in modified files
   - TODO.md — does this resolve or create tracked issues?

   Flag any implementation that contradicts or ignores documented constraints.

3. **Reference accuracy**: Every line number, test count, file path, function
   name, or cross-reference in the diff — including in documentation and
   comments — must be verified against the current state of the codebase.
   Stale references are bugs.

4. **Approach validity**: For non-trivial changes, ask: is this the right
   approach? Does it respect the contracts of the subsystems it touches?
   Could the approach fail for reasons not yet visible in test results?
   A wrong approach that passes tests is worse than a right approach with
   a failing test.

5. **Build and test**: `just test` must pass (nix-backed, content-addressed
   — equivalent to `just check`). New warnings must be acknowledged or
   fixed. Test count must not regress.

### Verdict format

The review produces one of:

- **PASS** — all checks satisfied, proceed to commit.
- **PASS with notes** — minor issues that don't block the commit. Notes go
  in the commit message or TODO.md.
- **REVISE** — issues identified. Each listed with severity
  (critical/moderate/minor) and a concrete fix. Do not commit until
  critical and moderate issues are resolved.

### Escalation

If the review reveals the *approach itself* may be wrong — not just the
implementation — stop and raise this before attempting fixes. Per the
discovery-driven restart rule (see agent memory): re-evaluate the design
against the expanded understanding rather than patching forward.

## Coding conventions

- Indent with tabs (8-space width)
- Opening braces on own line
- `/* */` comments only (no `//`)
- C23 dialect (GCC 14+ / Clang 18+)


## Divergence documentation

When ksh26's architecture handles a known ksh93u+m bug differently (or
structurally prevents it), document the situation in `notes/divergences/`.
The `legacy` branch serves as the reference point for comparison.

Each divergence note should cover:
- What the upstream bug is and how upstream fixed it
- How ksh26 handles it (structural prevention, different fix, or N/A)
- Why the approaches differ

Example filename: `NNN-short-description.md`

## Documentation workflow

The main branch maintains two companion documents:

- **SPEC.md** — The stable theoretical analysis. Sequent calculus correspondence,
  duploid framework, critical pair diagnosis, boundary violation taxonomy. This
  is the reference document; it changes only when the theory itself is refined.
- **REDESIGN.md** — The living implementation tracker. Records what has been built,
  which call sites are converted, implementation status, divergences from dev.
  Update this as work progresses.

When implementing a concrete refactoring or converting a call site, update
REDESIGN.md to reflect the new state. When a legacy bugfix is handled differently (or structurally
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
| `sh.prefix` (shell.h:343) | `char*` | Compound assignment context marker |
| `sh.st` (shell.h:320) | `struct sh_scoped` | Scoped interpreter state |
| `sh.jmplist` (shell.h:351) | `sigjmp_buf*` | Continuation stack head |
| `sh.var_tree` (shell.h:284) | `Dt_t*` | Current variable scope |

## Bug documentation

Bugs specific to ksh26 go in `notes/bugs/`, following the same format as
the parent project's `bugs/` directory (self-contained reproducer scripts
with header comments, analysis, and workaround). These are separate from
upstream bugs.

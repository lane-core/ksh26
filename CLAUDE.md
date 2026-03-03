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

```sh
just build              # build (default recipe)
just test               # parallel test suite (115 tests)
just test-one basic     # run a single test
just clean              # remove build artifacts
just configure          # (re)run feature detection
just reconfigure        # force all probes to rerun
just compile-commands   # generate compile_commands.json for clangd/LSP
just build-stdio        # build with stdio backend (KSH_IO_SFIO=0)
just test-stdio         # test the stdio build
```

The build system is three layers: `just` (porcelain) → `configure.sh` (probes
+ generates `build.ninja`) → `samu` (vendored ninja, executes `build.ninja`).
Output goes to `build/$HOSTTYPE/`. Feature probes are cached — reconfigure takes
~5s when nothing changed.

Tests live in `src/cmd/ksh26/tests/`. Use the `err_exit` pattern for assertions.

## Nix development environment

The flake provides reproducible development shells — no host toolchain needed.

```sh
nix develop             # default shell: compiler, just, pkg-config, debugger, ccache
nix develop .#agent     # agent shell: auto-configures on entry if needed
nix develop -c just build   # one-shot build inside the nix environment
```

### Devshells

| Shell | Purpose |
|-------|---------|
| `default` | Full build+test environment. Provides stdenv (cc, ld, ar), just, git, scdoc, pkg-config, ccache. lldb on Darwin, gdb+valgrind on Linux. Dependencies (utf8proc, libiconv) inherited from the package derivation via `inputsFrom`. |
| `agent` | Extends default. Auto-detects HOSTTYPE and runs `just configure` on entry if no `build.ninja` exists. Use this for CI or automated agents that need a ready-to-build environment. |

### Compiler caching

ccache is available in the devshell but opt-in:
```sh
CC="ccache cc" just build
```

### Cross-platform checks

```sh
nix flake check                              # run test suite on all configured systems
nix build .#checks.x86_64-linux.default      # explicit Linux check (remote builder)
```

The check derivation excludes `sigchld.sh` (signal timing differs in the Nix
sandbox) and asserts ≥110 test stamps as a regression guard.

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

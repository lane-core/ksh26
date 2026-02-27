# ksh — ksh93u+m fork (ksh26 branch)

Fork of ksh93u+m (upstream: `ksh93/ksh`). The `ksh26` branch is a structural
refactor guided by System L / duploid theory (see `REDESIGN.md`).

## Branches

| Branch | Purpose |
|--------|---------|
| `dev` | Tracks upstream `ksh93/ksh` dev. Bugfixes land here first. |
| `ksh26` | Structural refactor branch. Diverges from dev over time. |
| `fix/*` | Bugfix branches off dev, submitted as PRs to upstream. |

## Building and testing

```sh
bin/package make        # build
bin/package test        # full test suite
bin/shtests             # ksh regression tests directly
```

Tests live in `src/cmd/ksh26/tests/`. Use the `err_exit` pattern for assertions.

## Coding conventions (upstream)

- Indent with tabs (8-space width)
- Opening braces on own line
- `/* */` comments only (no `//`)
- C89 dialect
- Each upstream PR is squashed into a single commit

## Merge flow: dev → ksh26

Bugfixes are developed on `fix/*` branches off `dev` and submitted as PRs to
upstream (`ksh93/ksh`). When fixes land on dev, they should be evaluated for
incorporation into ksh26.

### When a dev fix applies cleanly

Cherry-pick or merge. No special documentation needed beyond the commit message.

```sh
git cherry-pick <commit>    # if it applies cleanly
```

### When a dev fix doesn't apply

When ksh26 has diverged enough that a dev fix can't be cherry-picked, document
the situation. Create a note in `notes/divergences/` with:

- **What the dev fix does**: commit hash, summary, which files it touches
- **Why it doesn't apply**: what ksh26 changed that conflicts
- **Whether ksh26 needs it**: is the bug structurally prevented by the refactor,
  or does it need an equivalent fix?
- **ksh26 equivalent**: if a fix is needed, what's the ksh26-native approach?

Example filename: `NNN-short-description.md`

### Structural prevention

Some dev bugfixes will be unnecessary on ksh26 because the refactored
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

## ksh26 documentation workflow

The ksh26 branch maintains two companion documents:

- **SPEC.md** — The stable theoretical analysis. Sequent calculus correspondence,
  duploid framework, critical pair diagnosis, boundary violation taxonomy. This
  is the reference document; it changes only when the theory itself is refined.
- **REDESIGN.md** — The living implementation tracker. Records what has been built,
  which call sites are converted, direction status, divergences from dev. Update
  this as work progresses.

When implementing a direction or converting a call site, update REDESIGN.md to
reflect the new state. When a dev bugfix is handled differently (or structurally
prevented) on ksh26, add a note to `notes/divergences/` and update the
divergence table in REDESIGN.md.

## Reference papers

Theoretical background for the ksh26 refactor lives in `~/src/ksh/`:

- `dissection-of-l.gist.txt` — Dissection of L (System L / duploid structure)
- `wadler-cbv-dual-cbn-reloaded.pdf` — Wadler, "Call-by-value is dual to call-by-name, reloaded"

See also `SPEC.md` and `REDESIGN.md` in the ksh26 worktree for the full
theoretical analysis and implementation status.

## ksh26-specific notes

### Key source files

| File | Role | Polarity relevance |
|------|------|--------------------|
| `src/cmd/ksh26/sh/xec.c` | Main eval (sh_exec, sh_debug) | Computation mode; polarity boundaries at trap dispatch |
| `src/cmd/ksh26/sh/name.c` | Name resolution (nv_create, nv_open) | Value mode; sh.prefix management |
| `src/cmd/ksh26/sh/macro.c` | Parameter expansion | Value mode (word expansion) |
| `src/cmd/ksh26/include/shell.h` | Shell_t struct, sh_scoped | Global state; polarity-sensitive fields |
| `src/cmd/ksh26/include/fault.h` | checkpt, push/pop context | Continuation stack |
| `src/cmd/ksh26/include/shnodes.h` | Shnode_t AST union, type tags | Two-sorted syntax |

### Polarity-sensitive global state

These `Shell_t` fields require save/restore discipline at polarity boundaries:

| Field | Type | Purpose |
|-------|------|---------|
| `sh.prefix` (shell.h:305) | `char*` | Compound assignment context marker |
| `sh.st` (shell.h:282) | `struct sh_scoped` | Scoped interpreter state |
| `sh.jmplist` (shell.h:306) | `sigjmp_buf*` | Continuation stack head |
| `sh.var_tree` (shell.h:246) | `Dt_t*` | Current variable scope |

### Bug documentation (ksh26-specific)

Bugs specific to the ksh26 refactor go in `notes/bugs/`, following the same
format as the parent project's `bugs/` directory (self-contained reproducer
scripts with header comments, analysis, and workaround). These are separate
from upstream bugs.

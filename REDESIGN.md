# ksh26: Redesign Progress

Living tracker for the ksh26 structural refactor.


## What ksh26 is

Unix shell, done right, for 2026.

The Bourne shell tradition — text streams, composable tools, the shell as
both interactive environment and scripting language — is sound design
philosophy. What's aged is the implementation: codebases carrying decades of
portability scaffolding for dead platforms, implicit invariants maintained by
convention rather than structure, interactive experiences unchanged since the
early '90s.

ksh93 has the strongest scripting engine in the Bourne family: compound
variables, disciplines, arithmetic, parameter expansion that covers what
other shells fork `sed` for. ksh26 takes that engine and rethinks the
project around it — stripping AT&T legacy, hardening the architecture,
bringing the interactive experience up to modern expectations.

This is a principled effort. Part of that is understanding the interpreter's
own structure deeply enough to modify it confidently. The execution engine
has two modes (value and computation) with boundary crossings that require
state discipline — a pattern that sequent calculus and polarized type theory
give precise vocabulary for. That analysis found bugs ([001], [002], [003])
before users did, and it informs every architectural decision going forward.
See [SPEC.md](SPEC.md) for the full theoretical treatment.

But the theory is one component alongside others: Unix design philosophy,
POSIX fidelity, security-first engineering, and a practical focus on what
shell users actually need. See [COMPARISON.md](COMPARISON.md) for the
feature vision.

[001]: ../bugs/001-typeset-compound-assoc-expansion.ksh
[002]: ../bugs/002-typeset-debug-trap-compound-assign.ksh
[003]: ../bugs/003-debug-trap-self-unset.ksh


## Roadmap

The foundations section (nine items below) established the engineering
base: polarity frames, prefix guards, scope unification, longjmp safety.

The modernization section covers the remaining work. Done so far:
- **C23 type enforcement** — typed enums, constexpr, static_assert, [[noreturn]], nullptr (**done**)
- **Library reduction** — strip dead libraries and thin survivors (**done**)
- **Platform targeting** — declare what we support, delete the rest (**done**)
- **Security hardening** — audit the reduced codebase (**done**)
- **Build system** — just + samu, retire MAM (**done**)

Remaining:
- **sfio reimplementation** — clean-room rewrite, polarity-structured (architecture documented)
- **Unicode via utf8proc** — grapheme-correct terminal handling

After that: interactive features (completions, autosuggestions, editor
hooks) on a codebase that's small enough to audit and typed enough to
extend confidently.


## The polarity frame API

The central abstraction. A `struct sh_polarity` captures the interpreter
state that must be saved when crossing from value mode into computation mode
(trap dispatch, discipline functions, environment lookups).

### Definition (shell.h)

```c
struct sh_polarity
{
    char        *prefix;    /* saved sh.prefix */
    Namval_t    *namespace; /* saved sh.namespace */
    struct sh_scoped st;    /* saved sh.st */
    Dt_t        *var_tree;  /* saved sh.var_tree */
};
```

### Operations (xec.c, declared in defs.h)

```c
void sh_polarity_enter(struct sh_polarity *frame);
void sh_polarity_leave(struct sh_polarity *frame);
```

`sh_polarity_enter` saves `sh.prefix`, `sh.namespace`, `sh.st`, and
`sh.var_tree`, then clears `prefix` and `namespace`. Computation-mode
code runs in a clean context.

`sh_polarity_leave` restores the saved state, but with a critical
refinement: it snapshots all live trap slots *before* restoring `sh.st`,
then writes them back after. This prevents handler-side trap mutations
(e.g. `trap - DEBUG`) from being silently overwritten by the restore.

### Why `sh.st` and not just `sh.prefix`

The full `sh_scoped` struct (~170 bytes) is more than just the prefix — it
includes trap pointers, loop counters, line numbers, and other scoped state.
Trap handlers and discipline functions can mutate any of these. Saving only
`prefix` (as the original `sh_fun` did) leaves the rest exposed. The frame
copies the full struct so that computation-mode code can't corrupt any of it.

The cost is a struct copy on each boundary crossing. For the call sites that
use this — DEBUG trap dispatch, discipline calls, `getenv`/`putenv` — this
is not in the hot path.


## Converted call sites

These functions previously did ad-hoc save/restore of some combination of
`sh.prefix`, `sh.namespace`, and `sh.st`. They now use the polarity frame.

| Function | File | What changed |
|----------|------|--------------|
| `sh_debug()` | xec.c | Was: manual `savprefix` + `*savst` + inline trap slot preservation. Now: lightweight polarity frame (`sh_polarity_lite_enter`/`leave`). Trap dup for use-after-free protection retained separately. |
| `sh_trap()` | fault.c | Was: conditional polarity frame (`use_polframe = !sh.indebug` guard). Now: unconditional full polarity frame after `var_tree` was added to frame (context frames resolution). |
| `sh_fun()` | xec.c | Was: saved only `sh.prefix`. Now: full polarity frame (saves `sh.st` too). Documented behavioral change in `notes/divergences/001-sh-fun-st-save.md`. |
| `sh_getenv()` | name.c | Was: ad-hoc `savns`/`savpr`. Now: polarity frame. |
| `putenv()` | name.c | Was: ad-hoc `savns`/`savpr`. Now: polarity frame. |
| `sh_setenviron()` | name.c | Was: ad-hoc `savns`/`savpr`. Now: polarity frame. |

### Callers that don't need polarity frames

Not every save/restore site is a polarity boundary. The remaining sites
are handled by their own sections:

**Within-value prefix management** — now converted to
`sh_prefix_enter`/`sh_prefix_leave`. See [Prefix isolation](#within-value-prefix-isolation).

**Scope management** — annotated with their classification.
See [Polarity frames at continuation boundaries](#polarity-frames-at-continuation-boundaries).


## sh_exec polarity taxonomy

All 16 `case` labels in `sh_exec()` (xec.c) are annotated with their
polarity classification:

| Classification | Node types |
|----------------|------------|
| **Value** (producers) | `TARITH`, `TSW`, `TTST` |
| **Computation** (consumers/statements) | `TFORK`, `TPAR`, `TFIL`, `TLST`, `TAND`, `TORF`, `TIF`, `TTIME` |
| **Mixed** (internal polarity boundaries) | `TCOM`, `TFOR`, `TWH`, `TSETIO`, `TFUN` |

The mixed cases are the interesting ones — they contain both value and
computation sub-operations. `TCOM` has assignments (value) and command
execution (computation). `TFOR` has loop variable binding (value) and loop
body (computation). `TFUN` has symbol table registration (value) and
namespace body execution (computation).

The `sh_node_polarity[]` constexpr table in shnodes.h encodes this
classification. Index with `tretyp & COMMSK`.


## Regression tests

| Test | File | What it covers |
|------|------|----------------|
| `trap - DEBUG` self-removal | basic.sh:1139 | Handler removes its own trap; must persist after `sh_polarity_leave` restores `sh.st` |
| Namespace + DEBUG trap | basic.sh:1149 | Namespace variable set while DEBUG trap active inside namespace block; verifies namespace context survives polarity boundary |
| ERR trap during compound assignment | basic.sh:1159 | `sh.prefix` must not leak into ERR trap handler (polarity boundary) |
| Trap sets new trap in handler | basic.sh:1172 | `trapdontexec` must survive polarity frame restore (polarity boundary) |
| Compound assignment + macro expansion | basic.sh:1183 | Prefix guard preserves context across `sh_mactrim` (prefix isolation) |
| Nested compound-associative assignment | basic.sh:1191 | Prefix guard handles nested subscript resolution (prefix isolation) |


## Error conventions (⊕/⅋ duality)

ksh93 has two error-handling conventions that coexist throughout the
interpreter. They are duals in the sequent calculus sense (SPEC.md §⊕/⅋):

- **⊕ (exit status)**: a command returns a status code; the *caller*
  decides what to do. Like `Result<T,E>` — data that gets pattern-matched.
- **⅋ (trap/continuation)**: on error, the *callee* invokes a handler
  registered by the caller. Like passing `onSuccess`/`onFailure` callbacks.

`set -e` (errexit) is the bridge: it converts ⊕ into ⅋ by automatically
invoking the ERR trap (or exiting) when a command returns nonzero.

### Function convention table

| Function | Convention | Mechanism |
|----------|-----------|-----------|
| `sh_exec()` | ⊕ return + ⅋ dispatch | Returns `sh.exitval`; calls `sh_chktrap()` at fault.c:397 |
| `sh_trap()` | ⊕ return | Returns handler's exit status; restores caller's `sh.exitval` |
| `sh_chktrap()` | ⅋ dispatch | ERR trap → `sh_exit()` longjmp if errexit option on |
| `sh_debug()` | ⊕ return | Returns trap status (2 = skip command) |
| `sh_fun()` | ⊕ return | Returns `sh.exitval` after polarity frame leave |
| `sh_funscope()` | ⊕ return | Returns r (from `sh.exitval` or jmpval) |
| `sh_eval()` | ⊕ return | Returns `sh.exitval` |
| `sh_exit()` | ⅋ longjmp | `siglongjmp` to `sh.jmplist` |
| `sh_done()` | ⅋ terminal | Runs EXIT trap, terminates process |
| `sh_fault()` | ⅋ deferred | Sets `sh.trapnote` flags; trap runs later at safe point |
| `b_return()` | ⅋ longjmp | Converts exit status to `SH_JMPFUN`/`SH_JMPEXIT` jump |
| `nv_open()` | ⅋ longjmp | `ERROR_exit()` on failure (no ⊕ return path) |
| builtins (`b_*`) | ⊕ return | Return int exit code; `sh_exec` captures in `sh.exitval` |

### The errexit bridge (⊕→⅋ conversion)

The state/option split:
- `sh_isstate(SH_ERREXIT)` — transient, suppressed in conditionals
- `sh_isoption(SH_ERREXIT)` — persistent `set -e`

Suppression: `&&`, `||`, `if`/`while` condition, `!` — these pass
`flags & ARG_OPTIMIZE` without `sh_state(SH_ERREXIT)` to recursive
`sh_exec()`, which clears the state at xec.c:925.

`skipexitset` (xec.c:881): prevents `exitset()` from committing to `$?`
in contexts where it shouldn't (test expressions inside conditionals).

`echeck`: gates whether `sh_chktrap()` runs after a construct.

### Dual-channel exit status flow

```
sh.exitval (transient, per-command)
    → sh.savexit (stable, $?) via exitset()
    → sh_chktrap() check at xec.c:2643
```

### Longjmp mode taxonomy

The `SH_JMP*` constants (fault.h) are ordered by severity. Higher values
propagate further up the continuation stack. The split between locally-caught
(⊕) and propagating (⅋) modes is at `SH_JMPFUN` (7) — see fault.h for the
full classified table.


## Divergence from dev

When a bugfix lands on `dev` and ksh26 handles it differently, the
situation is documented in `notes/divergences/`:

| # | File | Summary |
|---|------|---------|
| 001 | `001-sh-fun-st-save.md` | `sh_fun` now saves full `sh.st`, not just prefix |
| 002 | `002-debug-trap-self-unset.md` | Trap preservation in frame API vs dev's inline fix |


## Foundations

Progress against the refactoring directions from
[SPEC.md §Concrete directions](SPEC.md#concrete-directions):

### Context frames instead of global mutation

**Status: done**

The polarity frame API is implemented and in use at 6 call sites
(sh_debug, sh_fun, sh_getenv, putenv, sh_setenviron, sh_trap).
`sh.prefix`, `sh.namespace`, `sh.var_tree`, and `sh.st` are covered.
Trap slot and `trapdontexec` preservation handled uniformly by
`sh_polarity_leave`.

**Resolved evaluations:**
- `sh.var_tree` — **yes, added to the frame.** ksh93 encodes scope in two
  mutable fields (`sh.st` containing `own_tree`, and `sh.var_tree`) that must
  stay synchronized. `sh_setscope()` is the only function that updates both
  atomically; everything else (sh_scope, sh_funscope exit, sh_polarity_leave,
  sh_subshell) updates them independently. Without var_tree in the polarity
  frame, double-framing (sh_trap inside sh_debug) caused a SIGBUS: the inner
  frame's `sh.st` restore desynchronized `own_tree` from `sh.var_tree`.
  The workaround (`use_polframe = !sh.indebug` in sh_trap) has been removed
  now that the polarity frame keeps both halves of the scope representation
  in sync.

  **Type system note:** `Shscope_t` (public, shell.h) has field `var_tree`
  at the same offset where `struct sh_scoped` (private) has `own_tree`.
  When `sh_setscope` does `scope->var_tree`, it reads `own_tree` through
  the public interface. Both names now mean "this scope's variable tree."

  **Rename: `save_tree` → `own_tree`** — The original name `save_tree`
  suggested entry perspective ("the tree we saved on entry"), but every
  access site uses it as identity perspective ("this scope's own tree"):
  `sh.st.own_tree = sh.var_tree` after `sh_scope`, `prevscope->own_tree`
  for the parent's tree, restore via `sh.var_tree = prevscope->own_tree`.
  The rename eliminates the semantic gap between the public alias
  (`var_tree`) and the private field. The old comment ("var_tree for
  calling function") was also wrong — at xec.c:3051 it's set to the
  *current* function's tree.

  **Invariant:** `sh.var_tree == sh.st.own_tree` at stable points
  (outside scope transitions). `sh_setscope` is the only function that
  updates both atomically; all other sites (`sh_scope`, `sh_funscope`
  exit, `sh_polarity_leave`, `sh_subshell`) update them independently.

  Note: nvtree.c has a local variable `Dt_t *save_tree = sh.var_tree`
  in `walk_tree`. This is an RAII-style local save, not the struct field
  — the name is appropriate there and was not renamed.

- `sh.jmplist` — **no.** Already managed by `sh_pushcontext`/`sh_popcontext`,
  which pair correctly at each call site. The polarity frame would add
  redundant save/restore without fixing any real desync.

### sh_exec polarity classification

**Status: done**

All 16 case labels annotated. Block comment with taxonomy added. No further
code changes planned unless the taxonomy needs revision.

### Within-value prefix isolation

**Status: done**

The 5 within-value prefix management sites are converted to use the
`sh_prefix_enter`/`sh_prefix_leave` API. A 6th site (`nv_newattr`) does a
defensive save without clearing and is annotated but not converted.

#### Prefix guard API

`struct sh_prefix_guard` (shell.h) saves 3 fields: `sh.prefix`,
`sh.prefix_root`, and `sh.first_root`. `sh_prefix_enter` saves and clears
`sh.prefix`; `sh_prefix_leave` restores all three.

This is deliberately lighter than a polarity frame (no `sh.st` save). These
sites stay within value mode — they just prevent inner name resolution from
inheriting the outer compound assignment context.

Why `prefix_root` and `first_root`: they're companion fields to `sh.prefix`.
When prefix is null, both are cleared (name.c:286). `prefix_root` is set
from `first_root` during name resolution (name.c:498-499). Saving only
prefix would leave stale root pointers.

#### Converted sites

| # | File:function | Operation guarded |
|---|---------------|-------------------|
| 1 | name.c:`nv_setlist` | sh_mactrim (macro expansion of assignment value) |
| 2 | name.c:`nv_setlist` | nv_open (nested array subscript resolution) |
| 3 | name.c:`nv_open` | nv_putval (value assignment with NV_STATIC check) |
| 4 | name.c:`nv_rename` | nv_open (compound ref resolution, two calls) |
| 5 | xec.c:`sh_exec` (TFUN) | nv_open (discipline function lookup) |

#### Not converted

`nv_newattr` (name.c) does `char *prefix = sh.prefix` without clearing —
a defensive save across attribute change, not a guard. Annotated only.

#### Longjmp risk

Sites 2 and 4 call `nv_open()` which can `ERROR_exit()` (longjmp). The
guard doesn't make this worse: if nv_open longjmps, the unwinding lands at
a computation-mode checkpt that manages its own state. The prefix stays
cleared across the longjmp, same as the original inline code.

### Polarity frames at continuation boundaries

**Status: done**

All 27 `sh_pushcontext` sites are classified. Only one needed a polarity
frame added: `sh_trap()` in fault.c. Embedding `struct sh_polarity` in
`struct checkpt` was evaluated and rejected: ~200 bytes overhead at 27
sites for a benefit at 3 (sh_debug, sh_fun, sh_trap). Sites that need
polarity declare it locally.

**trapdontexec preservation fix:** `sh_polarity_leave` now preserves
`sh.st.trapdontexec` across the `sh.st` restore, matching the existing
trap slot preservation. Without this, a trap handler that sets a new trap
(incrementing trapdontexec at trap.c:199) would have the change silently
reverted by the blanket struct restore. Affects all polarity frame callers.

**sh_trap conversion:** sh_trap runs signal/ERR/EXIT trap handlers. When
called during compound assignment, `sh.prefix` was leaking into handlers.
The polarity frame prevents this. Nesting order: stk (outermost) →
polarity (middle) → continuation (innermost).

The polarity frame was initially conditional (`use_polframe =
!sh.indebug`) to avoid double-framing desync when sh_trap is called
from sh_debug. The issue: `sh.var_tree` and `sh.st` encode the same
scope in two places, and a polarity frame that saved only `sh.st`
would desynchronize them on the inner restore. Once `sh.var_tree` was
added to the polarity frame (context frames resolution), double-framing
became safe and the conditional was removed. The frame is now
unconditional.

#### Continuation frame polarity classification

| Site | File | Type | Classification |
|------|------|------|----------------|
| `sh_init` | init.c | SH_JMPSCRIPT | computation-only |
| `exfile` | main.c | SH_JMPERREXIT | computation-only |
| `sh_mactry` | macro.c | SH_JMPSUB | computation-only |
| `sh_mactrim` ($(<file)) | macro.c | SH_JMPIO | computation-only |
| `parse_function` | parse.c | 1 | computation-only |
| `sh_eval` | xec.c | SH_JMPEVAL | computation-only |
| `sh_exec` (TCOM assign) | xec.c | SH_JMPCMD | computation-only |
| `sh_exec` (TCOM builtin) | xec.c | SH_JMPCMD | computation-only |
| `sh_exec` (TCOM I/O) | xec.c | SH_JMPIO | computation-only |
| `sh_exec` (TFORK child) | xec.c | SH_JMPEXIT | computation-only |
| `sh_exec` (TFORK I/O) | xec.c | SH_JMPIO | computation-only |
| `sh_exec` (TPAR) | xec.c | SH_JMPEXIT | computation-only |
| `sh_exec` (TFOR opt) | xec.c | inherited | computation-only |
| `sh_exec` (TWH opt) | xec.c | inherited | computation-only |
| `sh_exec` (TFUN ns) | xec.c | SH_JMPCMD | computation-only |
| `sh_funct` | xec.c | SH_JMPFUN | scope boundary |
| `sh_fun` | xec.c | SH_JMPFUN/CMD | **polarity boundary** |
| `sh_ntfork` | xec.c | SH_JMPCMD | computation-only |
| `sh_debug` | xec.c | (none) | **polarity boundary** |
| `sh_trap` | fault.c | SH_JMPTRAP | **polarity boundary** |
| `sh_subshell` | subshell.c | SH_JMPSUB | scope boundary |
| `sh_funscope` | xec.c | SH_JMPFUN | scope boundary |
| `nv_setdisc` (APPEND) | nvdisc.c | SH_JMPFUN | indirect (sh_fun) |
| `nv_setdisc` (LOOKUPN) | nvdisc.c | SH_JMPFUN | indirect (sh_fun) |
| `sh_timetraps` | alarm.c | SH_JMPTRAP | indirect (sh_fun) |
| `b_dot_cmd` | misc.c | SH_JMPDOT | scope boundary |
| `b_read` | read.c | 1 | computation-only |
| `b_getopts` | getopts.c | 1 | computation-only |
| `b_typeset` | typeset.c | 1 | computation-only |

**polarity boundary**: has a `struct sh_polarity` frame (saves `sh.prefix`,
`sh.namespace`, `sh.st`). These are the value→computation boundary crossings.

**scope boundary**: does full custom `sh.st` management (save/restore via
local variable). Too intertwined with scope chain setup to use a polarity
frame directly.

**indirect**: wraps a call to `sh_fun`, which has its own polarity frame.

**computation-only**: no value→computation boundary crossing. Error recovery,
I/O setup, loop optimization, or child process management within computation
mode.

### Error convention duality

**Status: done**

Function convention table, errexit bridge analysis, and longjmp mode
taxonomy documented in [Error conventions](#error-conventions-⊕⅋-duality)
above. Inline annotations added to fault.h (longjmp mode block comment),
fault.c (`sh_chktrap`, `sh_trap`, `sh_exit`), xec.c (errexit suppression,
`skipexitset`, central dispatch), and cflow.c (`b_return`).

### Stack allocator boundaries

**Status: done**

The stk boundaries are already well-aligned at polarity boundary sites.
Documentation added; no functional code changes.

#### Three-layer nesting convention

At polarity boundary sites, three layers nest in a fixed order:

1. **stk** (outermost): `stkfreeze` / `stkset` bracket the entire operation
2. **polarity** (middle): `sh_polarity_enter` / `sh_polarity_leave`
3. **continuation** (innermost): `sh_pushcontext` / `sh_popcontext`

This ordering is structurally required: stk must be outermost because if a
longjmp unwinds past `sh_polarity_leave`, the stk restore in the sigsetjmp
recovery path handles cleanup. If polarity were outermost, the stk state
could point to freed memory after the polarity frame restored a different
base pointer.

#### Boundary site coverage

| Site | stk | polarity | continuation | Notes |
|------|-----|----------|--------------|-------|
| `sh_debug` | stkfreeze/stkset | sh_polarity_enter/leave | (none) | No inner checkpt; uses sh_trap which has its own |
| `sh_fun` | stkfreeze/stkset | sh_polarity_enter/leave | sh_pushcontext | All three layers |
| `sh_trap` | stkfreeze/stkset | sh_polarity_enter/leave | sh_pushcontext | All three layers |

#### Why stk is NOT in the polarity frame

Different callers have different stk lifetime requirements. `sh_debug`
freezes before building the `.sh.command` string on the stack. `sh_fun`
conditionally freezes only if `stktell > 0`. `sh_trap` always freezes.
Embedding stk in the polarity frame would force a single policy.

#### ARG_OPTIMIZE exception

`sh_exec` (xec.c TCOM) suppresses stk restore when `ARG_OPTIMIZE` is set.
This is intentional: loop body allocations persist for the optimizer. Not
a leak — the optimizer manages its own stk lifetime.


### Safe optimizations

**Status: done**

The polarity boundary framework (context frames through allocator boundaries) makes three optimizations
provably safe that would have been risky in the ad-hoc codebase. Each
eliminates redundant work on hot paths without changing observable behavior.

#### 7a: Empty DEBUG trap early exit

`sh_debug` is called on every command when a DEBUG trap is set. When the
trap string is empty (`trap '' DEBUG`), it previously built the entire
`.sh.command` string, entered a full polarity frame, allocated a trap
duplicate, and called `sh_trap` — all for a no-op.

In the sequent calculus framing, an empty trap body means the cut between
the current command (value) and the trap handler (computation) reduces to
identity. No polarity boundary crossing occurs, so the frame, continuation,
and string construction are pure overhead.

The fix adds `if(!*trap) return 0;` after the re-entrancy guard. `trap` is
always non-NULL here (callers gate on `sh.st.trap[SH_DEBUGTRAP]`), and the
`stkfreeze(sh.stk,0)` at the top is a read-only snapshot (arg 0 = no
mutation), so early return needs no cleanup.

**File:** `xec.c` `sh_debug`, after the `sh.indebug` guard.

#### 7b: Lightweight polarity frame (sh_polarity_lite)

`sh_debug` and `sh_trap` create nested polarity frames:

```
caller → sh_debug frame → sh_trap frame → handler → sh_trap leave → sh_debug leave
```

`sh_trap`'s inner frame already does a full `sh.st` save/restore (~184
bytes on arm64). The outer frame's full `sh.st` copy is therefore redundant
— `sh_debug`'s own operations (lines between enter/leave) only modify
`sh.prefix` and `sh.namespace`.

**Weakened outer boundary principle:** when nested cuts already provide the
structural guarantee, the outer cut can save only the fields it personally
modifies plus the fields the handler is allowed to mutate through the inner
boundary.

`struct sh_polarity_lite` (~56 bytes) replaces `struct sh_polarity` (~208
bytes) in `sh_debug`, saving:

| Field | Why saved |
|-------|-----------|
| `prefix` | sh_debug clears to NULL |
| `namespace` | sh_debug clears to NULL |
| `var_tree` | scope consistency across boundary |
| `trap[]` | handler may mutate (e.g. `trap - DEBUG`) |
| `trapdontexec` | handler may set new traps |

Everything else in `sh.st` is invariant across `sh_debug`'s own code and
protected by `sh_trap`'s full frame.

`update_sh_level()` is reordered to run after `sh_polarity_lite_leave()`,
since the scope checkpoint should happen after the caller's context is
restored.

**Files:** `shell.h` (struct), `xec.c` (enter/leave functions + sh_debug).

#### 7c: Scope dictionary pool

Every function call allocates a CDT dictionary via `dtopen` in `sh_scope`
and frees it via `dtclose` in `sh_unscope`. Function scopes are strictly
LIFO, so a fixed-size pool (8 entries) amortizes the malloc/free cost.

In the sequent calculus, scope creation/destruction corresponds to
structural rules (introducing/eliminating variable binding contexts).
The logical structure requires the scope to exist with proper identity
and viewpath linkage, but not that the physical memory be freshly
allocated. The pool separates logical lifetime (scope enter/leave) from
physical lifetime (allocate/free).

`sh_scope_acquire()` pops from the pool (or falls back to `dtopen`).
`sh_scope_release()` calls `dtclear()` and pushes to the pool (or falls
back to `dtclose` when full). `table_unset` in `sh_unscope` already
empties the dict's logical contents; `dtclear` resets CDT's internal
bookkeeping for safe reuse.

**File:** `name.c` (pool + acquire/release + sh_scope/sh_unscope updates).

#### Boundary site coverage (updated)

| Site | stk | polarity | continuation | Notes |
|------|-----|----------|--------------|-------|
| `sh_debug` | stkfreeze/stkset | **sh_polarity_lite** | (none) | Lite frame; sh_trap provides full sh.st protection |
| `sh_fun` | stkfreeze/stkset | sh_polarity_enter/leave | sh_pushcontext | All three layers |
| `sh_trap` | stkfreeze/stkset | sh_polarity_enter/leave | sh_pushcontext | All three layers |
| `nv_setlist` | (none) | (none) | **sh_exit guard** | Longjmp safety: L_ARGNOD guard |


### Compound assignment longjmp safety

**Status: done (v2 — sh_exit guard)**

`nv_setlist` (name.c) handles compound assignment by temporarily mutating
the global `L_ARGNOD` to act as a nameref pointing to a stack-local
`struct Namref nr`. It then calls `sh_exec` to evaluate the assignment
body. If `sh_exec` longjmps (e.g., read-only variable error), `L_ARGNOD`
retains `nvalue = &nr` — a dangling pointer to unwound stack memory.

In the sequent calculus framing, `sh_exec` inside `nv_setlist` is a cut
between a value context (the assignment target being configured) and a
computation context (the assignment body being evaluated). The temporary
`L_ARGNOD` mutation is a substitution that must be unwound regardless of
how the computation terminates.

**v1 (abandoned): checkpoint approach.** Wrapping `sh_exec` in a
`sh_pushcontext`/`sh_popcontext` checkpoint (SH_JMPCMD) changed the error
propagation *topology* — errors that previously landed at an outer handler
were now caught by the inner checkpoint. This caused 13 test regressions
(enum.sh, types.sh, pointtype.sh, io.sh). The problem is structural:
inserting a new handler changes where every longjmp in the subtree lands,
not just the ones we care about. No amount of "rethrow if severity >
threshold" can fix this, because the catch-and-rethrow itself changes
observable behavior (e.g., cleanup code runs at a different point).

**v2 (implemented): sh_exit guard.** Instead of adding a handler, we
register the L_ARGNOD restore in `sh_exit()` (fault.c) — the single
funnel that ALL error paths pass through before longjmping. This adds no
checkpoint, changes no topology. The error propagation chain stays exactly
as it was; L_ARGNOD is simply cleaned up as a side effect of sh_exit,
alongside `sh.prefix`, `sh.mktype`, etc.

Implementation:
1. `shell.h`: `argnod_guard` struct in `Shell_t` (nvalue, nvflag, nvfun)
2. `name.c`: save L_ARGNOD fields to guard before mutation, clear after
   normal restore
3. `fault.c`: in `sh_exit`, if guard is active, restore L_ARGNOD fields
   (placed next to `sh.prefix = 0`)

**Files:** `shell.h` (Shell_t), `name.c` (nv_setlist), `fault.c` (sh_exit)


### Scope representation unification

**Status: done (second pass)**

`sh.var_tree` and `sh.st.own_tree` encode the same concept: the current
scope dictionary. Only `sh_setscope` updates both atomically. Three sites
change scope identity without syncing `own_tree`, creating windows where
the two fields disagree:

| Site | Function | What happens |
|------|----------|-------------|
| `sh_scope` (name.c) | New scope installed | `sh.var_tree = newscope` without `own_tree` |
| `sh_unscope` (name.c) | Parent scope restored | `sh.var_tree = dp` without `own_tree` |
| `sh_funscope` (xec.c) | Caller scope restored | `sh.var_tree = prevscope->own_tree` without `own_tree` |

In the duploid framework, these are structural rules (context
introduction/elimination). The scope dictionary is part of the evaluation
context, and installing or removing a scope is a substitution that
affects both the variable lookup path (`sh.var_tree` via CDT viewpath)
and the interpreter's understanding of "where am I" (`sh.st.own_tree`).
When these diverge, operations that consult `own_tree` (e.g., scope
level detection in `update_sh_level`) see stale identity.

**First pass** added `sh.st.own_tree = <new value>` immediately after each
identity-changing `sh.var_tree` assignment. Sites that temporarily
navigate the viewpath chain (NV_GLOBAL lookups, nv_clone switches,
namespace manipulation) are *not* synced — they don't change scope
identity.

**Second pass** introduced `sh_scope_set()` (defs.h), a static inline
function that atomically updates both fields:

```c
static inline void sh_scope_set(Dt_t *tree)
{
    sh.var_tree = tree;
    sh.st.own_tree = tree;
}
```

The three first-pass sync sites now call `sh_scope_set()` instead of
writing two separate assignments. This makes the invariant
self-enforcing: new scope-changing code uses the setter rather than
remembering to update both fields manually. The one-time initialization
in `init.c` (`sh.var_base = sh.var_tree = sh_inittree(...)`) does not
use the setter — it runs before the scope stack exists.

**Files:** `defs.h` (`sh_scope_set`), `name.c` (`sh_scope`,
`sh_unscope`), `xec.c` (`sh_funscope`).


## Modernization

### C23 type enforcement

**Status: done**

Adopted C23 dialect (GCC 14+ / Clang 18+) across the codebase. Key changes:
typed enums via `enum : type`, `constexpr` for compile-time tables (node
polarity classification, longjmp severity), `static_assert` for invariant
checking, `[[noreturn]]` replacing compiler-specific attributes, `nullptr`
for pointer contexts.

**Files:** Throughout. See commit history for the full changeset.


### Library reduction

**Status: done**

Removed ~4,500 lines of dead library code and thinned survivors to match
the actual build requirements. The binary size is unchanged (the linker
was already stripping dead objects from static archives), but the build
compiles 71 fewer objects (478 → 407 steps).

#### 11a: Dead libast subsystems

Deleted `libast/stdio/` (75 files — full stdio reimplementation on sfio,
zero call sites) and `libast/hash/` (15 files — pre-CDT hash table ADT,
superseded by libcdt). Two survivors (`strkey`, `strsum`) were relocated
to `libast/string/` where they semantically belong.

#### 11b: libdll

Deleted `src/lib/libdll/` (12 files). `SHOPT_DYNAMIC=0` means all dynamic
plugin loading is compiled out. Zero active call sites (all behind
`#if SHOPT_DYNAMIC`). Removed from configure.sh: feature tests, source
collection, compilation, link line. Vestigial `#include <dlldefs.h>` in
`cdtlib.h` removed (CDT uses none of its symbols).

#### 11c: libsum

Deleted `src/lib/libsum/` (11 files). AT&T checksum library (MD5, SHA,
CRC, BSD/AT&T sum). Only consumer was `cksum.c` in libcmd, which is not
in the static builtin set.

#### 11d: libcmd thinning

Reduced compiled sources from 47 to 11 files. Only the 9 static builtins
(basename, cat, cp, cut, dirname, getconf, ln, mktemp, mv) plus support
files (cmdinit.c, lib.c) are compiled. Remaining sources stay in tree
for future `builtin -f` if dynamic loading is re-enabled.

#### 11e: libast/comp thinning

Deleted 21 of 38 compatibility shims. Nine were pure NoN stubs (compile
to empty functions on modern systems). Twelve compiled to real code but
were never linked into the binary (the linker dropped them because
nothing called them). The 17 survivors are AST interceptors that route
standard library calls through AST-specific wrappers (conformance
checking, locale awareness, error catalogs) and are actively linked.

**Files:** `configure.sh` (source collection, feature tests, link line),
deleted directories, `cdtlib.h`.


### sfio reimplementation

**Status: architecture documented, implementation not started**

ksh26 inherits AT&T's sfio (Safe/Fast I/O) library — 78 files, ~12,800
LOC of buffered I/O built in the '90s as a stdio replacement. ~1000 sfio
call sites in ksh26 proper, ~800 in libast. ksh uses 39 of 77 exported
functions.

#### Previous approach (abandoned)

Three attempts at replacing sfio with stdio all failed. The v1 postmortem
(`notes/sfio-rewrite-failure-analysis.md`) identified the root cause:
sfio is not a library ksh uses — it's the semantic substrate. The buffer
IS the API (code does pointer arithmetic on `f->next`, `f->endb`,
`f->data`). FILE\* is opaque by design. The polarity analysis showed that
even positive-polarity operations (writes) are entangled with negative-
polarity buffer state through the LOCKR protocol. A dual-representation
approach would be worse than either approach alone.

All v1 infrastructure (sh_io.h abstraction, sh_strbuf.h, stdio backend,
conditional compilation) has been removed. main is rolled back to v0.0.1
+ cherry-picked build infrastructure. 115/115 tests pass.

#### Current approach: clean-room rewrite

Same API, same semantics, new code. Drop-in replacement for
`src/lib/libast/sfio/` — ~2,600 lines in 7 source files (+ headers)
instead of ~12,800 lines across 78 files.

Source files organized by duploid polarity role:

| File | Polarity role | Est. lines |
|------|---------------|------------|
| `sfmode.c` | Shift mediator (`_sfmode`, `sfsetbuf`, `sfclrlock`) | ~250 |
| `sfread.c` | Negative / consumers (`sfreserve`, `sfgetr`, `sfread`, `sfpkrd`) | ~500 |
| `sfwrite.c` | Positive / producers (`sfwrite`, `sfputr`, `sfnputc`) | ~350 |
| `sfdisc.c` | Interception (`sfdisc`, `_sfexcept`, `Dccache_t`) | ~200 |
| `sflife.c` | Cuts / lifecycle (`sfnew`, `sfopen`, `sfclose`, `sfstack`, `sfswap`, `sfsetfd_cloexec`, `sftmp`) | ~450 |
| `sfvprintf.c` | Positive + shift / format (`sfvprintf`, `%!` engine) | ~700 |
| `sfvle.c` | Neutral / encoding (`sfputl/sfgetl`, `sfputu/sfgetu`) | ~150 |

Targets POSIX Issue 8 fd primitives (pipe2, dup3, ppoll, posix_close,
mkostemp, O_CLOFORK) for race-free fd lifecycle. FILE\*-based Issue 8
primitives explicitly excluded.

See `notes/sfio-rewrite-v2.md` for the full proposal: polarity
architecture, contract details, elimination analysis, implementation
sequence, risk assessment.

**Build/test:** `just build-stdio` / `just test-stdio`

**What's implemented:**

| Category | Functions | Status |
|---|---|---|
| Stream lifecycle | sh_stream_init, sh_stream_new, sh_stream_close, sfnew, sfopen, sftmp | Working |
| Stream control | sfswap, sfsetfd, sfsetfd_cloexec, sfset, sfsetbuf, sfpool, sfpurge, sfclrlock | Working (sfpool is no-op) |
| Formatted output | sfprintf→fprintf, sfputc→fputc, sfwrite→fwrite, sfputr, sfnputc, sfprints, sfsprintf | Working (macros) |
| Read ops | sfgetc, sfread, sfreserve (LOCKR + non-LOCKR), sfgetr, sfmove | Working |
| Positioning | sfseek, sftell, sfsize | Working |
| Discipline | sfdisc (push/pop), sfraise, sfrd | Structural; needs event protocol |
| Stream stacking | sfstack (push/pop), sfstacked | Working |
| Raw fd ops | sfpkrd (poll+recv peek), sffileno | Working |
| Integer encoding | sfputu, sfputl, sfgetu, sfgetl | Working |
| String buffers | sfstropen, sfstrclose, sfstruse, sfstrseek, sfstrtell, sfstrbase, sfstrsize | Working (open_memstream) |
| Notifications | sfnotify | Working |
| Not implemented | sfpoll (1 call site, optional), sfkeyprintf (0 call sites) | N/A |

**Key design decisions:**

1. **Wrapper struct** — `sh_stream_t` wraps `FILE*` with metadata (fd,
   flags, val, disc chain, stack). Enables sfswap (memcpy-swap), sfvalue
   state tracking, discipline chains, and stream stacking without fighting
   stdio's opaque `FILE*`.

2. **sfreserve dual-mode consumption** — sfio's sfreserve has two caller
   contracts that map to the polarity framework:

   - **LOCKR mode (μ-binding / context capture)**: Buffer is bound into a
     continuation context. Caller reads directly, releases explicitly via
     `sfread(f,buf,0)`. Data persists across sfreserve calls.
   - **Non-LOCKR mode (μ̃-binding / let)**: Buffer is a produced value.
     Consumed on return; next sfreserve reads fresh from FILE*.

   The implementation marks this via `f->data`: LOCKR preserves it;
   non-LOCKR clears it to NULL after returning the pointer. Prevents the
   infinite loop where non-LOCKR callers (macro.c) saw stale data.

3. **sfswap SFIO_STATIC preservation** — SFIO_STATIC tracks struct
   *identity* (is this address a global?), not content. `sfswap(f, NULL)`
   clears SFIO_STATIC on the heap copy; two-arg swap preserves each
   struct's original static flag regardless of swapped content.

4. **`_ksh_` prefixed globals** — sfstdin/sfstdout/sfstderr are real
   pointer variables (not macros) because subshell.c reassigns them.
   Prefixed `_ksh_` to avoid linker collision with libast's sfextern.c.

**Remaining 79 test failures** — concentrated in polarity-boundary paths:

| Failure class | Likely cause | Where |
|---|---|---|
| Here-docs/here-strings | sftmp+sfseek+sfmove chain (positive→cut→negative) | io.c heredoc setup |
| I/O redirections | sfnew/sfsetfd without FILE* properly initialized | io.c sh_iorenumber |
| Discipline callbacks | sfdisc event protocol (DPUSH/DPOP/DBUFFER) incomplete | io.c discipline defs |
| Pipe in subshell | Stream state after fork — FILE* buffers not synced | subshell.c, jobs.c |
| Edit/interactive | sfpkrd + sfreserve interaction on tty fds | edit/*.c |

#### Replacement roadmap

| sfio feature | Sites | Replacement | Status |
|---|---|---|---|
| Formatted I/O (sfprintf, sfwrite, etc.) | ~670 | stdio (fprintf, fwrite) | **Done** (macros) |
| String streams (sfstropen/sfstruse) | ~40 | `open_memstream()` (POSIX 2008) | **Done** (sh_strbuf) |
| Temp streams (sftmp) | 9 | `tmpfile()` | **Done** |
| Standard streams (sfstdin/out/err) | ~350 | sh_stream_t pointer vars | **Done** |
| Zero-copy reserve (sfreserve) | 21 | Custom buffer + LOCKR protocol | **Done** |
| Stream stacking (sfstack) | 8 | Linked list on sh_stream_t | **Done** |
| Disciplines (sfdisc) | 12 | Push/pop chain on sh_stream_t | Structural, needs events |
| Stream pools (sfpool) | 13 | No-op (stdio self-buffers) | Sufficient for now |

**Net: delete ~11.5k lines of sfio, add ~1200 lines of custom code.**
(Estimate revised upward from 500 — sfreserve, sfgetr, sfpkrd, and
integer encoding were more complex than "custom buffer peek".)

#### Other libast subsystems

| Subsystem | Sites | Status | Rationale |
|---|---|---|---|
| **stk** (stack allocator) | 273 | Decoupled (Phase 3) | `Stk_t` is now a real 24-byte struct, 0 sfio symbols. |
| **cdt** (containers) | 85 | Keep | `dtview()` scope chaining is shell-specific. ~4k lines, stable. |
| **AST regex** | — | Keep | Working, tested. PCRE2 migration deferred. |

#### Remaining phases

```
Phase 6: Fix the 79 remaining stdio test failures
         - FILE* lifecycle (sfnew/sfsetfd/_sh_ensure_fp)
         - Discipline event protocol (DPUSH/DPOP/DBUFFER)
         - Here-doc I/O path (sftmp+sfseek+sfmove chain)
         - Fork buffer sync (fflush before fork)

Phase 7: Parity — stdio build passes 115/115
         - Edit/interactive paths (sfpkrd+sfreserve on tty)
         - Edge cases from full test suite

Phase 8: Remove sfio from build
         - Delete libast/sfio/ (80 files, ~11.5k LOC)
         - Remove KSH_IO_SFIO conditional compilation
         - sh_io.h becomes the only I/O header
         - Update configure.sh, build.ninja generation

Phase 9: Post-sfio cleanup
         - Typed error handling (Result_t, notes/FUTURE.md)
         - Unicode — utf8proc integration
```


### Platform targeting

**Status: done**

Cleaned iffe feature probes for dead platforms:

- Deleted `features/omitted` (Windows .exe botch tests) and its
  configure.sh reference
- Stripped QNX and Cygwin branches from `features/standards`
- Reduced `features/aso` from 634 → 52 lines: kept GCC `__sync_*`
  builtins, removed Solaris `<atomic.h>` (6 variants), Windows
  `Interlocked*`, AIX `fetch_and_add`, MIPS, x86/ia64/ppc inline asm
- Removed HP-UX `pstat` probe and NeXT `nc.h` include from ksh26
  features/externs and main.c
- `features/signal.c` audited — clean (all `#ifdef`-guarded, no dead
  branches)
- Platform tiers documented in README

cc.* compiler profiles were already eliminated (library reduction).


### Security hardening

**Status: done**

Two targeted fixes plus documentation:

1. **Signal handler malloc removed** (`fault.c`): `sh_fault()` called
   `malloc(1)` to test heap availability before crash cleanup —
   not async-signal-safe, can deadlock. Removed; always attempt
   `sh_done()` for abort-class signals.
2. **Integer overflow guard** (`streval.c`): Added `SIZE_MAX` overflow
   check on `staksize * (sizeof(Sfdouble_t) + 1)` before `stkalloc`.
   Defense-in-depth (staksize is a `short`, bounded by expression
   complexity).
3. **Audit documented** in `notes/security/audit-2026-02.md`: stack
   buffers clean, format strings all literal, strcpy usage audited
   (22 occurrences, all pre-sized).


### Build system

**Status: done**

Replaced the MAM (Make Abstract Machine) build infrastructure with a
three-layer system: just (porcelain) → configure.sh (probes + generates
build.ninja) → samu (vendored ninja). Full test suite (115 tests) passes.

Build dependencies (utf8proc, scdoc) are detected at configure time:
system versions preferred, with git-clone fallback into `build/deps/`.
Nix flake provides these via `buildInputs` so the flake build path never
needs the fallback.

Man pages `shell.3` and `nval.3` converted from troff to scdoc format
in `doc/`. The `just doc` recipe processes `doc/*.scd` into
`build/$HOSTTYPE/man/`. The main man page `sh.1` (9,723 lines of
troff) is deferred to a dedicated session.


### Unicode via utf8proc

**Status: planned**

147 multibyte/wide-char call sites across 29 files. After library
reduction and sfio abstraction.

1. Write `sh_unicode.h` wrapping utf8proc: `sh_wcwidth()`,
   `sh_grapheme_next()`, `sh_utf8_decode()` / `sh_utf8_encode()`
2. Convert line editor (`edit/edit.c`, `edit/vi.c`, `edit/emacs.c`) —
   highest value, fixes emoji and CJK cursor positioning
3. Convert remaining call sites (pattern matching, `chresc()`)

utf8proc build dep infrastructure is in place (build system).


## References

1. Arnaud Spiwack. "A Dissection of L." 2014.
2. Éléonore Mangel, Paul-André Melliès, and Guillaume Munch-Maccagnoni.
   "Classical notions of computation and the Hasegawa-Thielecke theorem."
   *POPL*, 2026.
3. Guillaume Munch-Maccagnoni. "Syntax and Models of a non-Associative
   Composition of Programs and Proofs." PhD thesis, Paris 7, 2013.
4. Paul Blain Levy. *Call-by-Push-Value.* Springer, 2004.
5. Pierre-Louis Curien and Hugo Herbelin. "The duality of computation."
   *ICFP*, 2000.
6. Philip Wadler. "Call-by-Value is Dual to Call-by-Name, Reloaded."
   *RTA*, 2005.
7. David Binder, Marco Tzschentke, Marius Müller, and Klaus Ostermann.
   "Grokking the Sequent Calculus (Functional Pearl)." *ICFP*, 2024.

Full citations with sources in [SPEC.md §References](SPEC.md#references).

# ksh26: Redesign Progress

Living tracker for the ksh26 structural refactor. For the full theoretical
analysis — the sequent calculus correspondence, the duploid framework, the
critical pair diagnosis — see [SPEC.md](SPEC.md).

This document records what has been implemented, what it looks like in the
code, and what remains.


## Summary

ksh93's interpreter has two modes (value and computation) with implicit
boundaries. Crossing those boundaries requires saving and restoring global
state, and the original code does this ad-hoc at each site. Missed sites
produce bugs. The refactor makes boundary crossings explicit via a polarity
frame API and classifies the interpreter's dispatch table by mode.

The theoretical vocabulary comes from sequent calculus and polarized type
theory (see [SPEC.md §Theoretical framework](SPEC.md#theoretical-framework)
and the [references](#references) below). We aren't implementing a type
system — we're naming structures that already exist in the C code so they
can be maintained consistently.


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
};
```

### Operations (xec.c, declared in defs.h)

```c
void sh_polarity_enter(struct sh_polarity *frame);
void sh_polarity_leave(struct sh_polarity *frame);
```

`sh_polarity_enter` saves `sh.prefix`, `sh.namespace`, and `sh.st`, then
clears `prefix` and `namespace`. Computation-mode code runs in a clean
context.

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
| `sh_debug()` | xec.c | Was: manual `savprefix` + `*savst` + inline trap slot preservation. Now: `sh_polarity_enter`/`leave`. Trap dup for use-after-free protection retained separately. |
| `sh_fun()` | xec.c | Was: saved only `sh.prefix`. Now: full polarity frame (saves `sh.st` too). Documented behavioral change in `notes/divergences/001-sh-fun-st-save.md`. |
| `sh_getenv()` | name.c | Was: ad-hoc `savns`/`savpr`. Now: polarity frame. |
| `putenv()` | name.c | Was: ad-hoc `savns`/`savpr`. Now: polarity frame. |
| `sh_setenviron()` | name.c | Was: ad-hoc `savns`/`savpr`. Now: polarity frame. |

### Callers that don't need polarity frames

Not every save/restore site is a polarity boundary. The remaining sites
are handled by their own Directions:

**Within-value prefix management** (Direction 3) — now converted to
`sh_prefix_enter`/`sh_prefix_leave`. See [Direction 3](#direction-3-within-value-prefix-isolation).

**Scope management** (Direction 4) — annotated with their classification.
See [Direction 4](#direction-4-polarity-frames-at-continuation-boundaries).


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

A block comment at the top of the switch documents the full taxonomy.


## Regression tests

| Test | File | What it covers |
|------|------|----------------|
| `trap - DEBUG` self-removal | basic.sh:1139 | Handler removes its own trap; must persist after `sh_polarity_leave` restores `sh.st` |
| Namespace + DEBUG trap | basic.sh:1149 | Namespace variable set while DEBUG trap active inside namespace block; verifies namespace context survives polarity boundary |
| ERR trap during compound assignment | basic.sh:1159 | `sh.prefix` must not leak into ERR trap handler (Direction 4) |
| Trap sets new trap in handler | basic.sh:1172 | `trapdontexec` must survive polarity frame restore (Direction 4) |
| Compound assignment + macro expansion | basic.sh:1183 | Prefix guard preserves context across `sh_mactrim` (Direction 3) |
| Nested compound-associative assignment | basic.sh:1191 | Prefix guard handles nested subscript resolution (Direction 3) |


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
| `sh_exec()` | ⊕ return + ⅋ dispatch | Returns `sh.exitval`; calls `sh_chktrap()` at fault.c:396 |
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
`sh_exec()`, which clears the state at xec.c:887-888.

`skipexitset` (xec.c:881): prevents `exitset()` from committing to `$?`
in contexts where it shouldn't (test expressions inside conditionals).

`echeck`: gates whether `sh_chktrap()` runs after a construct.

### Dual-channel exit status flow

```
sh.exitval (transient, per-command)
    → sh.savexit (stable, $?) via exitset()
    → sh_chktrap() check at xec.c:2614
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


## Direction status

Progress against the six refactoring directions from
[SPEC.md §Concrete directions](SPEC.md#concrete-directions):

### Direction 1: Context frames instead of global mutation

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

### Direction 2: Classify sh_exec cases by polarity

**Status: done**

All 16 case labels annotated. Block comment with taxonomy added. No further
code changes planned unless the taxonomy needs revision.

### Direction 3: Within-value prefix isolation

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

### Direction 4: Polarity frames at continuation boundaries

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

The polarity frame is conditional: `use_polframe = !sh.indebug`. When
sh_trap is called from sh_debug (DEBUG trap dispatch), sh_debug already
has its own polarity frame with post-handler scope repair via
`update_sh_level()` → `sh_setscope()`. A second polarity frame inside
sh_trap would restore `sh.st` prematurely, making `update_sh_level()`
believe the scope level is already correct and skip the `sh_setscope()`
call that repairs `sh.var_tree`. The root issue: `sh.var_tree` and
`sh.st` encode the same scope concept in two places — `sh_setscope()`
synchronizes them, but a polarity frame only saves/restores `sh.st`.
This split is a candidate for future structural work (scope chain as
explicit substitution).

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

### Direction 5: Name the dual error conventions

**Status: done**

Function convention table, errexit bridge analysis, and longjmp mode
taxonomy documented in [Error conventions](#error-conventions-⊕⅋-duality)
above. Inline annotations added to fault.h (longjmp mode block comment),
fault.c (`sh_chktrap`, `sh_trap`, `sh_exit`), xec.c (errexit suppression,
`skipexitset`, central dispatch), and cflow.c (`b_return`).

### Direction 6: Stack allocator boundaries

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

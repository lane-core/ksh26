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

### Callers that don't need conversion

Not every save/restore site is a polarity boundary. The remaining ad-hoc
sites fall into two categories that are handled by future directions:

**Within-value prefix management** (Direction 3) — these clear `sh.prefix`
temporarily during sub-expansion or path resolution, without crossing into
computation mode:

| Site | File:line | What it does |
|------|-----------|--------------|
| `nv_setlist()` | name.c:271 | Clears prefix for macro expansion of assignment values |
| `nv_open()` | name.c:1522 | Prefix around NV_STATIC assignment |
| `nv_newattr()` | name.c:2817 | Prefix across attribute change |
| `nv_rename()` | name.c:3096 | Prefix during compound ref resolution |
| TFUN handler | xec.c:2389 | Clears prefix for discipline `nv_open` lookup |

**Scope management** (Direction 4) — these do full `sh.st` + scope chain
save/restore for function and subshell boundaries:

| Site | File | What it does |
|------|------|--------------|
| `sh_funscope()` | xec.c:2953 | Full scoped state for function execution |
| `sh_subshell()` | subshell.c:535 | Full scoped state for subshell execution |

These sites are annotated in the code with their Direction classification.


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

**Status: active**

The polarity frame API is implemented and in use at 5 call sites.
`sh.prefix`, `sh.namespace`, and `sh.st` are covered. Trap slot
preservation is handled uniformly by `sh_polarity_leave`.

**Remaining work:**
- Convert additional boundary sites as they're identified
- Evaluate whether `sh.jmplist` (continuation stack head) belongs in the
  frame — currently managed separately via `sh_pushcontext`/`sh_popcontext`
- Evaluate whether `sh.var_tree` scope state belongs in the frame

### Direction 2: Classify sh_exec cases by polarity

**Status: done**

All 16 case labels annotated. Block comment with taxonomy added. No further
code changes planned unless the taxonomy needs revision.

### Direction 3: Shift-aware name resolution

**Status: planned**

The 5 within-value prefix management sites are annotated but not yet
refactored. The goal is to decouple `nv_create()`'s path-resolution context
from the global `sh.prefix`, so that inner traversal can't corrupt the outer
assignment context.

This is where `sh.prefix` has 30+ occurrences in name.c — the densest
concentration of ad-hoc state management in the codebase.

### Direction 4: Unify continuation stack with polarity frames

**Status: planned**

The scope-management sites (`sh_funscope`, `sh_subshell`) are annotated.
The goal is to make `struct checkpt` and `struct sh_polarity` work together
so that entering a new continuation frame automatically saves polarity
state — the μ-binding and the polarity shift become a single operation.

### Direction 5: Name the dual error conventions

**Status: planned**

Document which functions use ⊕ (exit status / caller inspects) vs ⅋
(trap/continuation / callee invokes). Recognize that `set -e` bridges the
two by converting ⊕ to ⅋.

### Direction 6: Stack allocator boundaries

**Status: planned**

Align `sh.stk` (Stk_t) region boundaries with polarity frame boundaries.
Value-mode allocations live on the stack and are freed when the enclosing
computation frame ends.


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

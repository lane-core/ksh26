# Scope: Variable Scope and Context Management

CDT viewpath-based scope chaining, the dual representation problem,
and context frame discipline.

## Purpose

CDT viewpath-based scope chaining, dual representation unification, and context frame discipline.

**Status**: Done. Scope unification, scope pool, var_tree in polarity
frame, own_tree rename, and compound assignment longjmp safety
(argnod_guard) are all complete.

**Source material**: [REDESIGN.md §Scope representation unification](../../REDESIGN.md#scope-representation-unification),
[§Context frames](../../REDESIGN.md#context-frames-instead-of-global-mutation),
[§Compound assignment longjmp safety](../../REDESIGN.md#compound-assignment-longjmp-safety).


## Requirements

### Requirement: CDT viewpath scope chain

Variable scopes SHALL be implemented as CDT dictionaries linked via
`dtview()`. `sh.var_tree` points to the current scope; `dtview()` links
form the scope chain back to `sh.var_base` (the global scope).

**Polarity**: Value (scope is evaluation context)
**Source**: name.c:sh_scope, name.c:sh_unscope

#### Scenario: Scope chain integrity
After `sh_scope`, `dtview(sh.var_tree)` reaches the previous scope.
After `sh_unscope`, `sh.var_tree` is the previous scope.


### Requirement: Scope dictionary pool

`sh_scope_acquire()` SHALL pop from a fixed-size pool (8 entries) or
fall back to `dtopen`. `sh_scope_release()` SHALL call `dtclear()` and
push to the pool (or fall back to `dtclose` when full).

Function scopes are strictly LIFO, so the pool amortizes malloc/free.

**Polarity**: Value (physical optimization of logical scope lifetime)
**Source**: name.c (pool + acquire/release)

#### Scenario: Pool reuse
In a loop calling functions, `dtopen` is called at most 8 times
regardless of iteration count.


### Requirement: var_tree added to polarity frame

`sh.var_tree` SHALL be saved and restored by the polarity frame (both
full and lite). Without this, double-framing (sh_trap inside sh_debug)
causes SIGBUS: the inner frame's `sh.st` restore desynchronizes
`own_tree` from `sh.var_tree`.

**Polarity**: Shift (scope consistency across boundary)
**Source**: shell.h:sh_polarity, xec.c
**Hazard**: The conditional guard (`use_polframe = !sh.indebug`) in
sh_trap has been removed now that the frame keeps both scope fields in
sync.

#### Scenario: No conditional polarity frame in sh_trap
`sh_trap` in fault.c uses an unconditional polarity frame.


### Requirement: own_tree rename convention

The struct field `save_tree` in `struct sh_scoped` SHALL be renamed to
`own_tree` to match the public alias (`Shscope_t.var_tree`). The old
name suggested entry perspective ("the tree we saved on entry"); the
new name reflects identity perspective ("this scope's own tree").

**Hazard**: `nvtree.c:walk_tree` has a local variable
`Dt_t *save_tree = sh.var_tree`. This is an RAII-style local save, NOT
the struct field — the name is appropriate there and MUST NOT be renamed.

**Source**: REDESIGN.md §Context frames (Rename: save_tree → own_tree)

#### Scenario: Local variable preserved
After the rename, `nvtree.c:walk_tree` still has `Dt_t *save_tree` as
a local variable (not renamed to `own_tree`).


### Requirement: Compound assignment longjmp safety (sh_exit guard)

The interpreter SHALL protect `L_ARGNOD` from dangling pointers during
compound assignment longjmps.
v1 (checkpoint approach) caused 13 test regressions by changing error
propagation topology. v2 (sh_exit guard) is the accepted design but has
not been coded. `nv_setlist` temporarily mutates `L_ARGNOD` to act as a
nameref to a stack-local `struct Namref`. If `sh_exec` longjmps,
`L_ARGNOD` retains a dangling pointer.

The `argnod_guard` in `Shell_t` SHALL register the L_ARGNOD restore in
`sh_exit()` — the single funnel that ALL error paths pass through before
longjmping. This adds no checkpoint and changes no error propagation
topology.

Implementation:
1. `shell.h`: `argnod_guard` struct in `Shell_t` (nvalue, nvflag, nvfun)
2. `name.c`: save L_ARGNOD fields to guard before mutation, clear after
3. `fault.c`: in `sh_exit`, if guard active, restore L_ARGNOD fields

**Polarity**: Computation (error path cleanup)
**Source**: shell.h:Shell_t, name.c:nv_setlist, fault.c:sh_exit
**Hazard**: v1 checkpoint approach caused 13 test regressions by changing
error propagation topology.

#### Scenario: No dangling L_ARGNOD after longjmp
Assigning to a readonly compound variable does not leave L_ARGNOD
pointing at unwound stack memory.

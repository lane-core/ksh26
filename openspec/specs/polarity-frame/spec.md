# Polarity Frame: Boundary Crossing Infrastructure

The central abstraction for ksh26's interpreter. A polarity frame captures
interpreter state that must be saved when crossing from value mode into
computation mode (trap dispatch, discipline functions, environment lookups).

## Purpose

Polarity frame infrastructure for saving/restoring interpreter state at value-computation boundary crossings.

**Status**: Done (REDESIGN.md §Foundations — all 9 items complete).

**Source material**: [REDESIGN.md §The polarity frame API](../../REDESIGN.md#the-polarity-frame-api),
[§Converted call sites](../../REDESIGN.md#converted-call-sites),
[§sh_exec polarity taxonomy](../../REDESIGN.md#sh_exec-polarity-taxonomy),
[§Foundations](../../REDESIGN.md#foundations).
**Theory**: [SPEC.md §Concrete directions](../../SPEC.md#concrete-directions).


## Requirements

### Requirement: Polarity frame struct

`struct sh_polarity` SHALL save the following interpreter state fields:

```c
struct sh_polarity
{
    char        *prefix;    /* saved sh.prefix */
    Namval_t    *namespace; /* saved sh.namespace */
    struct sh_scoped st;    /* saved sh.st */
    Dt_t        *var_tree;  /* saved sh.var_tree */
};
```

**Polarity**: Shift (mediates value→computation boundary)
**Source**: shell.h

#### Scenario: Struct definition matches
`grep -A6 'struct sh_polarity' src/cmd/ksh26/include/shell.h` shows all
four fields.


### Requirement: Enter/leave operations

`sh_polarity_enter` SHALL save `sh.prefix`, `sh.namespace`, `sh.st`, and
`sh.var_tree`, then clear `prefix` and `namespace` to nullptr.
Computation-mode code runs in a clean context.

`sh_polarity_leave` SHALL restore the saved state with trap slot
preservation: it MUST snapshot all live trap slots and `trapdontexec`
*before* restoring `sh.st`, then write them back after. This prevents
handler-side trap mutations from being silently overwritten.

**Polarity**: Shift
**Source**: xec.c:sh_polarity_enter, xec.c:sh_polarity_leave
**Hazard**: Without trap preservation, `trap - DEBUG` inside a handler
has no lasting effect (bug 003).

#### Scenario: Trap self-removal persists
`trap - DEBUG` inside a DEBUG trap handler removes the trap permanently.
The handler's removal MUST survive `sh_polarity_leave`'s `sh.st` restore.


### Requirement: Lightweight polarity frame

`struct sh_polarity_lite` (~24 bytes) SHALL save only `prefix`,
`namespace`, and `var_tree`. Used where an inner full frame (e.g.,
sh_trap's) already provides `sh.st` protection.

**Polarity**: Shift (weakened outer boundary)
**Source**: shell.h, xec.c:sh_polarity_lite_enter, xec.c:sh_polarity_lite_leave

#### Scenario: sh_debug uses lite frame
`sh_debug` uses `sh_polarity_lite_enter`/`leave`, not the full frame.
sh_trap (called from sh_debug) provides the inner full frame.


### Requirement: Prefix guard (within-value isolation)

`struct sh_prefix_guard` SHALL save `sh.prefix`, `sh.prefix_root`, and
`sh.first_root`. `sh_prefix_enter` saves and clears `sh.prefix`;
`sh_prefix_leave` restores all three.

This is deliberately lighter than a polarity frame (no `sh.st` save).
These sites stay within value mode — they prevent inner name resolution
from inheriting the outer compound assignment context.

**Polarity**: Value (within-mode isolation)
**Source**: shell.h (struct), defs.h:sh_prefix_enter/sh_prefix_leave (static inline),
name.c:nv_setlist, name.c:nv_rename, xec.c:sh_exec(TFUN)

4 of 5 sites from REDESIGN.md §Converted sites are converted. Site 3
(`nv_open: nv_putval` with NV_STATIC check) still uses inline
`prefix = sh.prefix; sh.prefix = 0` at name.c:1553-1557.

#### Scenario: 4 converted sites use sh_prefix_enter/leave
name.c:nv_setlist (2 sites), name.c:nv_rename (1 site), and
xec.c:sh_exec TFUN (1 site) use sh_prefix_enter/leave.


### Requirement: Runtime depth tracking

`int16_t frame_depth` in `Shell_t` SHALL be incremented on polarity enter
(both full and lite) and decremented on leave. Assertions (unconditional,
not gated on NDEBUG) SHALL verify non-negative on enter, positive on leave.

**Polarity**: N/A (bookkeeping)
**Source**: shell.h:Shell_t, xec.c, init.c

#### Scenario: Assertion fires on mismatch
A mismatched enter/leave pair triggers an assertion failure.


### Requirement: Three-layer nesting order

At polarity boundary sites, three layers MUST nest in fixed order:
1. **stk** (outermost): `stkfreeze`/`stkset`
2. **polarity** (middle): `sh_polarity_enter`/`sh_polarity_leave`
3. **continuation** (innermost): `sh_pushcontext`/`sh_popcontext`

**Hazard**: If polarity were outermost, the stk state could point to freed
memory after the polarity frame restored a different base pointer.
**Source**: xec.c:sh_debug, xec.c:sh_fun, fault.c:sh_trap

**Exception**: `sh_exec` (xec.c TCOM) suppresses stk restore when
`ARG_OPTIMIZE` is set. This is intentional — loop body allocations
persist for the optimizer. Not a leak; the optimizer manages its own
stk lifetime. Do not "fix" this as a nesting violation.

#### Scenario: Nesting order at all 3 sites
sh_debug, sh_fun, and sh_trap follow stk→polarity→continuation order.


### Requirement: macro.c degree promotion (subcopy/copyto)

`subcopy()` and `copyto()` S_BRACT case SHALL use full `Mac_t` struct
save/restore (Degree 3), matching `sh_mactrim`, `sh_macexpand`,
`sh_machere`, `mac_substitute`, and `comsubst`.

**Hazard**: In `subcopy()`, `mp->dotdot` MUST survive the restore —
the caller reads it immediately after return. Capture `dotdot` before
the struct copy; write it back after.
**Source**: REDESIGN.md §macro.c Degree 2→3 promotion

#### Scenario: dotdot survives subcopy restore
After `subcopy()` returns, the caller's read of `mp->dotdot` reflects
the value set inside subcopy, not the pre-save value.


### Requirement: sh_exec polarity taxonomy

All 16 `case` labels in `sh_exec()` SHALL be annotated with polarity
classification via the `sh_node_polarity[]` constexpr table in shnodes.h.

| Classification | Node types |
|----------------|------------|
| Value (producers) | TARITH, TSW, TTST |
| Computation (consumers) | TFORK, TPAR, TFIL, TLST, TAND, TORF, TIF, TTIME |
| Mixed (internal boundaries) | TCOM, TFOR, TWH, TSETIO, TFUN |

**Source**: shnodes.h:sh_node_polarity, xec.c:sh_exec

#### Scenario: Table covers all node types
`sh_node_polarity` has entries for all `tretyp & COMMSK` values used
by `sh_exec` case labels.


### Requirement: Scope representation invariant

`sh.var_tree == sh.st.own_tree` SHALL hold at stable points (outside
scope transitions). `sh_scope_set()` is the atomic setter:

```c
static inline void sh_scope_set(Dt_t *tree)
{
    sh.var_tree = tree;
    sh.st.own_tree = tree;
}
```

**Polarity**: Value (scope identity)
**Source**: defs.h:sh_scope_set, name.c:sh_scope, name.c:sh_unscope, xec.c:sh_funscope
**Hazard**: Without atomic update, double-framing (sh_trap inside sh_debug)
causes SIGBUS from desynchronized own_tree/var_tree.

#### Scenario: All scope-changing sites use sh_scope_set
`sh_scope`, `sh_unscope`, and `sh_funscope` exit path all call
`sh_scope_set()` instead of separate assignments.


## Converted call sites

| Function | File | Frame type |
|----------|------|-----------|
| sh_debug | xec.c | Lite polarity frame |
| sh_trap | fault.c | Full polarity frame (unconditional) |
| sh_fun | xec.c | Lite polarity frame |
| sh_getenv | name.c:3000 | Full polarity frame |
| putenv | name.c:3032 | Full polarity frame |
| sh_setenviron | name.c:3050 | Full polarity frame |


## Continuation frame classification

See REDESIGN.md §Continuation frame polarity classification for the full
27-site table. Summary:

- **Polarity boundary** (3 sites): sh_fun, sh_debug, sh_trap
- **Scope boundary** (4 sites): sh_funct, sh_subshell, sh_funscope, b_dot_cmd
- **Indirect** (3 sites, wrap sh_fun): nv_setdisc (APPEND), nv_setdisc (LOOKUPN), sh_timetraps
- **Computation-only** (17 sites): error recovery, I/O setup, loop optimization

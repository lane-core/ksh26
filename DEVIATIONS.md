# Deviations from ksh 93u+m

This document lists all behavioral differences between ksh26 and upstream
ksh 93u+m. "Behavioral" means observable from shell scripts or interactive
use; internal-only refactoring that preserves identical behavior is not
listed. Each entry notes whether the deviation is intentional (by design)
or incidental (side effect of refactoring).

Last updated: 2026-02-26

## Version identity

ksh26 reports itself as `ksh26/0.1.0-alpha` instead of `93u+m/1.1.0-alpha`
in `${.sh.version}`, `--version` output, and related strings.

Scripts that check `${.sh.version}` for feature gating should match
`*ksh26/*` in addition to `*93u+m/*`. The ksh26 test suite already does
this.

**Status**: intentional.

## Polarity frame: sh_fun() builtin path

When a builtin is called through `sh_fun()` (discipline dispatch from
name.c and macro.c), ksh26's polarity frame saves and restores the full
`sh.st` (scoped interpreter state) across the call. Upstream saves only
`sh.prefix`.

**Effect**: If a builtin dispatched via discipline modifies `sh.st` fields
(`states`, `lineno`, `trapdontexec`, etc.), those modifications are wiped
on return. On upstream they persist.

**Risk**: Low. Builtins called through discipline dispatch are not expected
to side-effect `sh.st` in ways their callers depend on. The callers are
value-mode code (expansion, name resolution) that needs its state
protected.

**Status**: intentional. See `notes/divergences/001-sh-fun-st-save.md`.

## Trap slot preservation

`sh_polarity_leave` preserves all trap slots (`sh.st.trap[0..2]`,
covering ERR, EXIT, and DEBUG) across the `sh.st` struct restore. This
means that any trap mutation made by a handler (e.g., `trap - DEBUG`
inside a DEBUG handler) survives the polarity frame leave.

Upstream's `sh_debug()` only preserves `sh.st.trap[SH_DEBUGTRAP]`, and
only in `sh_debug()` itself (not in other callers like `sh_fun()`).

**Effect**: Broader fix. If an ERR or EXIT trap handler modifies its own
trap (or another trap) during execution, those modifications are preserved
on ksh26 regardless of which polarity boundary the handler was called
through. On upstream, only the DEBUG trap in `sh_debug()` gets this
treatment.

**Status**: intentional. See `notes/divergences/002-debug-trap-self-unset.md`.

## sh_debug lightweight frame

`sh_debug()` uses a lightweight polarity frame (`struct sh_polarity_lite`,
~56 bytes) instead of the full `struct sh_polarity` (~208 bytes). This
saves `sh.prefix`, `sh.namespace`, `sh.var_tree`, and trap slots, but not
the full `sh.st`. The full `sh.st` protection is provided by `sh_trap()`'s
inner polarity frame.

**Effect**: No behavioral change. The same fields are saved and restored;
only the mechanism differs (two nested frames — outer lite, inner full —
instead of two nested full frames).

**Status**: intentional optimization. ~4x reduction in copy traffic per
DEBUG trap invocation.

## Empty DEBUG trap early exit

When a DEBUG trap is set but its trap string is empty (e.g., `trap '' DEBUG`),
`sh_debug()` returns immediately without building `.sh.command`, entering a
polarity frame, or calling `sh_trap()`.

**Effect**: No behavioral change. An empty trap string produces no side
effects when executed. The early exit skips work that would have no
observable result.

**Status**: intentional optimization.

## Scope dictionary pool

Function scope dictionaries (CDT `Dt_t` objects created by `sh_scope()`
and destroyed by `sh_unscope()`) are cached in an 8-entry LIFO pool
instead of being `dtopen`/`dtclose`'d on every function call.

**Effect**: No behavioral change. The dictionaries are cleared (`dtclear`)
before reuse. Logical scope lifetime is unchanged; only physical memory
lifetime differs.

**Status**: intentional optimization. Measured 8.5% improvement on tight
function-call loops (1M iterations).

## $Id strings

All builtin `$Id` version strings report `(ksh26)` instead of
`(ksh 93u+m)`. This affects `--version` output for builtins like `cd`,
`printf`, `read`, `test`, etc.

**Status**: intentional.

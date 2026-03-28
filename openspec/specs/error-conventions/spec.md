# Error Conventions: ⊕/⅋ Duality

ksh93 has two error-handling conventions that coexist throughout the
interpreter. They are duals in the sequent calculus sense (SPEC.md §⊕/⅋).

## Purpose

Document the dual error-handling conventions (exit status vs trap/continuation) in the ksh interpreter.

**Status**: Done (REDESIGN.md §Error convention duality).

**Source material**: [REDESIGN.md §Error conventions](../../REDESIGN.md#error-conventions-⊕⅋-duality).
**Theory**: [SPEC.md §⊕/⅋](../../SPEC.md).


## Requirements

### Requirement: Two error conventions

The interpreter SHALL maintain two coexisting error conventions:

- **⊕ (exit status)**: A command returns a status code; the *caller*
  decides what to do. Like `Result<T,E>`.
- **⅋ (trap/continuation)**: On error, the *callee* invokes a handler
  registered by the caller. Like passing `onSuccess`/`onFailure` callbacks.

`set -e` (errexit) is the bridge: it converts ⊕ into ⅋ by automatically
invoking the ERR trap (or exiting) when a command returns nonzero.

**Polarity**: Mixed (⊕ is value-mode, ⅋ is computation-mode)
**Theory**: SPEC.md §⊕/⅋

#### Scenario: Function convention table accuracy
Each function in the table below uses the documented convention.


### Requirement: Function convention table

Each interpreter function SHALL use exactly one of the two conventions:

| Function | Convention | Mechanism |
|----------|-----------|-----------|
| sh_exec | ⊕ return + ⅋ dispatch | Returns sh.exitval; calls sh_chktrap |
| sh_trap | ⊕ return | Returns handler's exit status |
| sh_chktrap | ⅋ dispatch | ERR trap → sh_exit longjmp if errexit |
| sh_debug | ⊕ return | Returns trap status (2 = skip command) |
| sh_fun | ⊕ return | Returns sh.exitval after polarity leave |
| sh_funscope | ⊕ return | Returns r (from sh.exitval or jmpval) |
| sh_eval | ⊕ return | Returns sh.exitval |
| sh_exit | ⅋ longjmp | siglongjmp to sh.jmplist |
| sh_done | ⅋ terminal | Runs EXIT trap, terminates process |
| sh_fault | ⅋ deferred | Sets sh.trapnote; trap runs later |
| b_return | ⅋ longjmp | Converts exit status to SH_JMPFUN/EXIT |
| nv_open | ⅋ longjmp | ERROR_exit on failure (no ⊕ path) |
| builtins (b_*) | ⊕ return | Return int; sh_exec captures in sh.exitval |

**Source**: xec.c, fault.c, name.c, cflow.c

#### Scenario: Convention annotations in source
Inline annotations exist in fault.h (longjmp mode block comment),
fault.c (sh_chktrap, sh_trap, sh_exit), xec.c (errexit suppression,
skipexitset), and cflow.c (b_return).


### Requirement: Errexit bridge (⊕→⅋ conversion)

The state/option split SHALL be:
- `sh_isstate(SH_ERREXIT)` — transient, suppressed in conditionals
- `sh_isoption(SH_ERREXIT)` — persistent `set -e`

Suppression contexts (`&&`, `||`, `if`/`while` condition, `!`) SHALL
pass `flags & ARG_OPTIMIZE` without `sh_state(SH_ERREXIT)` to recursive
`sh_exec()`, which clears the state at xec.c:930.

**Source**: xec.c:sh_exec (errexit handling)
**Hazard**: `skipexitset` (xec.c:923) prevents exitset() from committing
to `$?` in test-expression contexts inside conditionals.

#### Scenario: Conditional suppression
`if false; then :; fi` with `set -e` does not exit the shell.


### Requirement: Dual-channel exit status flow

The interpreter SHALL maintain a dual-channel exit status flow:

```
sh.exitval (transient, per-command)
    → sh.savexit (stable, $?) via exitset()
    → sh_chktrap() check at xec.c:2636
```

`sh.exitval` SHALL be the transient per-command status. `sh.savexit`
SHALL be the stable value visible as `$?`, committed by `exitset()`.

**Source**: xec.c, fault.c:sh_chktrap

#### Scenario: $? reflects savexit
After `false; true`, `$?` is 0 (true's exit status via sh.savexit).


### Requirement: Longjmp mode taxonomy

The `SH_JMP*` constants (fault.h) SHALL be ordered by severity. Higher
values propagate further up the continuation stack. The boundary between
locally-caught (⊕) and propagating (⅋) modes is at `SH_JMPFUN` (7).

**Source**: fault.h (SH_JMP* constants with classified block comment)

#### Scenario: Severity ordering in fault.h
Block comment in fault.h documents the ordered taxonomy.

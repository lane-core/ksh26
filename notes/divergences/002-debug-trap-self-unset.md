# 002: 'trap - DEBUG' inside handler — structural vs inline fix

## Dev fix
Commit: 916cd31d
Files: `src/cmd/ksh26/sh/xec.c`, `src/cmd/ksh26/tests/basic.sh`
Summary: `trap - DEBUG` inside a DEBUG handler had no lasting effect. The
blanket `sh.st = *savst` restore in `sh_debug()` clobbered the handler's
trap removal, bringing back the old (freed) pointer.

Dev fix is three inline changes to `sh_debug()`:
1. Remove zeroing of `sh.st.trap[SH_DEBUGTRAP]` before handler dispatch
2. Duplicate trap string before `sh_trap()` to prevent use-after-free
3. Save `sh.st.trap[SH_DEBUGTRAP]` after handler, restore after blanket
   `sh.st` copy

## ksh26 status: fixed, structurally

Commit: c8583ae8

The same three problems existed on ksh26, but the fix goes into the polarity
frame API rather than into `sh_debug()` inline:

**`sh_polarity_leave`** now preserves all trap slots across the `sh.st`
restore. Before the blanket struct copy, it snapshots `sh.st.trap[0..2]`;
after, it writes them back. This makes the API correct for both callers
(`sh_debug` and `sh_fun`) without either needing to work around it.

The dev fix only preserves `SH_DEBUGTRAP` in `sh_debug()`. The ksh26 fix
preserves all trap slots (`0..SH_DEBUGTRAP`) for all `sh_polarity_leave`
callers — a broader correction that prevents the same class of bug for
ERR and EXIT traps modified inside handlers.

**`sh_debug` zeroing removal** — same as dev. Re-entrancy is prevented by
`sh.indebug`, so zeroing the trap slot was unnecessary and harmful (it hid
the live pointer from `trap - DEBUG`).

**Trap string duplication** — same as dev. `sh_trap()` reads the string
in-place via `sfopen(NULL,trap,"s")`; if the handler frees it, that's a
use-after-free. Both branches duplicate before `sh_trap()` and free after.

## Why the dev fix doesn't apply

The dev fix patches `sh_debug()` directly — it saves/restores
`sh.st.trap[SH_DEBUGTRAP]` around the `sh.st = *savst` line. On ksh26,
`sh_debug()` doesn't do its own `sh.st` save/restore; it delegates to
`sh_polarity_enter`/`sh_polarity_leave`. The inline save/restore has no
place to go.

The zeroing removal and string duplication do apply conceptually, and
the ksh26 commit makes the same two changes in `sh_debug()`. The trap
preservation is the part that diverges in *where* it lives.

## Regression test

Same test, ported to ksh26's `basic.sh`:

```sh
got=$(set +x; "$SHELL" -c '
	typeset -i n=0
	trap "if ((++n > 1)); then trap - DEBUG; fi" DEBUG
	:; :; :; :; :; :
	trap
')
[[ $got == '' ]] || err_exit "'trap - DEBUG' inside handler has no lasting effect ..."
```

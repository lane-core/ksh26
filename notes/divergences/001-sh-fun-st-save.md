# 001: sh_fun() polarity frame

## What changed (ksh26)

`sh_fun()` previously saved only `sh.prefix` across function/builtin dispatch.
It now uses `sh_polarity_lite_enter`/`sh_polarity_lite_leave`, which saves
`prefix`, `namespace`, and `var_tree`.

## Why

`sh_fun()` is the external interface for calling shell functions and builtins,
used primarily by name discipline dispatch in `nvdisc.c` (get/set/unset
disciplines). These are value-to-computation boundary crossings — the polarity
frame isolates the caller's compound assignment context (`prefix`, `namespace`)
and scope tree (`var_tree`) from the callee.

## What it does NOT save

The lite frame does NOT save `sh.st`. For the **non-builtin** path (through
`sh_funct` → `sh_funscope`), `sh_funscope` manages `sh.st` save/restore
internally. For the **builtin** path, `sh.st` modifications by the builtin
persist to the caller — this was the pre-existing behavior and is maintained.

## Risk assessment

Low. Builtins called through discipline dispatch are not expected to side-effect
`sh.st` in ways their callers depend on. The callers (macro.c expansion, name.c
resolution) are value-mode code that needs its interpreter state protected, not
mutated by callees.

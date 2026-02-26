# 001: sh_fun() now saves/restores full sh.st

## What changed (ksh26, commit 8d7fa961)

`sh_fun()` previously saved only `sh.prefix` across function/builtin dispatch.
The polarity frame API (`sh_polarity_enter`/`sh_polarity_leave`) now saves the
full `sh.st` as well.

## Why

`sh_fun()` is the external interface for calling shell functions and builtins,
used primarily by name discipline dispatch in `nvdisc.c` (get/set/unset
disciplines at lines ~302 and ~417). These are value-to-computation boundary
crossings — the polarity frame exists to protect the caller's interpreter state
across exactly these transitions.

## Behavioral change

For the **non-builtin** path (through `sh_funct` → `sh_funscope`), the polarity
frame's `sh.st` restore is redundant — `sh_funscope` already saves/restores
`sh.st` internally. No behavioral change.

For the **builtin** path, the polarity frame is the only `sh.st` save/restore.
If a builtin dispatched via `sh_fun` modifies `sh.st` fields (`states`,
`lineno`, `trapdontexec`, etc.), those modifications are now wiped on return.
Previously they persisted.

## Risk assessment

Low. Builtins called through discipline dispatch are not expected to side-effect
`sh.st` in ways their callers depend on. The callers (macro.c expansion, name.c
resolution) are value-mode code that needs its interpreter state protected, not
mutated by callees. This is the intended polarity discipline.

If a regression surfaces, check whether a builtin called via `sh_fun` relies on
persisting `sh.st` changes to its caller. The fix would be to selectively
restore only specific fields rather than the full struct.

## Corresponding dev behavior

Dev's `sh_fun()` saves/restores only `sh.prefix`. If a dev fix later adds
`sh.st` save/restore to `sh_fun`, it's convergent with this ksh26 change.

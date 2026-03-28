# Agent Implementation Guide

**Read CLAUDE.md first.** It is the authoritative project instruction
file. This file adds two things: a phase-to-spec mapping and a hazard
list. For everything else, use the openspec tooling directly.

## Getting started

```sh
openspec show <change>                          # read proposal + architecture
openspec instructions tasks --change <change>   # enriched context with dependencies
openspec spec show <spec-name>                  # read a spec's contracts
openspec validate --all                         # structural validation
```

Read `openspec/specs/workflow/spec.md` in full before your first commit.


## Specs by implementation phase

### Layer 1 (Reduction) — fresh-rewrite tasks 1.1-1.8
No specs needed — strictly subtractive. Delete code, verify
`just build && just test` after each sub-phase.

### Layer 2 (Type Foundation) — fresh-rewrite tasks 2.1-2.7
- `build-system`: C23 gate, POSIX Issue 8 probes, build variants

### Layer 3 (Polarity Infrastructure) — fresh-rewrite tasks 3.1-3.8
- `polarity-frame`: frame struct, enter/leave, lite frame, prefix
  guard, depth tracking, nesting order, taxonomy, macro.c degree promotion
- `error-conventions`: ⊕/⅋ duality, function convention table,
  errexit bridge, longjmp mode taxonomy
- `scope`: CDT viewpaths, scope pool, var_tree in frame, own_tree
  rename, argnod_guard (**not yet implemented**)
- `theory`: polarity vocabulary, precision levels for correspondences

### Layer 4 (sfio Rewrite) — sfio-rewrite tasks 0-8
- `sfio`: all 12 requirements — buffer invariant, flag namespaces,
  sfreserve 5 patterns, LOCKR protocol, %! format engine, disciplines,
  _sfmode, NUL sentinel, ksh integration, regression tests, surviving deps


## Hazards

Things that will trip you up — not documented elsewhere in the specs:

1. **argnod_guard is now implemented** (shell.h + name.c + fault.c).
   sh_exit restores L_ARGNOD if the guard is armed during compound
   assignment longjmps. No checkpoint, no topology change.
2. **sh_getenv, putenv, sh_setenviron exist** in name.c (lines 3000, 3032,
   3050) and are **already converted** with full polarity frames on `main`.
   Task 3.4 re-derives this on the fresh-rewrite clean base.
3. **Prefix guard site 3 is not converted.** `nv_open` (name.c:1553-1557)
   still uses inline `prefix = sh.prefix; sh.prefix = 0` instead of
   `sh_prefix_enter`. The other 4 of 5 sites are converted.
4. **`mp->dotdot` must survive Mac_t struct restore** in subcopy(). The
   caller reads it immediately after return.
5. **sfstrtof.h is needed** by comp/strtod.c — don't delete it during
   sfio work.
6. **sfdcfilter.c must stay excluded** from the build (depends on deleted
   sfpopen).
7. **N_ARRAY macro has different values** across VLE files. Use `#undef`
   between sections when consolidating.
8. **nvtree.c has a local `save_tree`** that is NOT the struct field and
   must NOT be renamed during the own_tree rename.
9. **`nix develop .#agent -c` eats commands.** Use `nix develop -c` for
   one-shot iteration recipes.

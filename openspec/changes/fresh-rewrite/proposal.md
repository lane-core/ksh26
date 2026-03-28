## Why

The main branch accumulated 2,158 organic commits — discoveries, false
starts, three failed sfio attempts, course corrections. The current
`main` descends from a fresh rewrite of the build system (originally
developed on `build-again-build-better2`, now merged). This change
re-derives each transformation from the specification. Same endpoint,
acyclic path, each step independently verifiable.

## What Changes

- **Layer 1 (Reduction)**: Delete ~150 files of dead code. 6 sub-phases:
  dead libast subsystems, dead libraries, libcmd thinning, comp thinning,
  platform removal, security audit. Strictly subtractive.
- **Layer 2 (Type Foundation)**: C23 dialect, typed enums, constexpr,
  static_assert, [[nodiscard]], nullptr, POSIX Issue 8 probes. Declarative.
- **Layer 3 (Polarity Infrastructure)**: Polarity frame API, prefix guards,
  scope unification, depth tracking, macro.c degree promotion, error
  convention annotations, safe optimizations.
- **Layer 4 (sfio Rewrite)**: Covered by the separate `sfio-rewrite` change.
  Layers 3+4 are interleaved as correspondence pairs (notes/IMPLEMENTATION.md).

## Specs Affected

### New
_(none — all specs already exist)_

### Modified
- `error-conventions`: Inline annotations added to source files
- `build-system`: C23 gate and POSIX Issue 8 probes in configure.sh

### Implemented (no contract changes)
- `polarity-frame`: All existing contracts re-derived on clean base
- `scope`: All existing contracts re-derived on clean base

## Impact

- Every source file in `src/` is potentially touched (C23 conversion)
- `configure.sh` — C23 gate, Issue 8 probes, source collection updates
- ~150 files deleted (Layer 1)
- ~41 files modified for platform removal
- Core interpreter files (xec.c, name.c, fault.c, shell.h, defs.h,
  shnodes.h, macro.c) gain polarity infrastructure

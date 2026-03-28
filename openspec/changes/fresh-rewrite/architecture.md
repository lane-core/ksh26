## Context

The current `main` descends from a fresh rewrite of the build system
(originally `build-again-build-better2`, now merged). It has a modern
build system (just + samu + nix) and a clean base for re-deriving each
transformation from specification in dependency order.

Prior phases already on main:
- Phase 0 (branding): commit 85b6d157
- Phase 1 (samu + configure): commit f822703f
- Phase 2 (nix encapsulation): commit 879c4d48
- Phase 3 (test contexts): commit 60038b5d
- Review fixes: commits a7cd15ec, 104c5aed

## Goals / Non-Goals

**Goals:**
- Same endpoint as main, acyclic path, each step independently verifiable
- 4 layers in dependency order: Reduction → Type Foundation → Polarity → sfio
- `just build && just test` passes after each sub-phase

**Non-Goals:**
- Cherry-picking main's commits (imports order dependencies and abandoned approaches)
- Preserving main's commit history (the path is re-derived, not replayed)
- Speculative refactoring beyond what main achieved

## Decisions

### 1. Fresh base, not cherry-pick

Main applied C23 changes late, after polarity and library reduction had
modified the same files. Cherry-picking imports merge conflicts and
implicit assumptions. Re-deriving from spec produces the same result
without path dependencies.

### 2. Reduction first

Dead code obscures structure. Removing ~150 files and ~191 compiled
objects first means every subsequent layer operates on a smaller surface.
This reverses main's order (where some polarity work preceded reduction).

### 3. Layers 3+4 interleaved as pairs

notes/IMPLEMENTATION.md organizes interpreter polarity infrastructure and sfio
rewrite as correspondence pairs. Each pair addresses one aspect of the
polarity framework with matched interpreter-side and sfio-side changes.
Build order: interpreter side first (works with legacy sfio), sfio files
staged, atomic swap at the end.

## Risks / Trade-offs

**[Layer 1 over-deletion]** → Deleting code that turns out to be needed.
Mitigation: `just build && just test` after each sub-phase. Each deletion
is reversible via git.

**[C23 compiler availability]** → Requiring GCC 14+ / Clang 18+ narrows
the builder set. Mitigation: nix flake provides the compiler. All Tier 1
platforms have compatible compilers.

**[Re-derivation divergence]** → The clean base might differ from main in
ways that make some transformations inapplicable. Mitigation: REDESIGN.md
and SPEC.md document the contracts, not the implementation. Re-derive
from contracts.

## Open Questions

- Should Layer 1 sub-phases be individual commits or squashed per layer?
- Should the C23 conversion be automated (clang-tidy) or manual?

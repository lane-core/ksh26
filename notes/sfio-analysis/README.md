# SFIO Operational Semantics Reference

## Purpose

Independent reference documenting what SFIO *actually does*, derived from the
legacy source code (`src/lib/libast/sfio/`). This suite serves as a control for
the sfio→stdio rewrite: it records the behavior that any
replacement must preserve or consciously deviate from.

This is **not** a rewrite plan. Rewrite decisions live in `REDESIGN.md`.

## How to navigate

**By operation**: Find the function you're calling and look it up in the
relevant path document.

| Need to understand... | Go to |
|-----------------------|-------|
| Struct fields, what they mean | [01-data-structures](01-data-structures.md) |
| What a flag/mode bit does | [02-flags-and-modes](02-flags-and-modes.md) |
| Buffer pointer invariants | [03-buffer-model](03-buffer-model.md) |
| sfread, sfgetr, sfreserve | [04-read-path](04-read-path.md) |
| sfwrite, sfputr, sfprintf | [05-write-path](05-write-path.md) |
| sfnew, sfopen, sfclose, sfstack, sfswap | [06-lifecycle](06-lifecycle.md) |
| Discipline stack, exceptions | [07-disciplines](07-disciplines.md) |
| sfsync, pools | [08-pools-and-sync](08-pools-and-sync.md) |
| SF_STRING, sftmp | [09-string-and-temp](09-string-and-temp.md) |
| ksh's sftable, redirections, comsub | [10-ksh-integration](10-ksh-integration.md) |
| Stk_t allocator | [11-stk-allocator](11-stk-allocator.md) |
| C23 modernization opportunities | [12-c23-opportunities](12-c23-opportunities.md) |

**By data structure**: Start with [01-data-structures](01-data-structures.md),
then follow cross-references.

**By integration point**: Start with [10-ksh-integration](10-ksh-integration.md)
for how ksh uses SFIO, or [11-stk-allocator](11-stk-allocator.md) for the
stack allocator identity.

## Conventions

- `Legacy: src/lib/libast/sfio/sfread.c:35` — reference to legacy source location
- `→ C23:` — modernization note inline with semantic description
- `Polarity:` — connection to SPEC.md polarity framework
- `Contract:` — invariant/postcondition that any replacement must preserve
- `Invariant:` — condition that holds across operations
- `⚠ Hazard:` — known pitfall or subtle behavior

## Polarity framework

SFIO operations map onto the polarity framework from [SPEC.md](../../SPEC.md):

- **Positive** (produce data): writes, buffer fills, format output
- **Negative** (observe/consume data): reads, buffer drains, format input
- **Cut** (restructure context): seek, mode switch, stack push/pop, sync

Each document annotates operations with their polarity where it illuminates
the design. The buffer is the mediating structure between value (data content)
and computation (I/O syscalls) — it sits at the polarity boundary.

## Living document protocol

- **Update when**: a rewrite reveals undocumented behavior, or a documented
  invariant turns out to be wrong
- **What goes where**: operational facts here, rewrite decisions in REDESIGN.md,
  bug analysis in `notes/bugs/`
- **Verification**: every documented invariant should cite at least one concrete
  source location

## What this does NOT cover

- Rewrite decisions (→ REDESIGN.md)
- The stdio replacement API design
- Performance benchmarks
- Test strategy for the migration

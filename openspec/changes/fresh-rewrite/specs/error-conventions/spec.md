## ADDED Requirements

### Requirement: Inline annotations on clean base

All error convention annotations documented in the main spec SHALL be
added to the clean base: fault.h block comment, fault.c inline
annotations (sh_chktrap, sh_trap, sh_exit), xec.c (errexit, skipexitset),
cflow.c (b_return).

#### Scenario: Annotations present
grep for "⊕" and "⅋" in fault.h, fault.c, xec.c, cflow.c finds the
convention annotations.

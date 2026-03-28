# Theory: Sequent Calculus Foundation

Cross-reference anchor for the theoretical framework underlying ksh26's
architecture. The full treatment lives at the project root; this spec
exists so other specs can cite it by reference.

## Purpose

Cross-reference anchor for the sequent calculus theoretical framework underlying ksh26.

## Authoritative source

[SPEC.md](../../SPEC.md) — sequent calculus correspondence, duploid
framework, critical pair diagnosis, boundary violation taxonomy, polarity
classification.

The theory is not decorative — it's a predictive tool. The analysis
found bugs [001]–[003b] before users did, the bugs validated the
theory, and the theory now informs every architectural decision. This
virtuous cycle (theory predicts failure modes → bugs found → bugs
validate theory → architecture improves) is why the theoretical
framework is central to ksh26, not supplementary.

## Key concepts (for cross-reference)

| Concept | SPEC.md section | Used by |
|---------|----------------|---------|
| Two execution modes (value/computation) | §The observation | polarity-frame, sfio |
| Critical pair (sh.prefix bugs) | §The critical pair | polarity-frame |
| ⊕/⅋ error duality | §Error conventions | error-conventions |
| Shift connectives (↓N/↑A) | §Theoretical framework | sfio (LOCKR, sftmp) |
| Polarity boundary crossings | §Concrete directions | polarity-frame, scope |
| Non-associativity witness | §Tightening the analogies | sfio (Dccache) |

### Polarity annotation vocabulary

Specs annotate requirements with polarity types. Canonical labels:

| Label | Meaning | Example |
|-------|---------|---------|
| **Value** | Produces/manipulates data without mode change | Prefix guard, scope chain |
| **Computation** | Consumes/executes, may longjmp or trap | sh_exec case labels, error paths |
| **Mixed** | Contains both value and computation sub-operations | TCOM (assignments + execution) |
| **Shift** | Mediates a polarity boundary crossing | Polarity frame enter/leave, _sfmode |
| **Boundary** | Sits between two modes, mediating without belonging to either | sfio buffer (value data ↔ computation I/O) |
| **Interception** | Observes/redirects at a mode crossing | Disciplines, Dccache |
| **Positive** | Produces/supplies output (call-by-value polarity) | sfwrite, sfvprintf |
| **Negative** | Demands/consumes input (call-by-name polarity) | sfreserve, sfread |
| **Neutral** | No mode interaction | VLE encoding |
| **N/A** | Bookkeeping, not polarity-relevant | frame_depth counter |

Value/Computation are location-level labels (where in the interpreter).
Positive/Negative are type-level labels (duploid polarity of data flow).
Both are used; the sfio spec primarily uses Positive/Negative because
I/O operations are characterized by data flow direction.

### Precision levels for structural correspondences

| Level | Language | Meaning |
|-------|----------|---------|
| Identification | "is" | Exact match of formal structure |
| Near-identification | "near-identification" | Equation matches exactly; composition laws unverified |
| Structural | "has the structure of" | Shape-level match; same failure discipline |
| Loose | "composes like" | Organizational parallel; formal structure absent |

**Source**: SPEC.md §Tightening the analogies, sfio-rewrite-v2.md §Tightening the analogies


## Requirements

This spec has no behavioral requirements of its own. It is a reference
anchor — changes to the theoretical framework are made in SPEC.md and
propagate to dependent specs via their cross-references.

### Requirement: Theory document is authoritative

SPEC.md at the project root SHALL be the single source of truth for
theoretical analysis. OpenSpec specs SHALL reference SPEC.md sections
rather than duplicating theoretical content.

#### Scenario: No duplication
No spec file under `openspec/specs/` contains more than 10 lines of
theoretical derivation. Theory lives in SPEC.md; specs cite it.

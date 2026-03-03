# Docs consistency audit prompt

Use this prompt with a code-reviewer or explore agent to find contradictions
between SPEC.md, REDESIGN.md, CLAUDE.md, and the actual codebase state.

---

## Task

Audit the ksh26 project documents for internal contradictions, stale
references, and description/prescription confusion. The goal is a single
list of concrete fixes — not a rewrite.

## Scope

Cross-reference these documents against each other and against the
current state of the codebase (HEAD of main):

1. **SPEC.md** — stable theoretical analysis
2. **REDESIGN.md** — living implementation tracker
3. **CLAUDE.md** (project-level, `/Users/lane/src/ksh/ksh/CLAUDE.md`) — conventions and contracts
4. **notes/sfio-rewrite-v2.md** — current sfio proposal
5. **notes/sfio-rewrite-failure-analysis.md** — postmortem

## What to check

### A. Cross-document contradictions

For every factual claim in one document, check whether other documents
agree. Flag any case where:

- Two documents describe the same thing differently (e.g., bug root
  cause, fix location, file paths, function names)
- One document claims something is "done" that another describes as
  "planned" or vice versa
- Status descriptions don't match the actual code (e.g., recipes that
  were removed, files that don't exist, APIs that were rolled back)

Pay special attention to the REDESIGN.md sfio section (lines ~733-888),
which is known to mix the abandoned stdio backend with the current
clean-room rewrite plan.

### B. Stale references

Verify every concrete reference against the current codebase:

- **Commit hashes** — do they exist? Are they on the right branch?
- **File paths** — do the files exist at HEAD?
- **Line numbers** — do they point to what the document claims?
- **Function names** — do they exist with the described signatures?
- **Recipe names** — do they exist in the justfile?
- **Test counts** — do they match `just test` output?
- **Build paths** — do they match configure.sh output?

### C. Description vs prescription

SPEC.md should describe existing structure. REDESIGN.md should track
progress and prescribe direction. Flag any case where:

- SPEC.md contains prescriptive guidance ("when adding a new feature,
  do X") that belongs in REDESIGN.md or CLAUDE.md
- REDESIGN.md contains theoretical analysis that belongs in SPEC.md
- CLAUDE.md contains stale conventions that contradict current practice

### D. Abandoned work artifacts

The sfio stdio backend (Phases 5-8) was rolled back to v0.0.1.
Check for any surviving references to:

- `sh_io.h`, `sh_strbuf.h`, `sh_stream_t`
- `KSH_IO_SFIO`, `KSH_IO_STDIO` conditional compilation flags
- `just build-stdio`, `just test-stdio`, `just check-stdio`
- `STDIODIR`, `build/darwin.arm64-64-stdio`
- Phase 6/7/8 as future work items (these phases described the
  abandoned approach, not the current one)

### E. sfio section reconstruction

The REDESIGN.md sfio section needs to clearly separate:

1. **What the sfio retirement accomplished** (in v0.0.1, still live):
   stk decoupling, dead code deletion, sfprintf→stdio macros in libast
2. **What was abandoned** (Phases 5-8): the stdio backend, sh_stream_t,
   FILE* wrapping
3. **What the current plan is**: clean-room sfio rewrite per
   sfio-rewrite-v2.md

Flag every line in the sfio section that conflates these three categories.

## Output format

For each finding:

```
[SEVERITY] CONTRADICTION | STALE | MISPLACED | ABANDONED
File: <path>
Line: <number or range>
Says: <what the document claims>
Reality: <what's actually true>
Fix: <concrete edit>
```

Severity: critical (blocks understanding), moderate (misleading),
minor (cosmetic or pedantic).

Sort by severity, then by file.

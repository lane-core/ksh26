# Workflow: Testing and Review Protocols

Process invariants for how changes are verified, reviewed, and committed.
These are as load-bearing as behavioral contracts — violating them has
caused real regressions and lost work.

## Purpose

Testing, review, and commit protocols that govern how changes to ksh26 are validated and integrated.

**Source material**: [CLAUDE.md §Pre-commit review protocol](../../CLAUDE.md),
[§Immutable Test Sanctity](../../CLAUDE.md), [§Advisory tests](../../CLAUDE.md).


## Requirements

### Requirement: Pre-commit review

Every commit SHALL require a correctness review before staging. No
exceptions — documentation-only changes still get reference accuracy
checks.

**Mechanism:**
- Non-trivial changes (multi-file, approach-level, new subsystem work):
  spawn a `feature-dev:code-reviewer` agent against the full diff.
- Small changes (single-file fixes, typo corrections, config tweaks):
  the committing agent runs through the checklist inline.

The threshold is judgment-based: if you'd want a second pair of eyes
on it in a human team, use the agent.

**Source**: CLAUDE.md §Pre-commit review protocol

#### Scenario: Non-trivial change triggers agent review
A multi-file change touching polarity infrastructure spawns a
`feature-dev:code-reviewer` agent before any `git add`.

#### Scenario: Documentation change gets reference check
A REDESIGN.md update still gets reference accuracy verification
(line numbers, function names, test counts).


### Requirement: Review checklist

The review SHALL verify five items in order:

1. **Task completion** — diff accomplishes what was requested. Flag
   claimed-but-missing or present-but-unrequested changes.
2. **Correctness against project materials** — cross-reference against
   CLAUDE.md, SPEC.md, REDESIGN.md, `openspec/specs/`, source comments,
   TODO.md. Run `openspec validate --all`.
3. **Reference accuracy** — every line number, test count, file path,
   function name, or cross-reference in the diff MUST be verified against
   current codebase state. Stale references are bugs.
4. **Approach validity** — for non-trivial changes: is this the right
   approach? Does it respect subsystem contracts? Could it fail for
   reasons not visible in test results?
5. **Build and test** — `just test` MUST pass. New warnings MUST be
   acknowledged or fixed. Test count MUST not regress.

**Source**: CLAUDE.md §Pre-commit review protocol §Checklist

#### Scenario: Stale line number reference caught
A comment citing `xec.c:925` is verified against the actual line.
If the code moved, the review flags it before commit.


### Requirement: Review verdict

The review SHALL produce one of three verdicts:

- **PASS** — all checks satisfied, proceed to commit.
- **PASS with notes** — minor issues that don't block. Notes go in
  commit message or TODO.md.
- **REVISE** — issues listed with severity (critical/moderate/minor)
  and concrete fixes. MUST NOT commit until critical and moderate
  issues are resolved.

**Source**: CLAUDE.md §Pre-commit review protocol §Verdict format

#### Scenario: Critical issue blocks commit
A review finding a dangling pointer in polarity frame code produces
REVISE with severity critical. The commit does not proceed.


### Requirement: Discovery-driven restart

Agents SHALL treat newly-discovered invariants as expanded spec, not
bugs. When a previously-unknown invariant or contract is discovered mid-
implementation, it SHALL be treated as new spec, not as a bug in the
current code. The agent SHALL re-evaluate design choices against the
expanded specification before patching forward.

If the new invariant would have changed how the code was structured,
restart from the expanded spec rather than retrofitting.

**Hazard**: Patching forward after discovering a missed invariant
produces brittle code that technically works but structurally ignores
the constraint.

**Source**: Agent memory (discovery-driven restart rule)

#### Scenario: New invariant discovered during sfio rewrite
Discovering that sfreserve pattern 5 has undocumented semantics
triggers a design re-evaluation of sfread.c, not a local workaround.


### Requirement: Zero-failure test policy

Any test failure SHALL be treated as a regression until proven otherwise.
No exceptions without explicit user approval, plus a concrete plan for
when and how the issue gets fixed.

**Ownership assumption:** The agent SHALL assume it caused any failure
observed during its work. The burden of proof is on the agent to
demonstrate a failure is pre-existing (by testing the pre-change state),
not on the user to prove it isn't.

**Source**: Agent memory (zero-failure test policy)

#### Scenario: Test fails during polarity frame work
A failure in `basic.sh` during polarity frame implementation is assumed
to be caused by the polarity changes. The agent tests the pre-change
state before claiming pre-existing.


### Requirement: Immutable test sanctity

The ksh93 test suite SHALL be treated as inherited specification, not
owned code. Test logic is immutable.

**Permitted modifications (narrow exceptions):**
- Changing execution context (env vars, working directory, fds)
- Providing filesystem fixtures the sandbox withholds
- Adjusting timing thresholds only where the test explicitly provides hooks
- Wrapping execution to simulate TTY availability

**Prohibited modifications (absolute):**
- Altering assertion logic, grep patterns, or expected output
- Reordering test sequences or skipping tests
- Replacing sleep durations or retry loops
- Modifying test data files or test scripts

**Source**: CLAUDE.md §Immutable Test Sanctity

#### Scenario: Test fails in nix sandbox but passes locally
The framework is adapted (context adaptation in `tests/contexts/`),
not the test. The test script is not modified.


### Requirement: Failure investigation protocol

When a test fails, the agent SHALL follow this hierarchy:

1. **Reproduce outside harness** — `just test-one <name>`. If it fails
   here too, it's a real bug in the shell.
2. **Identify missing context** — TTY, filesystem fixtures, env vars,
   network, UID/GID behavior. Add adaptation to `tests/contexts/`.
3. **Escalation** — if context deficiency can't be identified without
   modifying test logic, document: exact test name, failure mode, what
   was tried, hypothesis about missing context.

The agent MUST NOT modify the test as a "workaround."

**Source**: CLAUDE.md §Failure investigation protocol

#### Scenario: Job control test fails under sandbox
The agent checks `tests/contexts/tty.sh` for TTY simulation, adds
an adaptation if missing, and never touches the test's assertion logic.


### Requirement: Advisory test handling

`signal` and `sigchld` SHALL be advisory in nix sandbox builds — they
run and report but MUST NOT gate the build. They rely on sub-second
sleep races that break under sandbox scheduling jitter but pass
consistently on real hardware.

**Regression testing for timing-sensitive code:**
When touching signal handling, trap dispatch, job control, or process
management:
1. Run `just test-one signal` and `just test-one sigchld` locally
   (iteration path, real hardware)
2. If they fail locally → real regression, fix before committing
3. If they only fail in `just test` (nix sandbox) → scheduling jitter,
   acceptable

**Source**: CLAUDE.md §Advisory tests, flake.nix (advisory list)

#### Scenario: Signal test fails in nix but passes locally
The agent runs `just test-one signal` on real hardware. It passes.
The nix sandbox failure is documented as scheduling jitter and does
not block the commit.


### Requirement: Approach-level escalation

The agent SHALL stop and escalate when a review reveals the *approach
itself* may be wrong — not just the implementation. The agent SHALL stop and raise this before attempting
fixes. Re-evaluate the design against expanded understanding rather
than patching forward.

A wrong approach that passes tests is worse than a right approach with
a failing test.

**Source**: CLAUDE.md §Pre-commit review protocol §Escalation

#### Scenario: Review questions the checkpoint approach
During compound assignment longjmp safety review, the reviewer
identifies that adding a checkpoint changes error propagation topology.
The agent stops, escalates, and the approach is redesigned to use
sh_exit guards instead.


### Requirement: Build validation path discipline

All validation SHALL use the nix-backed path (`just build`, `just test`,
`just check-all`). The iteration path (`just test-one`, `just debug`)
is for development only and MUST NOT be used as the sole validation
for any commit.

**Source**: CLAUDE.md §Building and testing, build-system spec

#### Scenario: Agent validates with just test
Before committing, the agent runs `just test` (nix-backed, content-
addressed), not just `just test-one` for the specific test it was
working on.


### Requirement: Tee logging for validation output

Agents SHALL capture validation output via tee so errors are reviewable
without re-running. Nix-backed recipes (`just build`, `just test`) take
2+ minutes; losing the output means re-running to diagnose.

```sh
just test 2>&1 | tee /tmp/ksh-test.log | tail -15
just build 2>&1 | tee /tmp/ksh-build.log | tail -10
```

Agents MUST NOT suppress or background validation output — Lane needs
to see hanging tests.

**Source**: Agent memory (tee logging requirement), CLAUDE.md §Agent build/test workflow

#### Scenario: Test failure diagnosed from log
`just test` fails. The agent reviews `/tmp/ksh-test.log` to identify
the failing test without re-running the full suite.


### Requirement: TODO.md capture protocol

Agents SHALL capture noticed issues in TODO.md rather than fixing them
inline. When an agent notices something that should be fixed but isn't
part of the current task, it SHALL add it to TODO.md with a brief description,
severity, and enough context for someone to pick it up later. The agent
SHALL NOT fix it inline — capture and move on.

**Source**: CLAUDE.md §Noticed issues → TODO.md

#### Scenario: Agent notices stale comment during sfio work
While implementing sfread.c, the agent sees an outdated comment in
io.c. It adds a TODO.md entry and continues with sfread.c.


### Requirement: Nix staging discipline

New source files SHALL be `git add`ed before running `just build`.
The nix build copies the source tree based on git tracking — untracked
files are excluded from the nix store copy, causing silent link failures.

After deleting or adding source files, the iteration path (local samu)
SHALL run `just clean` + reconfigure. The cached `build.ninja` still
references deleted files' object targets. The nix validation path
handles this automatically (content-addressed).

**Source**: notes/sfio-analysis/sfio-reduction-report.md §Lessons Learned

**Hazard**: The nix build silently produces a binary without the new
functions, leading to confusing link errors that look like the code
is wrong when it's actually absent.

#### Scenario: New file excluded from nix build
Creating `sfvle.c` without `git add` causes `just build` to produce
a binary missing VLE functions. The agent `git add`s the file and
rebuilds.


### Requirement: Macro-hidden caller verification

When deleting source files, agents SHALL verify each file's actual
content and calling patterns, not just naming conventions or grep-based
reference counts. Callers that go through macros (e.g., `__sf_putl(f,v)`
expanding to `_sfputl(f,v)`) are invisible to direct symbol searches.

**Source**: notes/sfio-analysis/sfio-reduction-report.md §Lessons Learned

#### Scenario: Macro caller missed by grep
`grep _sfputl` finds zero callers, but `__sf_putl` (a macro) expands
to `_sfputl`. The agent reads the file to verify it's truly unused
before deleting.

## MODIFIED Requirements

### Requirement: Three-layer architecture

The build system SHALL have four layers:

| Layer | Tool | Role |
|-------|------|------|
| Porcelain | just | User-facing recipes |
| Validation | nix | Content-addressed builds (optional — not a hard dependency) |
| Configure | configure.sh | Probes + generates build.ninja + test infrastructure |
| Build engine | samu | Executes build.ninja |

nix provides content-addressed validation builds but is NOT required.
`./configure.sh && samu` SHALL work on any POSIX system with a C23
compiler. nix wraps this for reproducibility.

### Requirement: configure.sh architecture

configure.sh SHALL be an ~80-line orchestrator sourcing modules from
`build/configure/`. The architecture follows skalibs's model:

1. **Probes are C files.** Standalone `.c` programs in `build/probes/`
   compiled by a generic driver. C lives in .c files, not in shell
   heredocs.

2. **Results are flat text.** Probe outcomes go to
   `build/$HOSTTYPE/sysdeps`, a plain text key-value file.
   Inspectable, diffable, manually overridable.

3. **Headers are derived.** FEATURE headers are mechanically generated
   from sysdeps by `gen-features.sh`. Detection and output generation
   are separate phases.

4. **Shell foundation is vendored modernish.** Portable across POSIX
   shells via bundled modernish (ISC license). Provides shell detection,
   fatal bug battery, command hardening, proper scoping, safe temp files.

#### Scenario: Bootstrap from scratch
`./configure.sh && samu` on a clean checkout with a C23 compiler and any
POSIX shell produces a working ksh26 binary. No nix required.

#### Scenario: Probe debugging
When a C probe fails, the .c file can be compiled manually with
`cc -o try_foo build/probes/try_foo.c` to reproduce the failure outside
the configure framework.

#### Scenario: Result inspection
After configure runs, `cat build/$HOSTTYPE/sysdeps` shows all detected
capabilities as plain text key-value pairs.

### Requirement: configure.sh phases

configure.sh SHALL run three phases:

1. **Probes** — detect platform capabilities, write to sysdeps.
   Tiered with inter-probe dependencies. Probes run in parallel within
   tiers. Batch helpers (`hdr`, `lib`, `mem`, `typ`, `dat`) handle
   simple probes; `choose c|cl|clr` handles standalone C probes;
   shell functions handle complex multi-step probes.

2. **Generators** — read sysdeps, produce derived files.
   FEATURE headers, shtab_math[], shopt.h, git.h, cmdext.h, conflim.h,
   conftab.h, lc.h. Separate scripts, each reading sysdeps as input.

3. **Emit** — produce build artifacts.
   build.ninja, test-env.sh, run-test.

#### Scenario: Phase ordering
Probes complete and sysdeps is finalized before any generator runs.
Generators complete before emitters run.

#### Scenario: Adding a simple probe
Adding a new header or function probe requires adding one name to a
batch helper call and one entry to the manifest. No new shell function
needed.

#### Scenario: Adding a complex probe
Adding a probe that compiles+runs a C program requires adding a .c file
to `build/probes/` and a manifest entry with the appropriate type
(`c`, `cl`, or `clr`).

### Requirement: Manifest-driven probe scheduling

All probes SHALL be declared in `build/configure/manifest.sh` with
name, tier, dependencies, type, and output mapping. The driver reads
the manifest and schedules probes by tier with parallel execution
within tiers.

#### Scenario: Dependency satisfaction
A tier-2 probe that depends on tier-1 results sees those results in
`probe_defs.h` (regenerated from sysdeps after each tier).

### Requirement: Oracle-validated output

The replace-iffe-v2 monolith is the behavioral reference, NOT a
specification to reproduce verbatim. The monolith overfits to iffe's
operational semantics in several ways (see Probe Hygiene below).

For **retained probes** (those that survive the hygiene audit), FEATURE
headers SHALL be byte-identical to the monolith's output (modulo
input-hash comment lines). For **eliminated probes**, the corresponding
defines SHALL be absent from FEATURE headers AND confirmed unused by
any source file in `src/`.

#### Scenario: Oracle comparison for retained probes
After a full configure run, diff the new system's FEATURE output against
the monolith for each retained probe. Byte-identical (ignoring input-hash
comments).

#### Scenario: Eliminated probe verification
For each probe eliminated by the hygiene audit, `grep -r` for its defines
in `src/` returns zero hits (excluding `features/` iffe input files and
`configure.sh` itself).

### Requirement: Probe hygiene

Every probe in the new system SHALL have a verified downstream consumer
in `src/**/*.{c,h}`. Probes inherited from iffe that detect features
ksh26 never uses SHALL be eliminated rather than faithfully reproduced.

Specific hygiene rules:

1. **Dead defines**: If `#define _foo_bar` is generated but no `.c` or
   `.h` file in `src/` tests `_foo_bar` (via `#if`, `#ifdef`, or
   `#ifndef`), eliminate the probe.

2. **C23-guaranteed features**: If C23 (GCC 14+ / Clang 18+) guarantees
   a feature (e.g., `long long`, `_Static_assert`, `__func__`,
   `<stdint.h>` types), replace the runtime probe with an unconditional
   define. Document which C23 guarantee justifies the elimination.

3. **Dead platform branches**: Platform detection branches for systems
   ksh26 does not target (SunOS, AIX, IRIX, HP-UX, SCO) SHALL be
   removed unless a concrete portability need is documented.

4. **iffe artifacts**: Probe patterns that exist only because of iffe's
   interpreter mechanics (e.g., intermediate probes that only set up
   `$usr` context, probes split across multiple steps because iffe
   couldn't handle them in one) SHALL be redesigned for the new
   architecture, not translated.

The hygiene audit MUST be completed and documented before implementation
begins. The audit report lives in `notes/configure-audit.md`.

#### Scenario: Audit gate
No probe is implemented until `notes/configure-audit.md` confirms it has
a downstream consumer or documents why it's retained despite having none.

#### Scenario: C23 simplification
`_ast_LL`, `_key_signed`, `_has___func__`, `_has__Static_assert` are
emitted as unconditional `#define`s (no compile probe) because C23
guarantees these features.

## ADDED Requirements

### Requirement: No nix hard dependency

The build system SHALL work without nix. `./configure.sh && samu` on
any POSIX system with a C23 compiler SHALL produce a working build.
nix provides optional content-addressed validation.

#### Scenario: Bare-metal build
On a system with only a C23 compiler and a POSIX shell (no nix, no
package manager), `./configure.sh && samu` builds ksh26.

### Requirement: Portable shell foundation

configure.sh SHALL use vendored modernish (bundled, ISC license) for
shell portability. The bundle provides shell detection, fatal bug
rejection, command hardening, local scoping, and safe temp files.

#### Scenario: Unknown shell
Running configure.sh on an unfamiliar POSIX shell (e.g., dash on a
minimal Linux) succeeds if the shell passes modernish's fatal bug tests.

### Requirement: Probe output determinism

Each generated FEATURE header SHALL include a leading comment with the
probe's input signature (compiler identity, flags). Two configure runs
with identical inputs SHALL produce identical outputs.

#### Scenario: Reproducible headers
- **WHEN** configure.sh runs twice with the same compiler and source
- **THEN** all sysdeps entries and FEATURE headers are byte-identical

### Requirement: Manual sysdep override

configure.sh SHALL accept `--with-sysdep-K=V` to manually set probe
results (following skalibs's pattern). This supports cross-compilation
and environments where runtime probes cannot execute.

#### Scenario: Cross-compilation override
`./configure.sh --with-sysdep-devurandom=yes --with-sysdep-platform=linux`
skips runtime probes for those sysdeps and uses the provided values.

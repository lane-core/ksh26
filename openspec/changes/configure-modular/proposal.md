## Why

configure.sh replaced iffe with 8,806 lines of hand-translated native shell
probes. The probes are correct and verified, but the translation was
brute-force: each iffe directive became inline shell+C with no architectural
abstraction. iffe's ~1,100-line probe input files expanded 5x because the
translation inlined every pattern that iffe's interpreter provided generically
(batch probes, group cascades, result propagation, output guards).

Meanwhile, iffe itself (4,322 lines) is an unmaintained DSL interpreter with
implicit mutable state (`$usr`, `$can`, `$gothdr`, `$ifstack`) that makes
debugging a state-machine tracing exercise. Its probe input files are stranded
in a proprietary format that only iffe can execute.

Neither the monolith nor iffe is the right answer. The monolith has the right
semantics (verified, native, no interpreter) but the wrong architecture
(everything in one file, C in heredocs, no separation of concerns). iffe has
the right density (concise probe specifications) but the wrong execution model
(4K-line state machine with implicit global state).

**Reference projects:**

- **skalibs** (skarnet.org): The architectural model. 68 probes as standalone
  `try*.c` files, `choose c|cl|clr` classification, results as flat text
  (`sysdeps/sysdeps`), headers mechanically derived by `gen-sysdepsh.sh`.
  Configure script is ~850 lines of direct shell — no DSL, no interpreter.

- **modernish** (Martijn Dekker, ISC license): Portable shell foundation.
  163-test fatal bug battery, systematic shell detection across all POSIX
  shells, `harden` for command failure discrimination, `var/local` for proper
  scoping, `sys/base/mktemp` for portable temp files. Bundleable via
  `install.sh -B` for vendoring with projects. Author is the ksh93u+m
  maintainer.

- **iffe** (AT&T AST): The density reference. Probe input files (~1,100 lines)
  specify all 56 probes. The replace-iffe-v2 monolith (8,806 lines) serves as
  the operational semantics oracle — byte-identical FEATURE output is the
  correctness criterion.

## What Changes

**1. Skalibs-model architecture.** Probes are C files, not shell functions
containing C heredocs. Results go to flat text (`sysdeps`), FEATURE headers
are mechanically derived. The driver is a thin shell loop.

```
configure.sh                              orchestrator (~80 lines)
build/
  lib/modernish/                          vendored modernish bundle (ISC)
  configure/
    driver.sh                             choose/trylibs + sysdeps recording
    gen-features.sh                       sysdeps → FEATURE headers
    manifest.sh                           probe registry (name, tier, deps, type)
    probes-complex.sh                     17 shell-orchestrated probe functions
    probes-shell.sh                       5 shell-native probes (locale, cmds, etc.)
    generators/
      gen-math.sh                         math.tab → FEATURE/math + shtab_math[]
      gen-shopt.sh                        SHOPT.sh → shopt.h
      gen-headers.sh                      git.h, cmdext.h, cmdlist.h, ast_release.h
      gen-conf.sh                         conf.sh + lcgen → conflim/conftab/lc
    emit/
      ninja.sh                            emit build.ninja
      sources.sh                          collect_*_sources
      test-infra.sh                       test-env.sh + run-test
  probes/
    try_*.c                               ~46 standalone C probe programs
    data/                                 verbatim text blocks (~700 lines)
```

**2. Vendored modernish bundle as shell foundation.** Portable across all
POSIX shells without nix as a hard dependency. Provides shell detection,
fatal bug battery, `harden`, `var/local`, `mktemp`, `use safe` baseline.

**3. Separation of probes from generators.** Probes detect platform
capabilities and write results to `sysdeps`. Generators read `sysdeps` and
produce derived files (FEATURE headers, shtab_math[], shopt.h, etc.).
These are separate phases with an explicit data boundary.

**4. The replace-iffe-v2 monolith as test oracle.** Every FEATURE header
produced by the new system must be byte-identical (modulo input-hash
comment) to the monolith's output. The monolith stays on `replace-iffe-v2`
as a reference.

## Capabilities

### New Capabilities

### Modified Capabilities
- `build-system`: Rewritten configure.sh with skalibs architecture,
  vendored modernish, and probe/generator separation.

## Impact

- **configure.sh**: Rewritten from 8,806-line monolith to ~80-line orchestrator
- **build/configure/**: New directory with driver, generators, emitters
- **build/probes/**: ~46 standalone C probe files + data/
- **build/lib/modernish/**: Vendored modernish bundle (~5,000 lines, ISC)
- **Our code**: ~4,400 lines across ~20 files (driver, probes, generators, emitters)
- **Probe count**: Same 56 probes, same FEATURE outputs, same semantics
- **Portability**: No hard dependency on nix for building. Runs on any POSIX system.
- **Branch**: `new-build-sys` (worktree: `/Users/lane/src/ksh/ksh-new-build-sys/`)
- **Reference**: `replace-iffe-v2` monolith preserved as test oracle

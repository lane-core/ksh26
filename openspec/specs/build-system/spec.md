# Build System: just + samu + nix

Three-layer build system replacing AT&T's MAM infrastructure.

## Purpose

Three-layer build system (just + samu + nix) replacing AT&T's MAM infrastructure.

**Status**: Done (REDESIGN.md §Build system).

**Source material**: [notes/build-system.md](../../notes/build-system.md),
[CLAUDE.md §Building and testing](../../CLAUDE.md).


## Requirements

### Requirement: Three-layer architecture

The build system SHALL have three layers:

| Layer | Tool | Role |
|-------|------|------|
| Porcelain | just | User-facing recipes |
| Configure | configure.sh | Probes + generates build.ninja + test infrastructure |
| Build engine | samu | Executes build.ninja |

`samu` is a vendored C ninja implementation — zero-dependency bootstrap
via `cc -o samu src/cmd/INIT/samu/*.c`.

**Source**: notes/build-system.md §Architecture

#### Scenario: Bootstrap from scratch
`just build` on a clean checkout produces `result/bin/ksh` without
any pre-existing build tools beyond a C compiler.


### Requirement: Two-path build model

The build system SHALL provide two paths: validation and iteration.

**Validation path** (nix-backed, content-addressed):
- `just build`, `just test`, `just build-asan`, `just test-asan`, `just check-all`
- **Cross-platform**: `just build-linux`, `just test-linux`, `just test-linux-asan`
  (requires linux builder — nix-darwin module or remote builder)
- Any source change → derivation hash changes → full rebuild
- No stale builds possible

**Iteration path** (local samu, devshell-only):
- `just test-one NAME`, `just debug NAME`, `just test-repeat NAME`
- Timestamp-based samu caching for sub-second rebuilds
- NOT for validation
- Local-only (no cross-platform iteration builds)

**Source**: notes/build-system.md, CLAUDE.md §Build system

#### Scenario: Content-addressed correctness
Running `just test` twice with no source changes completes in ≤5 seconds
(nix cache hit).

#### Scenario: Cross-platform validation
Running `just test-linux` on a darwin host with a linux builder exercises
the full test suite on aarch64-linux via nix remote build.


### Requirement: Automatic test discovery

Tests in `src/cmd/ksh26/tests/` SHALL be discovered automatically. Drop a `.sh`
file, reconfigure, done. configure.sh discovers all `*.sh` files and
generates both C and C.UTF-8 locale variants.

**Source**: notes/build-system.md §Phase 5

#### Scenario: New test auto-discovered
Adding `src/cmd/ksh26/tests/foo.sh` and running `just configure` generates
`foo.C` and `foo.C.UTF-8` test targets in build.ninja.


### Requirement: configure.sh six phases

configure.sh SHALL run six phases in order:
0. Library detection (iconv, utf8proc)
1. Feature probes (libast iffe tests, compiler probe)
2. Other feature probes (ksh26, libcmd, pty — can run in parallel).
   std/ wrapper headers installed after this phase completes.
3. Generate derived headers (shopt.h, git.h, cmdext.h, conftab.h, lc.h)
4. Emit build.ninja
5. Test infrastructure (test-env.sh, run-test.sh)

All iffe probes SHALL compile with the same platform feature test macros
as the library code they probe for. `INSTALLROOT` SHALL be set before
invoking iffe so that `ast_standards.h` is included in all probe
compilations.

**Source**: configure.sh lines 1605-1645

#### Scenario: Phase ordering
configure.sh functions are called in the documented order.


### Requirement: Build variants

configure.sh flags SHALL compose to produce separate build directories:

| Flag | Suffix | Effect |
|------|--------|--------|
| (none) | $HOSTTYPE | Default: debug info + optimization |
| --debug | $HOSTTYPE-debug | -O0 for single-stepping |
| --asan | $HOSTTYPE-asan | AddressSanitizer + UBSan |
| --debug --asan | $HOSTTYPE-debug-asan | Both |

Variant builds SHALL share feature probes from the base build via
symlinks.

**Source**: notes/build-system.md §Build variants

#### Scenario: Variant isolation
`just build-asan` produces output in `build/$HOSTTYPE-asan/`, separate
from the base build.


### Requirement: Regression guard

The nix check derivation SHALL assert ≥114 test stamps as a regression
guard against build.ninja generation bugs.

**Source**: flake.nix checkPhase

#### Scenario: Test count assertion
`just test` produces ≥114 test stamps in the summary.


### Requirement: Advisory tests

`signal` and `sigchld` SHALL be advisory in the nix checkPhase — they
run and report but don't gate the build. They rely on sub-second sleep
races that break under sandbox scheduling jitter.

**Source**: flake.nix (advisory list), CLAUDE.md §Advisory tests

#### Scenario: Advisory test failure doesn't block
`just test` succeeds even if signal or sigchld report errors in the
nix sandbox.

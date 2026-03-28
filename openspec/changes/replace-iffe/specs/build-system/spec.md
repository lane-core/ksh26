## MODIFIED Requirements

### Requirement: configure.sh six phases

configure.sh SHALL run six phases in order:
0. Library detection (iconv, utf8proc)
1. Feature probes (native shell probe functions, compiler probe)
2. Other feature probes (ksh26, libcmd, pty — can run in parallel).
   std/ wrapper headers installed after this phase completes.
3. Generate derived headers (shopt.h, git.h, cmdext.h, conftab.h, lc.h)
4. Emit build.ninja
5. Test infrastructure (test-env.sh, run-test.sh)

All feature probes SHALL be implemented as native shell functions in
configure.sh, using `probe_hdr`, `probe_lib`, `probe_mem`, `probe_typ`,
`probe_c`, and `probe_c_output` helpers. iffe.sh SHALL NOT be invoked
during the build.

All probes SHALL compile with platform feature test macros from
`ast_standards.h` (generated in tier 0).

**Source**: configure.sh

#### Scenario: Phase ordering
configure.sh functions are called in the documented order.

#### Scenario: No iffe dependency
Running `configure.sh` with iffe.sh deleted from the source tree
produces identical build output.

#### Scenario: Cross-platform probe correctness
Generated headers on Linux contain Linux-correct values (e.g.,
`st_atim.tv_nsec` in tv.h, `_lib_gettimeofday` in FEATURE/time).

## ADDED Requirements

### Requirement: Self-contained log lines

configure.sh log output SHALL be structured so that every line is
self-contained and meaningful when viewed in isolation. No multi-line
banners or separator lines. Each probe result SHALL include its index,
name, and outcome on a single line.

#### Scenario: Single-line paging (nix build output)
- **WHEN** build output is displayed one line at a time (e.g., nix's
  `--print-build-logs` prefix `ksh26>`)
- **THEN** any individual line communicates what is happening without
  needing surrounding context

#### Scenario: Full log readability
- **WHEN** the full build log is viewed at once
- **THEN** the output reads as a clean sequential record with no
  wasted lines (no `=== BANNER ===` separators)

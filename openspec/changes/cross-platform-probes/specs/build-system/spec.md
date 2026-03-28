## MODIFIED Requirements

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

**Source**: configure.sh

#### Scenario: Phase ordering
configure.sh functions are called in the documented order.

#### Scenario: Probes use platform feature macros
When configure.sh runs on Linux with glibc, iffe probes compile with
`_GNU_SOURCE` active (via `ast_standards.h`). The `tv` probe detects
`st_atim.tv_nsec` (POSIX.1-2008), not `st_atimensec` (ancient BSD).

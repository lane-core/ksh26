# ksh26 TODO

New main branch — legacy source + new build system. Issues tracked
here are specific to this branch.

## Build system parity

- [ ] **Investigate tests added on deprecated branch for porting**
  The deprecated branch had 57 tests (114 stamps) vs legacy's 56 (112).
  Identify which tests were added, what they cover, and whether they
  should be ported to this branch. The tests themselves are immutable
  but they test functionality that exists in the legacy source.
  Check: `git diff legacy deprecated -- src/cmd/ksh26/tests/`

- [ ] **strxfrm bug detection fails in nix devshell**
  `_macos_strxfrm_bug` probe calls `setlocale(LC_ALL, "en_GB.UTF-8")`
  which fails in the nix devshell (locale exists but setlocale can't
  find it). The define is consumed by `setlocale.c:92`. Need to either
  fix the devshell locale setup or use a different detection method.

- [ ] **FEATURE diff audit vs iffe (7 remaining)**
  7 semantic diffs remain between our probes and iffe output. Each
  has been analyzed but should be re-verified on this fresh branch:
  - aso: casptr sort artifact (non-issue)
  - common: noreturn (fixed), UNREACHABLE abort vs __builtin
  - float: e/E case in fallback defines
  - lib: fnmatch shadow, mkostemp detection, UNIV_DEFAULT
  - mmap: _NO_MMAP Cygwin vs _mmap_worthy
  - stdio: ____FILE_defined intentional omission
  - wchar: wctype.h conditional include

## Test infrastructure

- [ ] **Signal tests fail in nix devshell (basic, signal)**
  SIGINT/SIGQUIT inheritance from nix environment causes basic.sh
  and signal.sh trap tests to fail. Pass on real hardware. Root
  cause: nix devshell sets signal dispositions that ksh inherits.

- [ ] **Sandbox-unreliable test list needs justification**
  Each test on the sandbox-unreliable list must have a documented
  root cause explaining why it fails in the sandbox. No test should
  be on the list without a specific mechanism identified.

## Platform cleanup

- [ ] **Retire dead platform support**
  Assess and remove support for platforms no longer maintained:
  Cygwin, UWIN, old SunOS, etc. This simplifies probes and
  source code. Keep: modern Linux (glibc, musl), macOS/Darwin,
  FreeBSD, OpenBSD, NetBSD.

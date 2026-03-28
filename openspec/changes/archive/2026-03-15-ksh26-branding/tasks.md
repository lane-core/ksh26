## 1. Core version identity

- [x] 1.1 Update `src/cmd/ksh26/include/version.h`: `SH_RELEASE_FORK` → `"26"`, `SH_RELEASE_SVER` → `"0.1.0-alpha"`, `SH_RELEASE_CPYR` → ksh26 attribution, `SH_RELEASE_DATE` → current date
- [x] 1.2 Fix hardcoded `@(#)` ID in `src/cmd/ksh26/sh/nvtype.c` line 30: `"ksh 93u+m"` → `"ksh26"`
- [x] 1.3 Fix hardcoded `@(#)` ID in `src/cmd/builtin/pty.c` line 21: `"ksh 93u+m"` → `"ksh26"`

## 2. Copyright headers (files modified in this change)

- [x] 2.1 Add dual attribution to version.h, nvtype.c, pty.c, builtins.c, init.c, shcomp.c (files touched in group 1)

## 3. Test version guards

- [x] 3.1 Update `src/cmd/ksh26/tests/substring.sh` version guard: `*93u+m/*` → `*26/*`
- [x] 3.2 Update `src/cmd/ksh26/tests/alias.sh` version guard: `*93u+m/1.0.*` → pattern that correctly gates the feature
- [x] 3.3 Update `src/cmd/ksh26/tests/bracket.sh` version guard: `*93u+m/1.0.*` → pattern that correctly gates the feature
- [x] 3.4 Update `src/cmd/ksh26/tests/case.sh` version guard and comment
- [x] 3.5 Audit remaining tests: updated types.sh, builtins.sh (×2), variables.sh, posix.sh (×2), namespace.sh (×2), functions.sh, quoting2.sh, shtests harness

## 4. Package metadata

- [x] 4.1 Update `flake.nix` description lines (2, 172): remove "fork of ksh93u+m" framing, lead with ksh26
- [x] 4.2 Sync `flake.nix` package version with `SH_RELEASE_SVER` (already `0.1.0-alpha` — confirmed in sync)

## 5. Documentation

- [x] 5.1 Rewrite `README.md` header and project description for ksh26 identity
- [x] 5.2 Update `NEWS` line 1 from "ksh 93u+m" to ksh26
- [x] 5.3 Update man page `src/cmd/ksh26/sh.1` — one live "ksh 93u+m" reference updated (rest in dead Z=2 conditionals)
- [x] 5.4 Update `CLAUDE.md` line 3 fork description

## 6. Validation

- [x] 6.1 Build and verify version output: `Version AJM 26/0.1.0-alpha 2026-03-15`
- [x] 6.2 Run full test suite: 110/110 gate tests pass — zero regressions
- [x] 6.3 Grep audit: all remaining `93u+m` in src/ are copyright headers or comments — clean

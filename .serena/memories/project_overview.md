# ksh26 — Project Overview

ksh26 is an independent fork of ksh93u+m (the KornShell). NOT a tracking fork — no merges from upstream, no upstream PRs. Repo: github.com/lane-core/ksh26.

## Purpose
A clean reimplementation of the KornShell for 2026. Current `main` branch: legacy ksh93u+m source + new build system (configure.sh + samu + nix). Design docs and Layer 1-3 refactoring on `deprecated` branch, to be vetted and replayed.

## Tech Stack
- **Language**: C (C23, GCC 14+ / Clang 18+)
- **Build**: custom configure.sh (skalibs-inspired probes) + samu (vendored ninja)
- **Package/CI**: Nix flake (flake-parts), GitHub Actions via nix-github-actions
- **Porcelain**: just (justfile)
- **Tests**: custom run-test wrapper + err_exit assertions
- **Shell foundation**: vendored modernish

## Source Layout
```
src/lib/libast/       — AST library (I/O, string, locale, sfio)
src/lib/libcmd/       — built-in command implementations
src/cmd/ksh26/        — shell source (sh/, bltins/, edit/, include/, data/, tests/)
src/cmd/INIT/samu/    — vendored ninja-compatible build tool
build/configure/      — configure system (driver.sh, probes/, emit/)
nix/modules/          — flake-parts modules (build, checks, devshell, ci, vm-tests)
tests/                — test infrastructure (contexts/, lint scripts)
```

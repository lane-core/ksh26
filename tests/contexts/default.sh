#!/bin/sh
# tests/contexts/default.sh — Base test environment setup
# Sourced by run-test.sh for all tests. Keep this minimal and fast.

# ── Environment cleanup ───────────────────────────────────────────
# Remove variables that could interfere with test behavior
unset DISPLAY FIGNORE HISTFILE POSIXLY_CORRECT _AST_FEATURES

# Neutral startup file
export ENV=/./dev/null

# ── Path setup ────────────────────────────────────────────────────
# Save original PATH for tests that need it
export userPATH=$PATH

# Minimal PATH for deterministic behavior
PATH=/usr/bin:/bin:/usr/sbin:/sbin
PATH="${BUILDDIR}/bin:$PATH"
export PATH

# ── Shell configuration ───────────────────────────────────────────
export SHTESTS_COMMON="${PACKAGEROOT}/tests/shell/_common"
export SHELL="${BUILDDIR}/bin/ksh"
export SHCOMP="${BUILDDIR}/bin/shcomp"

# ── Locale handling ───────────────────────────────────────────────
# Mode is passed from the test runner (C or C.UTF-8)
case ${mode:-C} in
	C)       unset LANG LC_ALL ;;
	C.UTF-8) export LANG=C.UTF-8; unset LC_ALL ;;
esac

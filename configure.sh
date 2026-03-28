#!/usr/bin/env sh
#
# configure.sh — ksh26 configure (skalibs architecture + modernish foundation)
#
# Detects platform capabilities, generates build.ninja + test infrastructure.
# Runs on any POSIX system with a C23 compiler. No nix required.
#
# Usage: CC=cc ./configure.sh [--force] [--debug] [--asan]
#                              [--with-sysdep-KEY=VALUE ...]
#
# Architecture:
#   Phase 1: Probes     — detect capabilities, write to sysdeps
#   Phase 2: Generators — read sysdeps, produce FEATURE headers + derived files
#   Phase 3: Emit       — produce build.ninja, test-env.sh, run-test
#
# Reference: skalibs (skarnet.org) for probe architecture,
#            modernish (Martijn Dekker) for portable shell foundation.

# ── Bootstrap modernish ──────────────────────────────────────────
# The vendored bundle finds a good POSIX shell, runs its fatal bug
# battery, and sets up safe mode + modules. If this fails, the shell
# is too broken to run configure.

_self=$(cd "$(dirname "$0")" && pwd)
CONFIGURE_DIR="$_self/build/configure"
MODERNISH_DIR="$_self/build/lib/modernish"

_Msh_PREFIX="$MODERNISH_DIR"
. "$MODERNISH_DIR/bin/modernish" || {
	echo "configure.sh: modernish initialization failed" >&2
	echo "  Your shell may have fatal bugs. Try: CC=cc bash ./configure.sh" >&2
	exit 1
}
# Note: NOT using 'use safe' — compiler invocations need word splitting
# on $CFLAGS_BASE etc. We set -u (nounset) and -C (noclobber) manually.
set -u
set -C
use sys/cmd/harden
use sys/cmd/extern
use sys/base/mktemp
use var/local

# ── Source configure modules ─────────────────────────────────────
. "$CONFIGURE_DIR/driver.sh"

# ── Parse options + setup ────────────────────────────────────────
PACKAGEROOT="$_self"
parse_options "$@"
detect_hosttype
setup_paths
gate_c23

# ── Cache check ──────────────────────────────────────────────────
if check_cache; then
	putln "configure.sh: cache valid, skipping (use --force to override)"
	exit 0
fi
setup_dirs

# ── Pre-probe setup ──────────────────────────────────────────────
if test "$_CROSS_COMPILE" -eq 1; then
	putln "configure: ksh26 for $HOSTTYPE (CC=$CC, cross-compiling from $(uname -s | tr A-Z a-z).$(uname -m))"
else
	putln "configure: ksh26 for $HOSTTYPE (CC=$CC)"
fi

detect_libs
detect_defpath
detect_tzdir
bootstrap_samu
bootstrap_setsid

# ── Phase 1: Probes ──────────────────────────────────────────────
run_probes

# ── Phase 2: Generators ─────────────────────────────────────────
run_generators

# ── Phase 3: Emit ───────────────────────────────────────────────
run_emitters

# ── Finalize ─────────────────────────────────────────────────────
write_cache_key
write_manifest
putln "configure: done"

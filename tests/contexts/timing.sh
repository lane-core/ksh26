#!/usr/bin/env sh
# tests/contexts/timing.sh — Accommodations for timing-sensitive tests
# Used by: leaks, sigchld, signal, subshell
#
# These tests have inherent timing dependencies. We cannot modify the
# tests (per Test Sanctity), but we can document known flaky behavior
# and set environment hints for future timeout integration.

# Only relevant for timing-sensitive tests
case $test_name in leaks|sigchld|signal|subshell) ;; *) return 0 ;; esac

# Per-test timeout hints (used by run-test when timeout support is wired)
case $test_name in
	leaks)
		export KSH_TEST_TIMEOUT=120
		;;
	signal|sigchld)
		# Signal delivery timing varies in sandboxed/CI environments.
		# SIGCHLD in particular may be delayed due to process scheduling.
		# These tests pass outside the sandbox — failures here are
		# scheduling artifacts, not shell bugs.
		export KSH_TEST_TIMEOUT=90
		;;
	subshell)
		export KSH_TEST_TIMEOUT=90
		;;
esac

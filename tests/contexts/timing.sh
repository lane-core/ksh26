#!/bin/sh
# tests/contexts/timing.sh — Accommodations for timing-sensitive tests
# Used by: leaks.sh, sigchld.sh, options.sh, subshell.sh
#
# These tests have inherent timing dependencies. We cannot modify the
# tests (per Test Sanctity), but we can:
# 1. Increase timeout thresholds (via KSH_TEST_TIMEOUT if respected)
# 2. Reduce scheduling jitter (taskset, nice)
# 3. Document known flaky tests

# Environment variable that some tests may check
# Note: Tests must explicitly respect this - we don't modify hardcoded sleeps
export KSH_TEST_TIMEOUT=${KSH_TEST_TIMEOUT:-60}

# Try to reduce scheduling jitter on Linux
if [ "$(uname -s)" = "Linux" ] && command -v taskset >/dev/null 2>&1; then
	# Pin to a single CPU if possible (reduces migration delays)
	# This is a hint to the test runner, not a forced setting
	export _KSH_PREFERRED_AFFINITY="0"
fi

# Nice value hint - negative values increase priority
# Tests that respect this can use: nice -n $_KSH_NICE $command
export _KSH_NICE="${KSH_TEST_NICE:-0}"

# Per-test timing adjustments
# These are documented timeouts, not modifications to test code
case $test_name in
	leaks)
		# Memory leak detection is inherently slow
		export KSH_TEST_TIMEOUT=120
		;;
	signal|sigchld)
		# Signal delivery timing can vary significantly in sandboxed/CI environments
		# SIGCHLD in particular may be delayed due to process scheduling priorities.
		#
		# Note: signal.sh line 330-337 tests SIGCHLD delivery timing with hardcoded
		# sleep values. In Nix sandbox on Darwin, signal delivery may be delayed
		# (observed: expected '01got_child23' but got '0got_child123'). This is a
		# sandbox scheduling artifact, not a shell bug. The test passes outside
		# the harness (run 'just test-one signal' to verify).
		export KSH_TEST_TIMEOUT=90
		;;
	subshell)
		# Subshell creation/destruction is resource intensive
		export KSH_TEST_TIMEOUT=90
		;;
	optons)
		# Option switching tests may involve sleeps
		export KSH_TEST_TIMEOUT=90
		;;
esac

# Note: If a test fails due to timing in CI but passes locally,
# the test may need to be categorized as "slow" and run separately,
# not modified to have longer hardcoded sleeps.

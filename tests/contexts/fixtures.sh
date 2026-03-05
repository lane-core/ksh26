#!/bin/sh
# tests/contexts/fixtures.sh — Filesystem fixtures for tests
# Used by: io.sh, libcmd.sh, and others that need specific paths
#
# Per Immutable Test Sanctity: Only create what specific tests need.
# Creating standard directories (tmp, dev, etc.) causes failures:
# - subshell.sh creates files named 'tmp', 'lin', 'buf' (not directories)
# - options.sh does '**' globbing that picks up extra directories
# - builtins.sh tests CDPATH behavior that conflicts with ./dev existing

# Export fixture paths for test awareness
export FIXTURE_ROOT="$tmp"

# io.sh specific: needs device nodes for redirection tests
if [ "$test_name" = "io" ]; then
	# Create device directory with fake nodes
	mkdir -p "$tmp/dev"
	mknod "$tmp/dev/null" c 1 3 2>/dev/null || :
	mknod "$tmp/dev/zero" c 1 5 2>/dev/null || :
	mknod "$tmp/dev/random" c 1 8 2>/dev/null || :
	export FIXTURE_DEV="$tmp/dev"
fi

# libcmd.sh specific: ensure external commands exist
if [ "$test_name" = "libcmd" ]; then
	# Some tests expect cat, echo, etc. to be in specific locations
	# The PATH setup in default.sh handles most of this
	:
fi

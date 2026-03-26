#!/usr/bin/env sh
# tests/contexts/fixtures.sh — Filesystem fixtures for tests
#
# Per Immutable Test Sanctity: Only create what specific tests need.
# Creating standard directories (tmp, dev, etc.) causes failures:
# - subshell.sh creates files named 'tmp', 'lin', 'buf' (not directories)
# - options.sh does '**' globbing that picks up extra directories
# - builtins.sh tests CDPATH behavior that conflicts with ./dev existing
#
# Currently no tests require external fixtures — the tests create their
# own temp files in $tmp. This file is a hook for future per-test setup.

# tests/expected-failures.sh — expected test failure manifest
#
# Marks specific test assertions as expected failures on specific platforms.
# When an expected failure occurs, run-test reports XFAIL (passes the gate).
# When an expected failure unexpectedly passes, run-test reports XPASS (noteworthy).
#
# Format: xfail TEST_NAME LINE_NUMBER PLATFORM_GLOB REASON
#   TEST_NAME:     base name of the test (e.g., "signal")
#   LINE_NUMBER:   line number from err_exit (matches test.sh[LINE]: FAIL:)
#   PLATFORM_GLOB: shell glob for HOSTTYPE ("*" = all, "linux.*" = linux, "darwin.*" = darwin)
#   REASON:        human-readable explanation (rest of line)
#
# Example:
#   xfail signal 261 "linux.*" parallel_3 timing under scheduler jitter
#
# Currently empty — all tests are expected to pass. Add entries here when
# a test failure is understood, has a tracking issue, and cannot be fixed
# immediately. Each entry must have a concrete plan for removal.

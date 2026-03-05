# Test Context Adaptations

This directory contains context adaptations for the test harness.

## Immutable Test Sanctity

Per CLAUDE.md: When a test fails under the harness but passes outside it,
the framework is deficient, not the test. These context adaptations provide
the missing environment without modifying test logic.

## Available Contexts

| File | Purpose | Tests Using |
|------|---------|-------------|
| `default.sh` | Base environment setup (always sourced) | All tests |
| `tty.sh` | Pseudo-terminal simulation | jobs, pty |
| `fixtures.sh` | Filesystem fixtures and required paths | io, libcmd |
| `timing.sh` | Timing-sensitive accommodations | leaks, sigchld |

## Adding a Context Adaptation

1. Create a `.sh` file in this directory
2. Add setup code that runs before the test
3. Reference it in `configure.sh`'s test generation logic
4. Document which tests need it and why

## Context Interface

Each context file is sourced by the test runner with these variables available:
- `$test_name` - Base name of the test (e.g., "basic")
- `$mode` - Locale mode ("C" or "C.UTF-8")
- `$BUILDDIR` - Build directory path
- `$tmp` - Per-test temporary directory

Context files should be idempotent and safe to source multiple times.

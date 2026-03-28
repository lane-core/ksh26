## MODIFIED Requirements

### Requirement: Three-layer architecture

The build system SHALL require C23 support (`-std=c23`, GCC 14+ /
Clang 18+) and SHALL probe for POSIX Issue 8 fd primitives in
configure.sh. No other behavioral change.

#### Scenario: C23 gate
Building with a compiler that doesn't support C23 fails with a clear
error message.

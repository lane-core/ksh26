## ADDED Requirements

### Requirement: Command hardening

The test harness SHALL provide a `harden` function that wraps specified
commands so that non-zero exit status calls `die` with a diagnostic
message including the command name, exit status, and arguments.

#### Scenario: Hardened command fails
- **WHEN** a hardened command (e.g., `mkdir`) exits non-zero in the harness
- **THEN** the harness terminates immediately with a `FATAL:` message
  identifying the command, its exit code, and its arguments

#### Scenario: Hardened command succeeds
- **WHEN** a hardened command exits zero
- **THEN** execution continues normally (no overhead visible to tests)


### Requirement: Fatal exit from subshells

The test harness SHALL provide a `die` function that terminates the
top-level test process even when called from a subshell, pipe segment,
or command substitution.

#### Scenario: die in subshell
- **WHEN** `die` is called inside a `$(...)` or pipe
- **THEN** the top-level harness process exits (not just the subshell)


### Requirement: Stack-based trap management

The test harness SHALL provide `pushtrap` and `poptrap` functions that
allow trap handlers to be stacked. Pushing a trap saves the current
handler and sets a new one. Popping restores the previous handler.

#### Scenario: Nested cleanup traps
- **WHEN** `default.sh` pushes an EXIT trap and `tty.sh` pushes another
- **THEN** popping `tty.sh`'s trap restores `default.sh`'s trap
- **AND** both cleanup actions execute on exit (in LIFO order)


### Requirement: ISC attribution

`tests/lib/safety.sh` SHALL include the ISC license notice attributing
the ported concepts to modernish by Martijn Dekker.

#### Scenario: License present
- **WHEN** `tests/lib/safety.sh` is inspected
- **THEN** the ISC copyright notice and license text are present
  in a comment block at the top of the file

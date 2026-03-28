## ADDED Requirements

### Requirement: nix-darwin linux-builder module

The ksh26 flake SHALL export a `darwinModules.linux-builder` module that
configures nix-darwin's `nix.linux-builder` with settings appropriate for
ksh26 development (CPU cores, memory, Rosetta).

#### Scenario: Module enables linux-builder
- **WHEN** a nix-darwin configuration imports `ksh26.darwinModules.linux-builder`
- **THEN** `nix.linux-builder.enable` is `true` and the VM is configured with
  ≥4 cores, ≥4096 MB memory, and Rosetta for Linux enabled.

#### Scenario: Module composes with existing darwin module
- **WHEN** a nix-darwin configuration imports both `ksh26.darwinModules.default`
  and `ksh26.darwinModules.linux-builder`
- **THEN** both modules apply without conflict — kshrc generation and
  linux-builder configuration coexist.


### Requirement: Cross-platform build recipe

The justfile SHALL provide a `build-linux` recipe that builds ksh26 for
x86_64-linux from a darwin host, using the nix remote builder.

#### Scenario: Build linux binary from darwin
- **WHEN** `just build-linux` is run on a darwin host with a linux builder available
- **THEN** nix builds `.#packages.x86_64-linux.default` and the result contains
  a linux ELF binary at `result-linux/bin/ksh`.

#### Scenario: Missing builder gives clear error
- **WHEN** `just build-linux` is run without a linux builder configured
- **THEN** the recipe exits with a message explaining how to enable the builder
  (import `darwinModules.linux-builder`), before attempting the nix build.


### Requirement: Cross-platform test recipe

The justfile SHALL provide a `test-linux` recipe that runs the full ksh26
test suite on x86_64-linux from a darwin host.

#### Scenario: Test on linux from darwin
- **WHEN** `just test-linux` is run on a darwin host with a linux builder available
- **THEN** nix builds `.#checks.x86_64-linux.default` with build logs printed,
  exercising the same test infrastructure as `just test` but on linux.

#### Scenario: Sanitizer variant
- **WHEN** `just test-linux-asan` is run on a darwin host with a linux builder
- **THEN** nix builds `.#checks.x86_64-linux.asan` with AddressSanitizer enabled.


### Requirement: Builder pre-flight check

Cross-platform recipes SHALL verify builder availability before invoking
`nix build`, providing actionable diagnostics on failure.

#### Scenario: Pre-flight passes with builder present
- **WHEN** the linux builder VM is running and reachable
- **THEN** the pre-flight check completes silently and the build proceeds.

#### Scenario: Pre-flight fails without builder
- **WHEN** no linux builder is configured in `/etc/nix/machines` or the builder
  is unreachable
- **THEN** the recipe prints a diagnostic message naming the missing prerequisite
  and exits non-zero without invoking `nix build`.

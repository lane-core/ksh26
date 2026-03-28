# ksh26 Identity

User-visible version strings, copyright attribution, and project branding.

**Status**: Done (ksh26-branding change, 2026-03-15).


## Requirements

### Requirement: Fork identity version string

The shell SHALL identify itself as ksh26 in all user-visible version output.
`SH_RELEASE_FORK` SHALL be `"26"` and `SH_RELEASE_SVER` SHALL be `"0.1.0-alpha"`.

#### Scenario: Version variable output
- **WHEN** a user evaluates `${.sh.version}` in ksh26
- **THEN** the output contains `26/0.1.0-alpha` (not `93u+m`)

#### Scenario: --version flag
- **WHEN** `ksh --version` is run
- **THEN** the output contains `26/0.1.0-alpha`

#### Scenario: shcomp version
- **WHEN** `shcomp --version` is run
- **THEN** the output contains `26/0.1.0-alpha`


### Requirement: Hardcoded ID strings

All `@(#)$Id:` strings in source files SHALL reference `ksh26` instead
of `ksh 93u+m`.

#### Scenario: No residual 93u+m in ID strings
- **WHEN** `grep -r 'ksh 93u+m' src/` is run excluding copyright headers
- **THEN** no `@(#)` ID strings match


### Requirement: Dual copyright attribution

Modified source files SHALL carry dual copyright attribution: the original
"Contributors to ksh 93u+m" line preserved, with a new "Contributors to
ksh26" line added.

#### Scenario: Modified file has both lines
- **WHEN** a source file is modified as part of ksh26 development
- **THEN** its copyright header contains both:
  - `Copyright (c) 20XX-20XX Contributors to ksh 93u+m`
  - `Copyright (c) 2024-2026 Contributors to ksh26`

#### Scenario: Unmodified files unchanged
- **WHEN** a source file has not been modified since the fork
- **THEN** its copyright header is unchanged (no ksh26 line added)


### Requirement: Test version guards

Test files that gate features on version string patterns SHALL use the
new `*26/*` pattern instead of `*93u+m/*`.

#### Scenario: Version-gated tests pass
- **WHEN** `just test` is run after the branding change
- **THEN** all tests that were passing before the change still pass
  (version guards correctly match the new format)


### Requirement: Package metadata identity

The flake.nix package description and documentation SHALL identify the
project as ksh26 without referencing ksh93u+m as the primary identity.

#### Scenario: Flake description
- **WHEN** `nix flake show` is run on the ksh26 flake
- **THEN** the description reads "ksh26" as the primary name

#### Scenario: Man page identity
- **WHEN** `man ksh` is viewed
- **THEN** the title and description reference ksh26

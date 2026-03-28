## MODIFIED Requirements

### Requirement: Two-path build model

The build system SHALL provide two paths: validation and iteration.

**Validation path** (nix-backed, content-addressed):
- `just build`, `just test`, `just build-asan`, `just test-asan`, `just check-all`
- **Cross-platform**: `just build-linux`, `just test-linux`, `just test-linux-asan`
  (requires linux builder — nix-darwin module or remote builder)
- Any source change → derivation hash changes → full rebuild
- No stale builds possible

**Iteration path** (local samu, devshell-only):
- `just test-one NAME`, `just debug NAME`, `just test-repeat NAME`
- Timestamp-based samu caching for sub-second rebuilds
- NOT for validation
- Local-only (no cross-platform iteration builds)

**Source**: notes/build-system.md, CLAUDE.md §Build system

#### Scenario: Content-addressed correctness
Running `just test` twice with no source changes completes in ≤5 seconds
(nix cache hit).

#### Scenario: Cross-platform validation
Running `just test-linux` on a darwin host with a linux builder exercises
the full test suite on x86_64-linux via nix remote build.

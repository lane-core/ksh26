## Why

ksh26 is an independent fork — not a tracking fork, no merges from upstream.
The codebase still identifies itself as "ksh 93u+m" in version output, man pages,
copyright headers, package metadata, and documentation. This creates confusion:
users see "93u+m" in `${.sh.version}` but are running a different project.
Clean the identity to match the reality.

## What Changes

- Change `SH_RELEASE_FORK` from `"93u+m"` to `"26"` — the single source of
  truth for fork identity. Version output becomes `26/0.1.0-alpha`.
- Update 2 hardcoded `@(#)` ID strings (nvtype.c, pty.c) from "ksh 93u+m" to "ksh26".
- Add dual-attribution copyright lines: existing "Contributors to ksh 93u+m"
  stays, new "Contributors to ksh26" line added in modified files.
- Update 5 test version guards from `*93u+m/*` to `*26/*` patterns.
- Rewrite README.md, NEWS, and man page (sh.1) ksh93u+m references.
- Update flake.nix descriptions and package version to `0.1.0-alpha`.
- Update CLAUDE.md fork description.

## Capabilities

### New Capabilities
- `ksh26-identity`: Version string, copyright attribution, and user-visible
  branding for the ksh26 fork.

### Modified Capabilities

## Impact

- **User-visible**: `${.sh.version}`, `--version`, man page header, `ksh --man` output
  all change from 93u+m to 26.
- **Scripts checking version**: Any script matching `*93u+m*` in the version
  string will stop matching. This is intentional — ksh26 IS a different shell.
- **Copyright headers**: ~493 files get a second attribution line (non-functional).
- **Test files**: 5 version guards updated (metadata gates, not assertions).
- **No ABI/API change**: Shell behavior, builtins, syntax all unchanged.

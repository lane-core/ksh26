## Context

The fork identity flows from a single macro in `version.h`:

```c
#define SH_RELEASE_FORK  "93u+m"
#define SH_RELEASE_SVER  "1.1.0-alpha"
```

`SH_RELEASE` composes these into the version string shown by `${.sh.version}`
and `--version`. Two files (nvtype.c, pty.c) have hardcoded `@(#)` ID strings
that bypass the macro. Everything else derives from these sources.

## Goals / Non-Goals

**Goals:**
- All user-visible identity says "ksh26" or "26", not "93u+m".
- Version format: `26/0.1.0-alpha` (matching flake.nix).
- Copyright: dual attribution — original "ksh 93u+m" line preserved,
  "ksh26" line added.
- Test version guards updated to match new format.
- Documentation (README, NEWS, man page, CLAUDE.md) updated.

**Non-Goals:**
- Renaming the `ksh93` command binary (stays `ksh`).
- Changing internal directory names (`src/cmd/ksh26/` already correct).
- Rewriting SPEC.md or REDESIGN.md references to "ksh93" — those discuss
  the upstream architecture and the name is historically accurate there.
- Touching `notes/` or `bugs/` directories (analysis material, not shipped).

## Decisions

### 1. Version macro change

```c
#define SH_RELEASE_FORK  "26"
#define SH_RELEASE_SVER  "0.1.0-alpha"
```

This produces `Version AJM 26/0.1.0-alpha 2026-03-15` in `${.sh.version}`.
The `SH_RELEASE_DATE` updates to the commit date.

**Why 0.1.0?** Matches flake.nix. The fork is pre-1.0 — the sfio rewrite
and polarity infrastructure are in progress. 1.0 signals stability.

### 2. Copyright dual attribution

In files we modify, add a ksh26 line below the existing one:

```c
/*
 * Copyright (c) 2020-2024 Contributors to ksh 93u+m
 * Copyright (c) 2024-2026 Contributors to ksh26
 */
```

The 2024 boundary is approximate (fork divergence began). Existing
"AT&T" and "93u+m" copyright lines stay — they're legally accurate
attribution for inherited code.

Files we haven't touched keep their existing headers. The ~493 file
count is for reference; only files modified in this change get the
new line.

### 3. Hardcoded @(#) strings

nvtype.c and pty.c have literal `"ksh 93u+m"` in their `@(#)` ID
strings. Change to `"ksh26"`:

```c
/* Before */ "@(#)$Id: type (ksh 93u+m) 2026-03-01 $\n"
/* After  */ "@(#)$Id: type (ksh26) 2026-03-15 $\n"
```

### 4. Test version guards

5 test files use `[[ ${.sh.version} == *93u+m/* ]]` to gate features.
Update to `*26/*`:

```ksh
# Before
[[ ${.sh.version} == *93u+m/* ]] && ...
# After
[[ ${.sh.version} == *26/* ]] && ...
```

These are feature-availability gates, not correctness assertions.
The fork has all the features they gate.

### 5. README.md approach

The README has two layers: a ksh26 header section and inherited
upstream documentation. Rewrite the header to be ksh26-primary.
In the inherited sections, change "KornShell 93u+m" to "ksh26"
where it refers to this project (not historical references).

### 6. Man page (sh.1)

The man page has conditional sections (`\nZ`-gated) for ksh vs ksh93
command names. Update the title and description to reference ksh26.
Keep the conditional structure — it's used for rksh (restricted) variants.

## Risks / Trade-offs

**[Scripts checking version]** → Any script matching `*93u+m*` stops
working. This is the point — ksh26 is a different project. No mitigation
needed; the break is intentional.

**[Copyright year boundary]** → 2024 as the fork-start year is approximate.
The exact date doesn't matter legally; it signals "around when the fork
diverged."

**[Bulk copyright changes in git blame]** → Only files modified in this
change get the new line, so blame stays clean for unmodified files.
For modified files, the copyright line change will show in blame but
the actual code changes are what matter.

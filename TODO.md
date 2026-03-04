# ksh26 TODO

Issues noticed during development. Each entry includes context for
why it matters and rough severity.

## Build system

- [ ] **Consider replacing iffe.sh** (low priority, post-sfio)
  4,322-line AT&T feature prober. 54 probes use `hdr`, `lib`, `mem`, `typ`,
  `tst`, `output{}`, `cat{}` primitives. ~70% are trivial (`hdr`/`lib`/`mem`/`typ`),
  replaceable with ~100 lines of shell helpers. The `output{}` blocks (~15-20
  probes) are the hard part. A custom ~300-line harness in configure.sh could
  cover everything, but risk is rediscovering edge cases iffe already handles.
  Alternatives considered: autoguess (preprocessor-only, can't do runtime probes),
  autosetup (Tcl — foreign language), acr (autoconf-but-smaller).

## Polarity infrastructure

- [x] **frame_depth counter** (SPEC.md Step 1)
  `int16_t frame_depth` in `Shell_t`, asserted in all four polarity
  frame functions.

- [x] **macro.c Degree 2→3 promotion**
  `subcopy` and `copyto` S_BRACT case now use full `Mac_t` struct
  save/restore, matching the established pattern in all other
  recursive expansion paths.

## POSIX Issue 8 compliance

- [x] `setitimer` → `timer_settime` fallback chain (timers.c)
- [x] `isascii` → inline `IS_ASCII` macro (macro.c)
- [x] `gettimeofday` → `clock_gettime` preferred path (timers.c)
- [x] `gettimeofday` (libast `tvgettime.c`) — already has
  `clock_gettime` → `gettimeofday` → `time()` fallback chain. No action needed.
- [x] `utime`/`utimes` (libast `tvtouch.c`) — already has
  `utimensat` → `utimes` → `utime` fallback chain. No action needed.
- [x] `ioctl` (libast/libcmd) — terminal control. Will never actually
  be removed by any real OS. Not actionable.

See `notes/posix8-deprecations.md` for the full audit.

## Sanitizers

- [ ] **LeakSanitizer false positives** (low priority, future work)
  ksh's global `Shell_t sh` struct and AT&T-era allocation patterns
  (vmalloc, stk) look like leaks to lsan. Options:
  - Annotate intentional "leaks" with `__lsan_ignore_object()`
  - Add proper teardown-before-exit for global state
  - Keep `detect_leaks=0` (current approach) and revisit after
    the vmalloc→malloc migration

## Dead subsystems

- [x] **Mount chain (mnt.c → fmtfs.c; fts_local() from fts.c)** — removed in
  dead code audit along with 34 other dead .c files, 4 headers, 7 man pages.

## Build system quality

- [ ] **Lint configure.sh** (medium priority)
  configure.sh has grown organically and hasn't had a systematic lint pass.
  ShellCheck with appropriate directives, dead code detection, and
  consistency review of probe patterns.

## Code quality tooling

- [ ] **Add shellcheck to treefmt** (low priority)
  Excluded from initial treefmt integration because `configure.sh` and
  `tests/infra/iffe.sh` use `local` (SC3043) and intentional word splitting
  on `$CFLAGS` (SC2086). Needs per-file `.shellcheckrc` or `shell=bash`
  directive to be useful. Revisit when build scripts stabilize.

- [ ] **Investigate include-what-you-use** (post-iffe, post-sfio)
  IWYU's worst failure modes (templates) don't apply to C, but ksh26's
  `FEATURE/` generated headers, iffe macros, and cross-platform `#if`
  conditionals would require extensive mapping files. Prerequisite:
  replace iffe.sh with configure.sh probes + single `config.h`. Revisit
  after that migration.

# ksh26 TODO

Issues noticed during development. Each entry includes context for
why it matters and rough severity.

## Build system

(none currently)

## Polarity infrastructure

- [ ] **frame_depth counter** (low priority, SPEC.md Step 1)
  Add a `frame_depth` integer to `Shell_t`. Increment on
  `sh_polarity_enter`, decrement on `sh_polarity_leave`. Assert
  proper nesting in debug builds. Catches frame mismatches (enter
  without leave, double leave) automatically. Cost: one integer,
  two assertions.

- [ ] **macro.c Degree 2→3 promotion** (low priority, future cleanup)
  `subcopy` (5 fields) and `copyto` S_BRACT case (3 fields) use
  field-by-field save/restore instead of full `Mac_t` struct save.
  Promoting to full-struct save (~5 lines per site) makes the
  discipline uniform across all recursive expansion paths. Not
  urgent — current code is correct.

## POSIX Issue 8 compliance

- [x] `setitimer` → `timer_settime` fallback chain (timers.c)
- [x] `isascii` → inline `IS_ASCII` macro (macro.c)
- [x] `gettimeofday` → `clock_gettime` preferred path (timers.c)
- [ ] `gettimeofday` (libast `tvgettime.c`) — already has
  `clock_gettime` → `gettimeofday` → `time()` fallback chain. No action needed.
- [ ] `utime`/`utimes` (libast `tvtouch.c`) — already has
  `utimensat` → `utimes` → `utime` fallback chain. No action needed.
- [ ] `ioctl` (libast/libcmd) — terminal control. Will never actually
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

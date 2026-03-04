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

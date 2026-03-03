# ksh26 TODO

Issues noticed during development. Each entry includes context for
why it matters and rough severity.

## Build system

(none currently)

## Sanitizers

- [ ] **LeakSanitizer false positives** (low priority, future work)
  ksh's global `Shell_t sh` struct and AT&T-era allocation patterns
  (vmalloc, stk) look like leaks to lsan. Options:
  - Annotate intentional "leaks" with `__lsan_ignore_object()`
  - Add proper teardown-before-exit for global state
  - Keep `detect_leaks=0` (current approach) and revisit after
    the vmalloc→malloc migration

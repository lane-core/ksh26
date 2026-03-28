# POSIX Issue 8 (IEEE 1003.1-2024) Deprecation Impact

Audit of ksh26 usage of interfaces removed or deprecated in POSIX.1-2024.

## Used — need migration

| Interface | Where | Status |
|-----------|-------|--------|
| `setitimer()` | `timers.c:66` | **Migrated**: `timer_settime` → `setitimer` → `alarm` fallback chain |
| `gettimeofday()` via `timeofday()` | `timers.c:48`, libast `tvgettime.c` | **Migrated** (timers.c): `clock_gettime` → `gettimeofday` → `time()`. libast: already has `clock_gettime` → `gettimeofday` → `time()` fallback chain — no action needed |
| `isascii()` | `macro.c:1176,1664` | **Migrated**: replaced with inline `IS_ASCII()` macro |
| `utime()`/`utimes()` | libast `tvtouch.c` | Already in fallback chain (`utimensat` → `utimes` → `utime`). No action needed |
| `ioctl()` | libast/libcmd (~12 sites) | Terminal control (`TIOCGWINSZ`, `TIOCSCTTY`, etc.). Will never actually be removed — every real OS needs it. No action |
| `test -a`/`-o` | `testops.c`, `test.c` | Already gated behind `SH_POSIX` flag. Correct behavior |

## Not used (clean)

These POSIX Issue 8 removed interfaces do not appear in ksh26 code:

| Interface | Notes |
|-----------|-------|
| `sighold`/`sigignore`/`siginterrupt`/`sigpause`/`sigrelse`/`sigset` | ksh uses `sigaction`/`sigprocmask` exclusively |
| `asctime_r`/`ctime_r` | Not used |
| `_setjmp`/`_longjmp` | ksh uses `sigsetjmp`/`siglongjmp` |
| `ftw`/`nftw` | Header reference only, no calls |
| `gets` | Not used |
| `tempnam` | Comment reference only |
| `rand_r` | Configure probe only, no runtime use |
| `pthread_setconcurrency`/`pthread_getconcurrency` | Not used |
| STREAMS APIs (`putmsg`, `getmsg`, etc.) | Not used |
| `toascii` | Not used |
| `ulimit` (C function) | Shell `ulimit` builtin uses `getrlimit`/`setrlimit` |

## Migration details

### `setitimer` → `timer_settime` (timers.c)

POSIX Issue 8 removes `setitimer()` and `getitimer()`. The replacement
is `timer_create()` + `timer_settime()`, which provides the same
interval timer functionality with nanosecond precision.

**Implementation**: Three-tier fallback in `setalarm()`:
1. `timer_settime()` — POSIX Issue 8 compliant, nanosecond precision
2. `setitimer()` — legacy POSIX, microsecond precision
3. `alarm()` — minimal fallback, second precision

The `timer_t` is created once via `timer_create(CLOCK_REALTIME)` with
`SIGEV_SIGNAL`/`SIGALRM`, matching ksh's existing signal architecture.
Cleaned up in `sh_timerdel(NULL)`.

**`getnow()` modernization**: Added `clock_gettime(CLOCK_REALTIME)` as
the preferred time source, falling back to `gettimeofday()` (via the
existing `timeofday()` macro) when unavailable.

**Platform behavior**:
- Linux (glibc ≥2.17, musl): `timer_create` + `clock_gettime` available, no `-lrt`
- macOS: No `timer_create`; `clock_gettime` available (10.12+); `setitimer` fallback activates
- Feature detection via `features/posix8` and `features/time` probes

### `isascii` → inline macro (macro.c)

POSIX Issue 8 removes `isascii()` from `<ctype.h>`. Replaced with:
```c
#define IS_ASCII(c)  ((unsigned)(c) <= 0x7f)
```
Semantically identical on all platforms. Defined locally in macro.c —
this is a lexer detail, not a public interface.

## References

- [POSIX 2024 removed interfaces (sortix.org)](https://sortix.org/blog/posix-2024/)
- [IEEE 1003.1-2024](https://pubs.opengroup.org/onlinepubs/9799919799/)

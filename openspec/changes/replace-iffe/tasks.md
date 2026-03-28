## 1. Probe helper functions

- [x] 1.1 `probe_hdr HDR` — compile test for `#include <HDR>`
- [x] 1.2 `probe_sys HDR` — compile test for `#include <sys/HDR>`
- [x] 1.3 `probe_lib FN [LIBS]` — link test for library function
- [x] 1.4 `probe_mem STRUCT FIELD HDR` — compile test for struct member
- [x] 1.5 `probe_typ TYPE HDR` — compile test for type existence
- [x] 1.6 `probe_dat SYM [HDR]` — link test for data symbol
- [x] 1.7 Log output helper: `probe_log INDEX TOTAL NAME RESULT` — self-contained line format

## 2. Tier 0: standards

- [x] 2.1 Translate `standards` probe to native `probe_ast_standards()`
- [x] 2.2 Verify output matches iffe on darwin

## 3. Tier 1: api, common, lib

- [x] 3.1 Translate `api` probe
- [x] 3.2 Translate `common` probe (complex: output{}, execute{}, run{})
- [x] 3.3 Translate `lib` probe (moderate: execute{}, link{}, status{}, cross{})
- [x] 3.4 Verify tier 1 outputs match iffe on darwin

## 4. Tier 2: system capabilities (12 probes)

- [x] 4.1 Translate `eaccess`, `aso`, `asometh` (moderate)
- [x] 4.2 Translate `sig` (shell script probe)
- [x] 4.3 Translate `fs` (complex: mem, mac, cat{}, compile{})
- [x] 4.4 Translate `sfio` (complex, sfio-rewrite target — translate as-is)
- [x] 4.5 Translate `sys`, `param` (trivial/moderate)
- [x] 4.6 Translate `tty` (moderate: hdr, lib, mem, cat{})
- [x] 4.7 Translate `map` (.c program probe)
- [x] 4.8 Translate `mmap` (complex: execute{}, output{})
- [x] 4.9 Translate `wchar` (complex: execute{}, compile{}, run{})
- [x] 4.10 Verify tier 2 outputs match iffe on darwin

## 5. Tiers 3-4: fcntl, limits

- [x] 5.1 Translate `fcntl` (.c program probe)
- [x] 5.2 Translate `limits` (.c program probe, depends on conflim.h)
- [x] 5.3 Verify outputs match

## 6. Tier 5: wide parallel band (17 probes)

- [x] 6.1 Translate `tv`, `tvlib`, `time` (time-related cluster)
- [x] 6.2 Translate `float`, `sizeof`, `align` (numeric/layout cluster)
- [x] 6.3 Translate `stdio` (complex, sfio target — translate as-is)
- [x] 6.4 Translate `dirent`, `wctype`, `nl_types`, `ccode` (misc)
- [x] 6.5 Translate `syscall`, `hack`, `tmlib` (moderate)
- [x] 6.6 Translate `ndbm`, `random`, `siglist`, `mode` (moderate/complex)
- [x] 6.7 Verify tier 5 outputs match iffe on darwin

## 7. Tier 6: final probes

- [x] 7.1 Translate `signal` (.c program)
- [x] 7.2 Translate `tmx`, `iconv`, `locale`, `libpath`
- [x] 7.3 Translate `sfinit` (.c program, sfio target — translate as-is)
- [x] 7.4 Verify tier 6 outputs match iffe on darwin

## 8. ksh26, libcmd, pty probes

- [x] 8.1 Translate ksh26 probes: `cmds`, `posix8` (trivial)
- [x] 8.2 Translate ksh26 probes: `time`, `poll`, `rlimits`, `fchdir` (moderate)
- [x] 8.3 Translate ksh26 probes: `locale`, `options`, `math`, `externs` (complex)
- [x] 8.4 Translate supplemental probes (NV_PID, extrabytes, GLOBCASEDET, etc.)
- [x] 8.5 Translate libcmd probes: `symlink`, `sockets`, `ids`, `utsname`
- [x] 8.6 Translate pty probe
- [x] 8.7 Verify all ksh26/libcmd/pty outputs match iffe

## 9. Remove iffe machinery

- [x] 9.1 Remove `run_iffe`, `run_iffe_ast`, INSTALLROOT/workdir setup from configure.sh
- [x] 9.2 Remove `IFFE` variable and iffe-related path setup (kept: math.sh still calls iffe directly)
- [x] 9.3 Keep `src/cmd/INIT/iffe.sh` in tree, keep `tests/infra/iffe.sh` for regression tests

## 10. Log output formatting

- [x] 10.1 Replace banners with `[N/56] PROBE lib/name ... result` lines
- [x] 10.2 Apply `[configure]` format to generation and infrastructure phases
- [x] 10.3 Verify output reads well in nix single-line paging

## 11. Cross-platform validation

- [x] 11.1 `just build` + `just test` — darwin 102/102 gate + 8/8 advisory
- [x] 11.2 `just build-linux` + `just test-linux` — linux 102/102 gate + 8/8 advisory
- [x] 11.3 Diff generated headers: all 56 byte-identical to iffe reference (darwin)
- [x] 11.4 Linux: time.h conditional fix for nanosleep, build succeeds

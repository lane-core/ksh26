# ksh93u+m POSIX Compliance Analysis

Comparison of ksh93u+m against POSIX Issue 8 (IEEE Std 1003.1-2024).
Organized by: features ksh pioneered that POSIX adopted, deviations worth
examining, and new POSIX requirements ksh doesn't yet implement.

## Features ksh93 pioneered, now standardized in Issue 8

These are ksh-isms that POSIX Issue 8 adopted. ksh93u+m already implements
all of them. No action needed except possibly adding test coverage for the
POSIX-specified edge cases.

| Feature | POSIX ref | ksh93 status | Notes |
|---------|-----------|-------------|-------|
| `$'...'` quoting | §2.2 | Full support | ksh invented this |
| `set -o pipefail` | §2.9.2 | Full support | ksh invented this |
| `;&` case fallthrough | §2.9.4.3 | Full support | ksh invented this |
| `{varname}>file` fd alloc | §2.7 | Full support | ksh invented this |
| `test -ef`, `-nt`, `-ot` | test(1) | Full support | long-standing ksh feature |
| `read -d delim` | read(1) | Full support | long-standing ksh feature |
| `cd -e` (with `-P`) | cd(1) | Full support | tested in T2-32 |
| `printf '%n$s'` positional | printf(1) | Full support | ksh extension |
| Glob excludes `.` and `..` | §2.14.3 | Full support since 93u+m | COMPATIBILITY item 2 |
| Brace expansion (optional) | §2.6.7 | Full support | `SHOPT_BRACEPAT` |

## Deviations from POSIX to examine

These are places where ksh93 behavior differs from what POSIX specifies.
Each needs evaluation: is the deviation essential to ksh identity, or is
it an accident that should be fixed (at least in `set -o posix` mode)?

### Already handled by `set -o posix`

These deviations are corrected when POSIX mode is active. Tested in
`tests/posix.sh`. No further action needed.

| Deviation | POSIX behavior | ksh default | posix.sh test |
|-----------|---------------|-------------|---------------|
| Brace expansion | Not required | On | lines 41-60 |
| IFS repeated whitespace | Each is a delimiter | Collapsed | lines 104-119 |
| fd > 2 cloexec | Inherited | Close-on-exec | lines 121-129 |
| `&>` redirection | Not recognized | Shorthand for `>f 2>&1` | lines 131-156 |
| `while <file` filescan | Not recognized | Splits into `$@` | lines 158-171 |
| `<>` default fd | stdin | stdout | lines 173-185 |
| `inf`/`nan` in arithmetic | Variable names | Float constants | lines 187-191 |
| Octal leading zero | Always octal | Decimal (except `--letoctal`) | lines 193-210 |
| `.` finds functions | Scripts only | Also finds `function` defs | lines 220-236 |
| `printf` arithmetic operands | Decimal/hex/octal only | Allows expressions | lines 238-250 |
| `test -a`/`-o` with `!`/`(` | Binary operators | Unary operators | lines 252-270 |
| `test -t` bare | String nonemptiness | `test -t 1` | lines 272-282 |

### Not yet handled — examine for `set -o posix`

These deviations exist in both normal and POSIX mode. Candidates for
fixing in POSIX mode without breaking default behavior.

#### Signal exit status: 256+N vs 128+N

ksh93 returns `256+signum` for processes killed by signal (documented in
man page, `SH_EXITSIG=0400` in shell.h). POSIX specifies `> 128` but the
convention is `128+signum`. bash, dash, and zsh all use 128+N.

**Assessment**: This is a deliberate ksh93 design choice that allows
distinguishing signal deaths from normal exits in the 129-255 range.
Changing it would break scripts that check for specific ksh93 exit codes.
Consider: POSIX mode could use 128+N while default mode keeps 256+N.

#### `read -S` CRLF handling

`read -S` (CSV mode) preserves `\r` from CRLF line endings in the last
field. The code sets `S_ERR` for `\r` intending to skip it, but the
`S_ERR` handler in `read.c:632` flushes accumulated field data before
the skip takes effect. RFC 4180 specifies CRLF as the record terminator.

**Assessment**: This is a bug, not a deviation. The code intends to skip
CR but has a sequencing error. Fix in `read.c` S_ERR handler: truncate
the accumulated value before flushing, or use `sfwrite` with explicit
length instead of `sfputr`.

#### `SIGCONT` auto-sent with `SIGTERM` to stopped jobs

In ksh93, `kill -TERM` to a stopped job automatically sends `SIGCONT`
first (so the process can actually receive and handle the TERM). In
`set -o posix` mode, this is disabled (`jobs.c:892`). POSIX doesn't
require or forbid this — it's an extension.

**Assessment**: The ksh93 default is arguably better behavior (a TERM to
a stopped job actually works). The POSIX mode disabling is fine. No change
needed.

#### `time` as reserved word

POSIX Issue 8 lists `time` as a word implementations may recognize as
reserved. ksh93 already treats it as reserved. No issue.

### Deviations that are essential to ksh identity

These should NOT be changed even in POSIX mode. They are core ksh features
that POSIX deliberately doesn't standardize.

| Feature | Notes |
|---------|-------|
| `typeset` / `nameref` / compound variables | Core ksh type system |
| Discipline functions (`.get`, `.set`, etc.) | No POSIX equivalent |
| `[[ ]]` extended test | POSIX has `test`/`[` only |
| `(( ))` arithmetic command | POSIX has `$(( ))` only |
| `select` loop | Not in POSIX |
| Process substitution `<(...)` | Not in POSIX |
| Here-strings `<<<` | Not in POSIX |
| `RANDOM`, `SECONDS` | Deliberately excluded from POSIX |
| `function name { }` syntax | POSIX only has `name() { }` |
| Associative arrays | Not in POSIX |
| `print` builtin | POSIX has `printf` and `echo` |
| `.sh.*` namespace | ksh-specific |
| `FPATH` / autoloading | Not in POSIX |

## New in POSIX Issue 8 — not yet in ksh93

Features POSIX Issue 8 added that ksh93u+m may not fully implement.

### Intrinsic utility category (§1.7)

POSIX Issue 8 defines a new "intrinsic" utility category between special
built-in and regular built-in. The 16 intrinsic utilities (`alias`, `bg`,
`cd`, `command`, `fc`, `fg`, `getopts`, `hash`, `jobs`, `kill`, `read`,
`type`, `ulimit`, `umask`, `unalias`, `wait`) are:
- Not subject to PATH search
- CAN be overridden by user functions (unlike special built-ins)

**ksh93 status**: ksh93's built-in system doesn't distinguish this
category. `cd`, `read`, etc. are regular built-ins found via PATH
position. Implementing the intrinsic category would require changes to
command lookup. Low priority — ksh93's built-in behavior is already
mostly compatible.

### `ulimit` expansion (§ulimit)

POSIX Issue 8 moved most of `ulimit` from XSI extension to Base, adding
`-H`, `-S`, `-a`, `-c`, `-d`, `-n`, `-s`, `-t`, `-v`.

**ksh93 status**: ksh93 already supports all of these. No action needed.

### `trap -p` formalization

POSIX Issue 8 formalized the `-p` option for `trap` to display current
trap settings.

**ksh93 status**: `trap -p` works. Verify output format matches POSIX
requirements.

### `readonly`/`export` restrictions on shell-managed variables

POSIX Issue 8 restricts marking `LINENO`, `OLDPWD`, `OPTARG`, `OPTIND`,
`PWD` as readonly.

**ksh93 status**: Needs investigation. ksh93 may allow `readonly LINENO`
which POSIX now prohibits.

### `$` followed by whitespace/nothing

POSIX Issue 8 (defect 1038) clarifies that a bare `$` followed by
space/tab/newline/nothing is treated as a literal `$`.

**ksh93 status**: Already behaves this way. No action needed.

### `;;&` case pattern fall-through (optional)

POSIX Issue 8 recognizes `;;&` (fall through to next matching pattern) as
an allowed extension. ksh93 implements `;&` (unconditional fall-through)
but not `;;&` (conditional fall-through — this is a bash extension).

**ksh93 status**: Not implemented. Low priority as it's optional in POSIX.

## Test coverage gaps for POSIX features

These POSIX-required behaviors lack dedicated tests. Some are partially
covered by existing tests but not explicitly verified.

| Feature | What to test | Priority |
|---------|-------------|----------|
| `$'...'` edge cases | `\e`, `\cX`, `\xHH` max 2 digits, `\u`/`\U` | Medium |
| `pipefail` with signals | Pipeline member killed by signal + pipefail | Medium |
| `{fd}>file` edge cases | `{fd}` with readonly var, invalid var name | Low |
| `printf '%n$s'` | Mixed numbered/unnumbered (should error) | Medium |
| `read -d ''` | NUL-delimited input (`find -print0` piped to read) | High |
| `test -ef` with symlinks | Symlink to same file, hardlinks, cross-device | Low |
| `cd -eP` failure mode | Exit status 1 when PWD can't be determined | Low (tested in T2-32) |
| Intrinsic utility behavior | Function overrides of `cd`, `read`, etc. | Medium |
| `readonly LINENO` rejection | Should error per Issue 8 | Medium |
| POSIX mode `<>` on stdin | Verify doesn't clobber | Low (tested in posix.sh) |

## References

- [POSIX Issue 8 (2024) Shell Command Language](https://pubs.opengroup.org/onlinepubs/9799919799.2024edition/utilities/V3_chap02.html)
- [POSIX Issue 8 Rationale](https://pubs.opengroup.org/onlinepubs/9799919799/xrat/V4_xcu_chap01.html)
- ksh93u+m `src/cmd/ksh93/COMPATIBILITY`
- ksh93u+m `src/cmd/ksh93/tests/posix.sh`
- ksh93u+m `README.md` policy: "Changes required for compliance with
  the POSIX shell language standard are implemented for the posix mode
  only to avoid breaking legacy scripts."

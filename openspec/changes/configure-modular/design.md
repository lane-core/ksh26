## Context

configure.sh (8,806 lines on replace-iffe-v2) is a verified-correct but
brute-force translation of iffe's 56 probes into native shell. The
translation expanded ~1,100 lines of iffe input 5x because it inlined
every abstraction iffe's interpreter provided generically (batch probing,
group cascades, result propagation, output guard management).

iffe itself (4,322 lines) is an unmaintained DSL interpreter with implicit
mutable state (`$usr`, `$can`, `$gothdr`, `$ifstack`). Its probe input
files are stranded in a proprietary format.

**The monolith is a behavioral reference, not a specification.** An
overfitting audit found: ~27 dead library probes (defines with no
consumers in `src/`), ~5 dead header probes, ~14 C23-redundant probes
(testing features guaranteed by the compiler), ~280 lines of dead platform
code (SunOS/AIX/IRIX branches), and 1 functional bug (`_mmap_worthy`
never emitted, permanently disabling sfio mmap). The new system must
detect only what ksh26 actually uses, not faithfully reproduce iffe's
full detection surface. See `notes/configure-audit.md` (Phase -1).

Probe classification of the monolith:
- **Category A** (18 probes, ~1,200 lines): Pure C — standalone .c files.
- **Category B** (11 probes, ~800 lines): Batch + 1-2 custom C programs.
- **Category C** (17 probes, ~3,000 lines): Shell-orchestrated C programs.
  C extractable; sequencing decomposes into driver operations.
- **Category D** (14, ~1,500 lines): 5 shell probes + 7 generators + 2 stubs.

## Goals / Non-Goals

**Goals:**
- Replace the monolith with a principled architecture modeled on skalibs
- Vendor modernish as portable shell foundation (no nix hard dependency)
- Separate probes (detect → sysdeps) from generators (read sysdeps → emit)
- Maintain byte-identical FEATURE output vs. the monolith (test oracle)
- Make adding a simple probe = adding a .c file + manifest entry

**Non-Goals:**
- Changing what's probed (same 56 features, same defines)
- Adopting autoconf, CMake, meson, or any external build tool
- Reimplementing modernish — we vendor the bundle
- Porting to non-POSIX systems

## Decisions

### 1. Skalibs architecture: probes are C files

The central principle: **probes are C programs, not shell code containing
C heredocs.** The shell driver compiles them and records results. The C
lives in .c files where editors, compilers, and LSPs understand it.

46 probes (Categories A+B) become standalone `build/probes/try_*.c` files.
When a probe fails, you run `cc -o try_foo try_foo.c` manually to debug.

For the ~120 simple sub-probes (hdr/lib/mem/typ/dat), the C is generic.
Batch helpers use iffe's vocabulary as shell function names:

```sh
# In a probe script — reads like iffe input, IS shell code
hdr fcntl dirent direntry filio
lib fork fsync getpagesize getrlimit getrusage gettimeofday
mem dirent.d_fileno dirent.d_ino stat.st_mtim.tv_nsec
typ clock_t "= uint32_t"
```

### 2. Flat text results (sysdeps)

Probe results go to `build/$HOSTTYPE/sysdeps`, a flat text file:

```
getrusage: yes
gettimeofday: yes
sizeof_pid_t: 4
ccode: ascii
platform: darwin
```

FEATURE headers are mechanically derived from sysdeps by `gen-features.sh`.
Decouples detection from output. The sysdeps file is inspectable, diffable,
and manually overridable (`--with-sysdep-K=V` for cross-compilation,
following skalibs's pattern).

### 3. Vendored modernish

modernish is vendored via `install.sh -B` in `build/lib/modernish/`
(~5,000 lines after bundling: comments stripped, interactive features
removed, 163 cap tests statically linked). ISC license.

What it provides:
- **Shell detection + fatal bug battery**: finds a good POSIX shell,
  rejects broken ones. Replaces ad-hoc shell detection.
- **`use safe`**: `IFS=''; set -fCu` baseline.
- **`harden`**: distinguishes "probe failed" from "compiler broken."
- **`var/local`**: proper local scoping. Replaces `_prefixed_variable`
  naming convention.
- **`sys/base/mktemp`**: portable mktemp with trap-based cleanup.
- **`sys/cmd/extern`**: finds commands with 126/127 discrimination.

What it doesn't provide (we write these):
- C compilation probes, sysdeps recording, FEATURE derivation, ninja
  generation, test infrastructure.

### 4. Probe/generator separation

Probes and generators are separate phases with `sysdeps` as the boundary:

**Phase 1: Probes** — detect capabilities, write to sysdeps.
  - C probes: `choose c|cl|clr` compiles try_*.c files
  - Batch probes: `hdr`/`lib`/`mem`/`typ`/`dat` helpers
  - Shell probes: locale, cmds, siglist (special cases)
  - Delegated probes: sig.sh, param.sh, libpath.sh (already separate)

**Phase 2: Generators** — read sysdeps, produce derived files.
  - `gen-features.sh`: sysdeps → FEATURE headers
  - `gen-math.sh`: sysdeps + math.tab → FEATURE/math + shtab_math[]
  - `gen-shopt.sh`: SHOPT.sh → shopt.h
  - `gen-headers.sh`: git.h, cmdext.h, cmdlist.h, ast_release.h
  - `gen-conf.sh`: conf.sh + lcgen → conflim.h/conftab.h/lc.h

**Phase 3: Emit** — produce build artifacts.
  - `ninja.sh`: emit build.ninja
  - `test-infra.sh`: emit test-env.sh + run-test

### 5. Manifest-driven probe scheduling

The probe registry (`manifest.sh`) declares name, tier, deps, type:

```sh
# NAME              TIER  DEPS                TYPE      OUTPUT
probe ast-standards   0   ""                  complex   "standards=ast_standards.h"
probe ast-api         1   "standards"         static    "api=ast_api.h"
probe ast-common      1   "standards"         complex   "common=ast_common.h"
probe ast-lib         1   "standards,common"  complex   "lib=ast_lib.h"
probe ast-sig         2   "common,lib"        delegate  "sig=sig.h"
probe ast-fs          2   "common,lib"        complex   "fs=ast_fs.h"
```

The driver topologically sorts by tier, runs probes in parallel within
tiers (background jobs + wait), copies FEATURE→header after each tier.

Probe types: `c`/`cl`/`clr` (standalone C), `batch` (hdr/lib/mem),
`complex` (shell function with multiple C programs), `delegate`
(external .sh/.c file), `static` (fixed text), `shell` (shell commands).

### 6. Group mechanism for variant cascades

iffe's `tst - -DN=1 - -DN=2 output{...}end` becomes `try_variants`:

```sh
try_variants build/probes/try_va_list.c -DN=1 -DN=2 -DN=3 -DN=4
```

Compiles+runs the same .c file with each flag in order, stops at first
success. Eliminates C body duplication that caused the va_list section
to expand 3x in the monolith.

### 7. Result propagation

iffe's implicit `$usr` propagation becomes explicit: the driver maintains
`$BUILDDIR/probe_defs.h`, regenerated from sysdeps after each tier. All C
compilations include it via `-include probe_defs.h`. Later probes see
prior results through the include, not invisible shell state.

## Risks / Trade-offs

**[Total line count larger than iffe]** → iffe+inputs=5,422. New system:
modernish (5,000 vendored) + our code (4,400) = 9,400. But our maintained
code drops from ~6,100 to ~4,400. modernish is tested, ISC-licensed,
maintained by the ksh93u+m maintainer.

**[Density regression vs. iffe]** → Simple probes: same density
(`hdr fcntl dirent` = 1 line). Complex probes: iffe's adjacent
test-and-output is more compact than shell + standalone .c files. We trade
density for transparency.

**[modernish maintenance risk]** → Feature-complete (0.17.x stable),
ISC-licensed. Patterns well-documented enough to self-maintain if needed.
Alternative (reimplementing portability) would be ~1,500 lines of
worse-tested code.

**[Propagation more explicit]** → `probe_defs.h` must be regenerated after
each tier. More work to set up, much easier to debug vs. iffe's invisible
`$usr`.

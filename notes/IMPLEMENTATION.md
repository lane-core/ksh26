# ksh26: Implementation Roadmap

## What this document is

The operational counterpart to [SPEC.md](../SPEC.md).

SPEC.md maps polarized type theory onto the existing codebase — where the
modes are, where the boundaries fall, what invariants hold at each crossing.
This document maps the same theory onto the **transformation sequence**: how
to take the dev branch from its current state (clean base with build
infrastructure) to a fully realized ksh26.

The `main` branch reached this destination through 2,158 organic commits —
discoveries, false starts, three failed sfio attempts, and course corrections.
Those commits are not the path; they're the expedition journal. This document
extracts the path: the minimal, dependency-ordered sequence of changes that
produces the same endpoint, informed by everything we learned along the way.

### The single principle

**Make implicit structure explicit.**

ksh93's interpreter has sequent calculus structure — two execution modes, boundary
crossings with state discipline, dual error conventions, a continuation stack —
but these patterns are maintained by convention, not by construction (SPEC.md §The
observation). The transformation makes them structural:

- C23 type enforcement makes flag namespaces, mode constants, and error returns
  compile-time distinct
- The polarity frame API makes boundary crossings explicit and uniform
- The sfio clean-room rewrite makes the buffer/syscall polarity boundary into
  C code organized by duploid role

Every layer of the transformation serves this principle. Reduction removes
noise that obscures the structure. Type foundation gives the compiler vocabulary
to enforce it. Polarity realization builds the infrastructure and rewrites the
substrate.

### Why fresh base, not cherry-pick

The dev branch descends from `build-again-build-better2` — a cleanroom re-port
of the build system from first principles. It shares no commit history with main
beyond the pre-fork `legacy` state. Cherry-picking main's commits would import:

- **Order dependencies from the expedition.** Main applied C23 changes late,
  after polarity infrastructure and library reduction had already modified the
  same files. Importing those commits means importing their merge conflicts and
  implicit assumptions about what the codebase looks like at each point.
- **Abandoned approaches.** The three sfio-replacement attempts left traces
  (abstraction layers, conditional compilation, shim headers) that were later
  removed. Cherry-picking the removal without the introduction is meaningless;
  cherry-picking both is waste.
- **Accidental coupling.** Commits on main often touch both infrastructure and
  substance (e.g., a polarity frame commit that also adjusts the build system
  for a file that was moved in a different commit). These don't transplant
  cleanly onto dev's different build system state.

The correct approach re-derives each transformation from the specification
(SPEC.md + REDESIGN.md), applying it to dev's clean base. The result is the
same — same API, same semantics, same structure — but the path is acyclic
and each step is independently verifiable.


## Layer 1: Reduction

**Character: strictly subtractive.** No new code, no behavioral changes. The
codebase shrinks from 591 .c files (measured on dev) toward the ~407 that
main has after all reductions (REDESIGN.md §Library reduction tracks
compiled object steps; the .c file counts are measured from the respective
worktrees). Every sub-phase is independently buildable (`just build &&
just test` passes after each).

The purpose is noise removal. Dead code obscures the structure we're trying
to make explicit. Removing it first means every subsequent layer operates on
a smaller, cleaner surface.

Reference: [REDESIGN.md §Library reduction](../REDESIGN.md#library-reduction),
[§Platform targeting](../REDESIGN.md#platform-targeting).


### 1a: Dead libast subsystems

Delete `src/lib/libast/stdio/` (75 files) and `src/lib/libast/hash/` (15
files).

**stdio/**: Full stdio reimplementation on top of sfio. Zero call sites in
ksh26 — the stdio compatibility layer exists only for hypothetical libast
consumers that want stdio semantics. Since ksh26 is the only consumer, and
we'll be rewriting sfio itself (Layer 4), the compatibility layer is pure
dead weight.

**hash/**: Pre-CDT hash table ADT, superseded by libcdt. Two survivors
(`strkey`, `strsum`) are string utilities that happen to live in the wrong
directory — relocate them to `src/lib/libast/string/` where they
semantically belong.

**dir/**: Directory-reading compat shims (opendir, readdir, seekdir, etc.).
6 .c files implementing POSIX directory primitives that every target
platform provides natively. Zero reason to carry our own. (New for dev —
not tracked in main's REDESIGN.md; identified by diffing dev's directory
tree against main's.)

Update `configure.sh` to remove source collection for all three
directories. Verify no transitive includes survive (`#include <hashpart.h>`,
`#include <dirlib.h>`, etc.).

**Build criterion:** `just build && just test` passes. Compile step count
drops by ~96 (75 stdio + 15 hash + 6 dir).


### 1b: Dead libraries

Delete `src/lib/libdll/` (12 files) and `src/lib/libsum/` (11 files).

**libdll**: Dynamic plugin loading. `SHOPT_DYNAMIC=0` means all call sites
are behind dead `#if` branches. Remove from `configure.sh`: feature tests,
source collection, compilation, link line. Remove vestigial
`#include <dlldefs.h>` from `cdtlib.h` (CDT uses none of its symbols).

**libsum**: AT&T checksum library (MD5, SHA, CRC). Only consumer was
`cksum.c` in libcmd, which is not in the static builtin set.

**Build criterion:** `just build && just test` passes. Two fewer library
archives in the link line.


### 1c: libcmd thinning

Reduce compiled sources from 47 to 11 files. Only the 9 static builtins
(basename, cat, cp, cut, dirname, getconf, ln, mktemp, mv) plus support
files (cmdinit.c, lib.c) need compilation. Remaining sources stay in tree
for potential future `builtin -f` dynamic loading.

This is a build system change (modify `configure.sh`'s source collection
glob for libcmd), not a file deletion. The unused sources are not dead
code — they're dormant code behind a disabled feature flag.

**Build criterion:** `just build && just test` passes. Compile step count
drops by ~37.


### 1d: libast/comp thinning

Delete 21 of 38 compatibility shims in `src/lib/libast/comp/`.

Nine are pure NoN (Nothing on Nothing) stubs — they compile to empty
functions on every target platform (all POSIX.1-2008+ systems). Twelve
compile to real code but are never linked (the linker drops them because no
ksh26 code calls them). The 17 survivors are AST interceptors that route
standard library calls through AST-specific wrappers (conformance checking,
locale awareness, error catalogs) and are actively linked.

Identifying which 21 to delete requires a link-time audit: build with
`-Wl,--gc-sections` (or equivalent) and diff the symbol table. Main's
REDESIGN.md records the specific files; re-verify against dev's link
output.

**Build criterion:** `just build && just test` passes. Compile step count
drops by ~21.


### 1e: Platform-specific code removal

Two phases, matching REDESIGN.md §Platform targeting.

**Phase 1 — iffe probes (~50 lines net):**
- Delete `features/omitted` (Windows .exe botch tests) and its
  `configure.sh` reference
- Strip QNX and Cygwin branches from `features/standards`
- Reduce `features/aso` from 634 → 52 lines: keep GCC `__sync_*` builtins,
  remove Solaris `<atomic.h>` (6 variants), Windows `Interlocked*`, AIX
  `fetch_and_add`, MIPS, x86/ia64/ppc inline assembly
- Remove HP-UX `pstat` probe and NeXT `nc.h` include from
  `features/externs` and `main.c`

**Phase 2 — source-level removal (~1,500 lines across ~41 files):**

| Platform | Guard macros | What goes |
|----------|-------------|-----------|
| Windows | `_WINIX`, `__CYGWIN__`, `__INTERIX`, `_WIN32` | Tilde expansion, path normalization, drive letters, .exe/.bat fallback, locale APIs, spawn modes, path conversion, Administrator→root mappings. Delete `lclang.h`, `ast_windows.h`. |
| IRIX | `__sgi` | Forced-unidirectional pipe workaround |
| SCO | `_SCO_COFF`, `_SCO_ELF` | mnttab guard, `KERNEL_*` sysconf entries |
| LynxOS | `__Lynx__` | `/etc/fstab` mount path |
| z/OS/MVS | `_mem_pgroup_inheritance` | Spawn path |
| UTS | `_UTS` | mnttab guard, sfvprintf size optimization |
| Universe (Pyramid/Sequent) | (various) | `b_universe()` builtin, `sh.universe` cache, `B_echo()` ucb detection, `univlib.h`/`univdata.c`, pathgetlink/pathsetlink universe-aware symlinks, astconf.c `getuniverse`/`setuniverse`, `features/cmds` probe |
| XBS5 | — | Superseded conf.tab entries (POSIX 2001+) |

Target platforms after reduction: Linux (glibc, musl), macOS/Darwin,
FreeBSD, NetBSD, OpenBSD, illumos/Solaris, Haiku. All x86_64 and aarch64
where applicable.

**Build criterion:** `just build && just test` passes on all target
platforms. Platform tiers documented in README.


### 1f: Security audit

After reduction, the codebase is small enough (~407 files) for a meaningful
security audit. Two targeted fixes from main's audit
([REDESIGN.md §Security hardening](../REDESIGN.md#security-hardening)):

1. **Signal handler malloc** (fault.c): `sh_fault()` called `malloc(1)` to
   test heap availability before crash cleanup — not async-signal-safe.
   Remove; always attempt `sh_done()`.
2. **Integer overflow** (streval.c): `staksize * (sizeof(Sfdouble_t) + 1)`
   overflow guard before `stkalloc`.

Document audit results in `notes/security/`.

**Build criterion:** `just build && just test` passes. ASAN clean
(`just build-asan && just test-asan`).


### Layer 1 summary

| Sub-phase | Files deleted | Compiled objects removed | Key directories |
|-----------|--------------|------------------------|-----------------|
| 1a | 96 | ~96 | libast/stdio/, libast/hash/, libast/dir/ |
| 1b | 23 | ~23 | libdll/, libsum/ |
| 1c | 0 | ~36 | (build system only) |
| 1d | 21 | ~21 | libast/comp/ (partial) |
| 1e | ~10 + inline | ~15 | (scattered + features/) |
| 1f | 0 | 0 | (code fixes only) |
| **Total** | **~150 files** | **~191 objects** | |

The file count delta (591 − 407 = 184) also includes sfio files eliminated
in Layer 4's rewrite (80 legacy files → 7 new files = net −73) and files
added by Layers 3+4 (polarity infrastructure, new headers). The sub-phase
totals above cover Layer 1 only.


## Layer 2: Type Foundation

**Character: declarative.** Declare what language we write, what standard we
target, what the compiler enforces. No behavioral changes to the shell; the
interpreter does exactly what it did before, but the code communicates its
contracts to the compiler.

This is the **first constructive change** after reduction. Every subsequent
layer — polarity infrastructure, sfio rewrite — is written against a C23
codebase from the start. This avoids the main-branch problem where C23 was
applied late, touching files that had already been modified by polarity work
and library reduction, creating unnecessary merge complexity.

Reference: [REDESIGN.md §C23 type enforcement](../REDESIGN.md#c23-type-enforcement).


### 2a: C23 dialect declaration

Set `-std=c23` in `configure.sh`. Require GCC 14+ or Clang 18+.

This is a gate: if the compiler doesn't support C23, the build fails with
a clear message rather than producing a binary with silently degraded type
safety. The gate is justified because every subsequent layer depends on C23
features — there is no useful intermediate state where "some files are C23
and some aren't."


### 2b: C23 features — downstream connections

Each C23 feature is adopted because it enables something specific in Layers
3 and 4. This is not modernization for its own sake.

#### Typed enums (`enum : type`)

Directly enables contract B1 (three flag namespaces become compile-time
distinct). sfio has three flag fields in `Sfio_t`:

- `_flags` (`unsigned short`) — public flags (SF_READ, SF_WRITE, SF_STRING, ...)
- `bits` (`unsigned short`) — private bits (SFIO_DCDOWN, SFIO_PEEK, ...)
- `mode` (`unsigned int`) — mode flags (SF_LOCK, SF_POOL, SF_GETR, ...)

Wrong-field bugs are silent in C99. With typed enums:

```c
enum sf_flags : unsigned short { SF_READ = 0x0001, ... };
enum sf_bits  : unsigned short { SFIO_DCDOWN = 0x0001, ... };
enum sf_mode  : unsigned int   { SF_LOCK = 0x0001, ... };
```

Cross-namespace mixing becomes a type error. The `sh_node_polarity[]` table
(SPEC.md §sh_exec polarity classification) uses `constexpr` typed enums for
compile-time polarity classification.

#### constexpr

Compile-time constants for:
- `sh_node_polarity[]` — polarity classification table (SPEC.md §Focalization)
- Longjmp severity ordering (fault.h `SH_JMP*` constants)
- sfio buffer size constants (`SF_BUFSIZE`, `SFSTRSIZE`)
- Flag values across all three sfio namespaces

These were `#define` macros or `const` variables. `constexpr` makes them
genuinely compile-time, usable in `static_assert` and array dimensions.

#### static_assert

Enforces structural invariants at compile time:
- Buffer invariant B2: field offset relationships in `Sfio_t`
- Struct layout compatibility between `Sfio_t` and `Stk_t` (stk depends
  on the three-pointer prefix `data`, `endb`, `next` matching)
- Polarity frame field offsets (if the struct layout changes, the
  assertions catch it before the code silently corrupts)

#### [[nodiscard]]

Applied to sfio I/O functions that return error indicators (sfwrite, sfclose,
sfread), allocation wrappers, and scope acquisition functions
(sh_polarity_enter returns void — but sh_scope_acquire returns a dictionary
that must not be dropped).

#### [[maybe_unused]]

Replaces the AT&T `NOT_USED(x)` macro and `(void)x` casts throughout.
Cleaner, compiler-standard, no runtime cost.

#### nullptr

Replaces `NULL` and `0`-as-pointer throughout. Eliminates the ambiguity
where `0` could be an integer or a null pointer (matters for variadic
functions and `_Generic`).

#### FAM (flexible array members)

Replaces zero-length arrays (`char data[0]`) in AT&T structs with standard
`char data[]`. Several `Sfio_t`-adjacent structures use this pattern.


### 2c: POSIX Issue 8 (IEEE 1003.1-2024)

Bundled with C23 because it's the same kind of change: declaring what APIs
we target. The fd-level primitives are probed at configure time and become
the substrate for Layer 4's sfio rewrite.

| Primitive | Replaces | Where used |
|-----------|----------|-----------|
| `pipe2(O_CLOEXEC\|O_CLOFORK)` | `pipe()` + `fcntl(FD_CLOEXEC)` | sflife.c, io.c |
| `dup3(old, new, O_CLOEXEC)` | `dup2()` + `fcntl(FD_CLOEXEC)` | sflife.c (sfsetfd), io.c |
| `ppoll(fds, n, ts, sigmask)` | `poll()` + `sigprocmask()` | sfread.c (sfpkrd) |
| `posix_close(fd, 0)` | `close(fd)` | sflife.c (sfclose) |
| `mkostemp(tmpl, O_CLOEXEC)` | `mkstemp()` + `fcntl()` | sflife.c (sftmp) |
| `O_CLOFORK` | manual FD_CLOEXEC | throughout (ksh forks constantly) |

**Not used:** FILE\*-based Issue 8 primitives (`open_memstream`, `fmemopen`,
`getdelim`). These reintroduce the exact problem that killed the v1 sfio
replacement — opaque buffers conflicting with sfio's direct pointer access.
See [sfio-rewrite-v2.md §Dangerous: FILE\*-based primitives](sfio-rewrite-v2.md#dangerous-file-based-primitives).

`configure.sh` probes for each primitive and provides fallbacks (e.g.,
`pipe` + `fcntl` when `pipe2` is unavailable). All fd-level Issue 8
primitives are available on Tier 1 targets (glibc 2.9+, musl, macOS 11+,
FreeBSD 10+, OpenBSD 5.7+, illumos).

**Build criterion:** `just build && just test` passes. No new warnings
(C23 is stricter about implicit conversions; any new warnings indicate
actual type confusion that should be fixed, not suppressed).


## Layers 3+4: Polarity Realization

**Character: constructive.** This is where the theory becomes code.

### The structural decision

The interpreter polarity infrastructure (Layer 3) and the sfio clean-room
rewrite (Layer 4) are treated as **paired manifestations of the same
theory**. SPEC.md's polarity framework isn't an abstraction imposed on
ksh — it's structure already present in both the interpreter (sh_exec's
mode distinctions, boundary crossings, continuation stack) and the I/O
substrate (sfio's buffer/syscall boundary, mode transitions, discipline
interception). The transformation makes both sides explicit simultaneously.

The document organizes them as **correspondence pairs**: each pair
addresses one aspect of the polarity framework, with an interpreter-side
change and an sfio-side change that realize the same theoretical structure
in their respective domains.

**Build order**: interpreter side of each pair first (it works with the
existing legacy sfio), then sfio files are written in a staging directory
(`src/lib/libsfio/`). When the full sfio reimplementation is complete and
passes all tests, the swap happens: delete `src/lib/libast/sfio/`, move
`src/lib/libsfio/` into its place, update `configure.sh`. The design is
interleaved even though the build is staged.

Reference: [SPEC.md](../SPEC.md) (theoretical foundation),
[REDESIGN.md §Foundations](../REDESIGN.md#foundations) (what main built),
[sfio-rewrite-v2.md](sfio-rewrite-v2.md) (sfio endgame specification),
[sfio-analysis/](sfio-analysis/) (12-file contract-level analysis).


### Pair 0: Vocabulary

**Interpreter side:** Annotate `sh_exec()` with polarity classification for
all 16 `case` labels. Add `sh_node_polarity[]` constexpr table to
`shnodes.h`. Establish error convention documentation (⊕ return vs ⅋
trap/continuation). No code changes — this is metadata that subsequent
pairs reference.

Classification from [REDESIGN.md §sh_exec polarity taxonomy](../REDESIGN.md#sh_exec-polarity-taxonomy):

| Classification | Node types |
|----------------|------------|
| Value (producers) | TARITH, TSW, TTST |
| Computation (consumers/statements) | TFORK, TPAR, TFIL, TLST, TAND, TORF, TIF, TTIME |
| Mixed (internal polarity boundaries) | TCOM, TFOR, TWH, TSETIO, TFUN |

**sfio side:** Write `sfio.h` and `sfhdr.h` — the contract headers.
Full `Sfio_t` struct definition with C23 typed enums for the three flag
namespaces (B1). `static_assert` for the five-pointer buffer invariant
field offsets (B2). `static inline` replacing fast-path macros (sfputc,
sfgetc, sffileno, sfvalue, sfeof, sferror, sfclrerr, sfstacked, sfstropen,
sfstruse, sfstrclose). `[[nodiscard]]` on I/O functions.

**Correspondence:** Both establish vocabulary — modes, boundaries, flag
taxonomy — that all subsequent pairs use. Neither produces executable code
that differs from the current behavior.

**Build criterion:** `just build && just test` passes. (Interpreter
annotations are comments and constexpr tables; sfio headers exist in
staging but aren't linked yet.)

Reference: [sfio-analysis/02-flags-and-modes.md](sfio-analysis/02-flags-and-modes.md),
[sfio-analysis/03-buffer-model.md](sfio-analysis/03-buffer-model.md).


### Pair 1: Mode Transitions

**Interpreter side:** Implement the polarity frame API in `shell.h` and
`xec.c`:

```c
struct sh_polarity
{
    char        *prefix;
    Namval_t    *namespace;
    struct sh_scoped st;
    Dt_t        *var_tree;
};

void sh_polarity_enter(struct sh_polarity *frame);
void sh_polarity_leave(struct sh_polarity *frame);
```

`sh_polarity_enter` saves `sh.prefix`, `sh.namespace`, `sh.st`, and
`sh.var_tree`, then clears `prefix` and `namespace`. `sh_polarity_leave`
restores — but with trap slot preservation: snapshots live trap slots
before restoring `sh.st`, writes them back after. This prevents handler-
side trap mutations (e.g., `trap - DEBUG`) from being silently overwritten
by the blanket struct restore.

Convert the first three call sites: `sh_debug()`, `sh_fun()`, `sh_trap()`.
These are the polarity boundary crossings — value→computation transitions
where the interpreter shifts from word expansion into trap/discipline/
environment execution.

**sfio side:** Write `sfmode.c` — the shift mediator. `_sfmode()` runs at
every operation entry, mediating between the stream's current state and the
caller's expected polarity. Handles:

1. GETR restore (`f->next[-1] = f->getr` — undo STRING mode observation)
2. Mode transitions (WRITE→READ, READ→WRITE — drain/reset/seek)
3. Initialization (SF_INIT → allocate buffer, set initial mode)
4. Pool management (SF_POOL → move to head of pool)
5. Lock acquisition

Also: `sfsetbuf`, `sfclrlock`, `_sfsetpool`, `_sfcleanup`. ~250 lines.

**Correspondence:** Both mediate mode transitions. The polarity frame
mediates value→computation shifts in the interpreter; `_sfmode()` mediates
read↔write shifts in the I/O substrate. Both restructure state at
boundaries without producing or consuming data. The structural parallel is
"has the structure of" — same failure discipline (wrong mode = corruption),
but the transitions are within-stream state changes, not inter-component
cuts (see [sfio-rewrite-v2.md §C4](sfio-rewrite-v2.md#c4-buffer--polarity-boundary)).

**Build criterion:** Interpreter side: `just build && just test` passes with
legacy sfio. sfio side: `sfmode.c` compiles independently against the new
headers.

Reference: [REDESIGN.md §The polarity frame API](../REDESIGN.md#the-polarity-frame-api),
[sfio-analysis/06-lifecycle.md §_sfmode](sfio-analysis/06-lifecycle.md).


### Pair 2: Context Management

**Interpreter side:** Three changes:

1. **Scope representation unification.** `sh.var_tree` and
   `sh.st.own_tree` encode the same concept (current scope dictionary).
   Introduce `sh_scope_set()` (static inline, `defs.h`) that atomically
   updates both. Convert the three sites that change scope identity without
   syncing: `sh_scope` (name.c), `sh_unscope` (name.c), `sh_funscope`
   (xec.c).

2. **Continuation classification.** Classify all ~27 `sh_pushcontext` sites
   by polarity role: polarity boundary, scope boundary, computation-only,
   or indirect. Only `sh_debug`, `sh_fun`, and `sh_trap` are polarity
   boundaries; the rest are classified and annotated but unchanged.

3. **Compound assignment longjmp safety.** `nv_setlist` (name.c) temporarily
   mutates global `L_ARGNOD` to act as a nameref to stack-local state, then
   calls `sh_exec`. If `sh_exec` longjmps, `L_ARGNOD` dangles. Fix: register
   the restore in `sh_exit()` (fault.c) — the single funnel all error paths
   pass through. No added checkpoint, no topology change.

**sfio side:** Write `sflife.c` — lifecycle and identity operations.
`sfnew`, `sfopen`, `sfclose`, `sfstack`, `sfswap`, `sfsetfd`,
`sfsetfd_cloexec`, `sfset`, `sfseek`, `sftell`, `sfsize`, `sfsync`,
`sfpurge`, `sftmp`, `sfpool`, `sfnotify`. ~450 lines.

Key contract: `sfsetfd` uses `fcntl(F_DUPFD, newfd)` — lowest available fd
≥ newfd, not necessarily exactly newfd (B6). `sftmp` implements the
string→file polarity shift when buffer exceeds size threshold (C3 in
sfio-rewrite-v2.md — the cleanest genuine polarity shift in sfio: a value
substrate is promoted to a computation substrate while preserving stream
identity).

POSIX Issue 8 primitives enter here: `posix_close()` for sfclose,
`mkostemp(O_CLOEXEC)` for sftmp, `dup3()` for sfsetfd. The `sfnotify`
callback fires at the same lifecycle points as legacy — this is contract
B11, and getting it wrong desynchronizes ksh's three parallel arrays
(`sh.sftable`, `sh.fdstatus`, `sh.fdptrs`).

**Correspondence:** Both manage context — introducing, eliminating, and
transferring identity. Scope unification makes the interpreter's context
representation self-consistent; `sflife.c` makes the I/O substrate's
context operations (creation, destruction, identity exchange) correct and
race-free. Structural rules in the duploid framework.

**Build criterion:** Interpreter side: `just build && just test` passes.
sfio side: `sflife.c` compiles against the new headers + `sfmode.c` and
passes unit tests for `sfnew`/`sfclose`/`sfstack` lifecycle sequences.

Reference: [REDESIGN.md §Scope representation unification](../REDESIGN.md#scope-representation-unification),
[REDESIGN.md §Compound assignment longjmp safety](../REDESIGN.md#compound-assignment-longjmp-safety),
[sfio-analysis/06-lifecycle.md](sfio-analysis/06-lifecycle.md),
[sfio-analysis/10-ksh-integration.md §The three parallel arrays](sfio-analysis/10-ksh-integration.md).


### Pair 3: Interception

**Interpreter side:** Convert remaining polarity boundary call sites:
`sh_getenv()`, `putenv()`, `sh_setenviron()` (all in name.c). These are
environment lookups — the interpreter shifts into computation mode to
resolve environment variables. Add runtime depth tracking (`frame_depth`
counter in `Shell_t`, asserted in all four enter/leave functions).

**sfio side:** Write `sfdisc.c` — the interception layer. `sfdisc`,
`_sfexcept`, `sfraise`, `Dccache_t`. ~200 lines.

The critical contract is Dccache (B9 area): when a discipline is pushed
during a read, buffered data predating the new discipline must be replayed
through it, not served directly. This is the non-associativity witness —
the composition equation `(h ○ g) • f ≠ h ○ (g • f)` maps exactly (see
[sfio-rewrite-v2.md §C2](sfio-rewrite-v2.md#c2-dccache--non-associativity-witness)).
Data that has crossed to value mode (buffered) cannot be reprocessed
through a new computation context (new discipline) without explicit
mediation.

ksh's discipline configurations to test against: `outexcept` (io.c, write
error handling on stdout), `slowexcept` (slow device read), `slowread`
(TTY read with signal handling), `piperead` (pipe read with interrupt
support), `pipeexcept` (pipe-specific error handling).

**Correspondence:** Both intercept at mode crossings. Polarity frames
intercept interpreter-level value→computation transitions; disciplines
intercept I/O-level buffer→syscall transitions. Both are boundary
mediators — they don't produce or consume data, but they observe and
potentially redirect the crossing. The non-associativity witness (Dccache)
is the closest structural identification between the two domains
([sfio-rewrite-v2.md §C2](sfio-rewrite-v2.md#c2-dccache--non-associativity-witness)).

**Build criterion:** Interpreter side: `just build && just test` passes.
sfio side: `sfdisc.c` compiles against headers + `sfmode.c` + `sflife.c`.
Discipline push/pop sequences work correctly. Dccache replay tested with
synthetic buffered data.

Reference: [REDESIGN.md §Converted call sites](../REDESIGN.md#converted-call-sites),
[REDESIGN.md §Runtime depth tracking](../REDESIGN.md#runtime-depth-tracking-specmd-step-1),
[sfio-analysis/07-disciplines.md](sfio-analysis/07-disciplines.md).


### Pair 4: Positive Operations

**Interpreter side:** Implement within-value prefix isolation — the
`sh_prefix_enter`/`sh_prefix_leave` API for the 5 sites that do prefix
management without crossing a polarity boundary:

| # | File:function | Operation guarded |
|---|---------------|-------------------|
| 1 | name.c:nv_setlist | sh_mactrim (macro expansion of assignment value) |
| 2 | name.c:nv_setlist | nv_open (nested array subscript resolution) |
| 3 | name.c:nv_open | nv_putval (value assignment with NV_STATIC check) |
| 4 | name.c:nv_rename | nv_open (compound ref resolution) |
| 5 | xec.c:sh_exec (TFUN) | nv_open (discipline function lookup) |

These stay within value mode — they prevent inner name resolution from
inheriting the outer compound assignment context. Deliberately lighter than
a polarity frame (no `sh.st` save).

**sfio side:** Write `sfwrite.c` — positive / producer operations.
`sfwr`, `_sfflsbuf`, `sfwrite`, `sfputr`, `sfnputc`. ~350 lines.

Key contracts:
- **NUL sentinel (B4):** sfio does NOT guarantee NUL termination. The only
  incidental NUL is in sfputr's byte-at-a-time loop. stk manages its own
  sentinel via `STK_SENTINEL`. Do NOT add NUL to sfio write functions — it
  would break stk's `_stkseek`.
- **Line buffering trick (B10):** When `SF_LINE` is set, `_endw = _data`.
  Every `sfputc` triggers the slow path, which checks for `'\n'` and
  flushes. `HIFORLINE` (128 bytes) threshold: large writes skip line-scan.
- **LOCKR release:** `sfwrite(f, buf, 0)` releases a peek lock acquired by
  `sfreserve(..., SF_LOCKR)`. This is polarity mixing by design — a
  nominally positive call performing negative-polarity state management.

**Correspondence:** Both handle production without mode change. Prefix
guards protect value-mode assignments from context leakage; sfwrite
produces data into buffers without triggering mode transitions (unless
the buffer fills and a flush is needed — that's the write-path's own
boundary crossing, handled by `sfwr` → discipline chain).

**Build criterion:** Interpreter side: `just build && just test` passes.
sfio side: `sfwrite.c` compiles against headers + `sfmode.c` + `sflife.c` +
`sfdisc.c`. Write operations work for fd-backed and string streams.

Reference: [REDESIGN.md §Within-value prefix isolation](../REDESIGN.md#within-value-prefix-isolation),
[sfio-analysis/05-write-path.md](sfio-analysis/05-write-path.md).


### Pair 5: Negative Operations

**Interpreter side:** Promote `subcopy()` and `copyto()` S_BRACT case in
macro.c from field-by-field save/restore (Degree 2) to full `Mac_t` struct
save/restore (Degree 3). This matches the established pattern in
`sh_mactrim`, `sh_macexpand`, `sh_machere`, `mac_substitute`, and
`comsubst`.

Caveat: `mp->dotdot` must survive the restore in `subcopy()` — the caller
reads it immediately after return. Capture before struct copy, write back
after.

**sfio side:** Write `sfread.c` — negative / consumer operations.
`sfrd`, `_sffilbuf`, `sfread`, `sfreserve`, `sfgetr`, `sfungetc`,
`sfpkrd`, `sfmove`, `_sfrsrv`. ~500 lines.

This is the hardest file. All three v1 failures manifested here.

The sfreserve contract is the nucleus — 5+ calling patterns that ksh
depends on ([sfio-rewrite-v2.md §The sfreserve contract](sfio-rewrite-v2.md#the-sfreserve-contract-nucleus)):

| Pattern | Call | Semantics |
|---------|------|-----------|
| Peek | `sfreserve(f, 0, 0)` | Non-consuming peek. **Do NOT advance f->next.** |
| Peek/lock | `sfreserve(f, SF_UNBOUND, SF_LOCKR)` | Peek + lock. Release via `sfread(f,buf,0)`. |
| Consume | `sfreserve(f, SF_UNBOUND, 0)` | Advance f->next by available amount. |
| Reserve N | `sfreserve(f, n, SF_LOCKR)` | Ensure ≥ n bytes available, lock. |
| Assess | `sfreserve(f, -size, SF_LOCKR)` | Negative size with special handling. |

Additional contracts:
- **rsrv sharing (B5):** Shared side buffer between sfgetr and sfreserve.
  `rsrv->slen < 0` = partial record, `rsrv->slen == 0` = complete.
- **GETR destructive NUL (B7):** sfgetr with SF_STRING overwrites separator
  with '\0', sets `f->getr` for later restore by `_sfmode()`.
- **sfungetc sfstack fallback (B8):** When fast path fails, creates a string
  stream and pushes via `sfstack`. `_uexcept` discipline auto-pops.
- **sfpkrd timed reads:** Uses `ppoll()` (Issue 8) for atomic signal mask +
  timeout.

The LOCKR protocol has thunk structure (↓N in SPEC.md's vocabulary):
`sfreserve(..., SF_LOCKR)` suspends the fill machinery into a storable
value (pointer + length); the releasing `sfread(f, buf, 0)` forces it. See
[sfio-rewrite-v2.md §C1](sfio-rewrite-v2.md#c1-lockr--thunk-↓n).

**Correspondence:** Both handle observation/demand. macro.c's degree
promotion makes the expansion pipeline's save/restore discipline uniform;
sfread.c implements the consumer side of the I/O substrate. Both deal with
the fundamental challenge of negative polarity: consuming data may require
shifting into computation mode (filling buffers, evaluating command
substitutions) — and the save/restore discipline must be correct across
those shifts.

**Build criterion:** Interpreter side: `just build && just test` passes.
sfio side: all 5 sfreserve patterns pass unit tests. sfgetr record
accumulation works. sfpkrd timed reads work. LOCKR acquire/release cycle
is clean.

Reference: [REDESIGN.md §macro.c Degree 2→3 promotion](../REDESIGN.md#macroc-degree-23-promotion),
[sfio-analysis/04-read-path.md](sfio-analysis/04-read-path.md),
[sfio-rewrite-v2.md §The sfreserve contract](sfio-rewrite-v2.md#the-sfreserve-contract-nucleus).


### Pair 6: Format and Optimization

**Interpreter side:** Three safe optimizations enabled by the polarity
boundary framework ([REDESIGN.md §Safe optimizations](../REDESIGN.md#safe-optimizations)):

1. **Empty DEBUG trap early exit.** `sh_debug` is called on every command
   when a DEBUG trap is set. When the trap string is empty, the entire
   polarity frame, continuation, and string construction are pure overhead.
   Add `if(!*trap) return 0;` after the re-entrancy guard. In the sequent
   calculus, an empty trap body means the cut reduces to identity — no
   boundary crossing occurs.

2. **Lightweight polarity frame (sh_polarity_lite).** `sh_debug` creates an
   outer frame; `sh_trap` (called from within `sh_debug`) creates an inner
   frame. The inner frame already does full `sh.st` save/restore, so the
   outer frame's full copy is redundant. Weakened outer boundary principle:
   `struct sh_polarity_lite` (~24 bytes) saves only prefix, namespace,
   and var_tree. Trap preservation (trap[], trapdontexec) is delegated
   to `sh_trap`'s inner full frame.

3. **Scope dictionary pool.** Function calls allocate/free CDT dictionaries
   in `sh_scope`/`sh_unscope`. Scopes are LIFO, so a fixed-size pool (8
   entries) amortizes the cost. `sh_scope_acquire()` pops from pool or falls
   back to `dtopen`. `sh_scope_release()` calls `dtclear()` and pushes to
   pool or falls back to `dtclose`.

**sfio side:** Write `sfvprintf.c` — the format engine. `sfvprintf`,
`sfprintf`, `sfprints`, format tables. ~700 lines.

The biggest single function. ksh's `print` and `printf` builtins call
`sfprintf(outfile, "%!", &pdata)` where pdata contains an `extf` callback
for ksh-specific format specifiers (%b, %q, %H, %T, %Z, %P, %R, %B, %Q).

The %! protocol ([sfio-rewrite-v2.md §The sfprintf/%! format engine](sfio-rewrite-v2.md#the-sfprintf-format-engine)):
1. Parse format string until `%!` → read `Sffmt_t*` from va_args
2. If `ft->form` set, push format context (FMTSET — save position + args)
3. For each `%` directive, call `ft->extf(f, &argv, ft)`
4. extf return: <0 = pop, >0 = extf already wrote, 0 = use argv
5. Handle standard specifiers via libc `vsnprintf` on a temp buffer

Key contract: **shadow pointer optimization (B9).** `sfvprintf` caches
`f->next` in local `d` and `f->endb` in `endd` for the hot loop. Flushes
back via `SFEND(f)` before any actual I/O. Code that reads `f->next`
without SFEND sees stale data.

The FMTSET/FMTGET pattern has the structure of a polarity frame (loose
analogy — [sfio-rewrite-v2.md §C5](sfio-rewrite-v2.md#c5-fmtsetfmtget--polarity-frame)):
save format state, call extf (computation), read back modified state. The
organizational parallel guides where to put save/restore boundaries; the
formal correspondence is looser than the interpreter's polarity frames.

The reimplementation delegates standard specifiers to libc `vsnprintf`:
~700 lines vs legacy's 1,434 lines.

**Correspondence:** Both address hot-path performance within the polarity
framework. The interpreter optimizations are safe precisely because the
polarity boundary framework makes frame nesting provably correct. The
format engine's shadow pointer optimization is safe because the SFEND
discipline is uniform. Both are polarity-aware optimizations: they exploit
structural knowledge about what state is invariant across what boundaries.

**Build criterion:** Interpreter side: `just build && just test` passes.
48/58 test files exercise sfprintf → must all pass. %! protocol works with
ksh's `extend()` callback in print.c.

Reference: [REDESIGN.md §Safe optimizations](../REDESIGN.md#safe-optimizations),
[sfio-analysis/05-write-path.md §sfvprintf](sfio-analysis/05-write-path.md),
[sfio-rewrite-v2.md §The sfprintf/%! format engine](sfio-rewrite-v2.md#the-sfprintf-format-engine).


### Pair 7: Encoding (self-contained)

**Interpreter side:** No corresponding interpreter change.

**sfio side:** Write `sfvle.c` — neutral encoding operations. `sfputl`,
`sfgetl`, `sfputu`, `sfgetu`, `sfputd`, `sfgetd`, `sfputm`, `sfgetm`.
~150 lines.

Pure encoding/decoding — no mode interaction, no dependency on the rest of
the library beyond basic buffer access. Self-contained and can be
implemented at any point; listed last because nothing depends on it.

**Build criterion:** Encoding round-trips are correct for all integer sizes
and edge cases (0, 1, -1, INT_MAX, INT_MIN, LLONG_MAX, LLONG_MIN).


### The swap

Once all 7 sfio files pass their unit tests and the full integration test
suite passes with the staging build:

1. Delete `src/lib/libast/sfio/` (~80 .c files, ~12,800 lines)
2. Move staging directory contents into `src/lib/libast/sfio/` (or a new
   location — the name is less important than the build integration)
3. Update `configure.sh` source collection
4. Delete `ast_stdio.h` interception header
5. `just build && just test` — full validation
6. `just build-asan && just test-asan` — sanitizer validation

**Success criteria** (from [sfio-rewrite-v2.md §Success criteria](sfio-rewrite-v2.md#success-criteria)):
1. All tests pass (current count: 115+)
2. ASAN clean
3. Nix sandbox passes
4. Old sfio/ deleted
5. ast_stdio.h eliminated
6. Total I/O code ≤ 3,500 lines (vs ~12,800)
7. Zero ksh call site changes (same API)
8. All fd creation uses Issue 8 atomic primitives where available


### Pair summary table

| Pair | Interpreter side | sfio side | Precision | Build gate |
|------|-----------------|-----------|-----------|------------|
| 0 | sh_exec classification, error conventions | sfio.h, sfhdr.h (contracts) | Vocabulary | Compiles |
| 1 | Polarity frame API (sh_debug, sh_fun, sh_trap) | sfmode.c (shift mediator) | Structural | Tests pass (interpreter); compiles (sfio) |
| 2 | Scope unification, continuation classification, longjmp safety | sflife.c (lifecycle/cuts) | Structural | Tests pass; lifecycle unit tests |
| 3 | Remaining call sites, depth tracking | sfdisc.c (interception) | Near-identification (Dccache) | Tests pass; discipline unit tests |
| 4 | Prefix guards | sfwrite.c (positive) | Structural | Tests pass; write unit tests |
| 5 | macro.c degree promotion | sfread.c (negative) | Structural (LOCKR ↔ thunk) | Tests pass; sfreserve 5-pattern tests |
| 6 | Safe optimizations | sfvprintf.c (format) | Loose (FMTSET ↔ frame) | Tests pass; 48/58 printf tests |
| 7 | — | sfvle.c (neutral) | Self-contained | Encoding round-trips |


## Verification

### Per-layer criteria

**Layer 1 (Reduction):** Each sub-phase gates on `just build && just test`.
File count verified against REDESIGN.md targets. No behavioral changes —
test output is identical before and after each sub-phase.

**Layer 2 (Type Foundation):** `just build && just test` with `-std=c23`.
Zero new warnings — any C23-triggered warning indicates real type confusion.
`static_assert` failures are compile errors (caught automatically). POSIX
Issue 8 probes verified on all Tier 1 platforms.

**Layer 3+4 (Polarity Realization):** Each pair gates on:
- Interpreter side: `just build && just test` passes (full suite)
- sfio side: unit tests pass for the pair's functions
- Integration: after the swap, `just build && just test` passes

### End-to-end criteria

After all layers:

1. `just build && just test` passes (≥115 test stamps)
2. `just build-asan && just test-asan` is clean
3. `just check-all` passes (nix flake check — tests + formatting)
4. Source file count ~407 .c files (from ~591)
5. sfio line count ≤ 3,500 (from ~12,800)
6. All fd creation uses Issue 8 atomic primitives
7. Zero ksh call site changes relative to the sfio API
8. Platform tiers verified: at minimum Linux x86_64 and Darwin arm64

### Contract traceability

Every implementation contract from [sfio-rewrite-v2.md §Implementation
contracts](sfio-rewrite-v2.md#implementation-contracts) must be traceable to
a specific pair and a specific test:

| Contract | Pair | What it tests |
|----------|------|---------------|
| B1 (flag namespaces) | 0 | C23 typed enums → compile-time enforcement |
| B2 (buffer invariant) | 0 | static_assert on field offsets |
| B3 (lock asymmetry) | 1 | sfmode.c SFLOCK/SFOPEN implementation |
| B4 (NUL sentinel) | 4 | sfwrite does NOT add NUL; stk tests still pass |
| B5 (rsrv sharing) | 5 | Interleaved sfgetr/sfreserve sequences |
| B6 (sfsetfd F_DUPFD) | 2 | sflife.c sfsetfd with occupied fd targets |
| B7 (GETR destructive NUL) | 5 | sfgetr SF_STRING mode → separator restored by _sfmode |
| B8 (sfungetc sfstack) | 5 | sfungetc fast-path miss → string stream push/pop |
| B9 (shadow pointer) | 6 | sfvprintf SFEND discipline → f->next consistency |
| B10 (line buffering) | 4 | SF_LINE + sfputc → newline triggers flush |
| B11 (ksh integration) | 2 | sfnotify fires at correct lifecycle points |


## Risk Assessment

Three sfio replacement attempts failed. Each failure maps to a specific
contract violation and informs a specific mitigation.

### Risk 1: sfreserve calling patterns

**What went wrong (v1):** `sfreserve(f, 0, 0)` consumed the entire buffer
instead of peeking. The lexer's character stream was consumed before the
parser saw it. The shell couldn't even boot.

**Contract violated:** The sfreserve nucleus — 5+ calling patterns with
completely different semantics depending on parameter combinations
([sfio-rewrite-v2.md §The sfreserve contract](sfio-rewrite-v2.md#the-sfreserve-contract-nucleus)).

**Mitigation (Pair 5):** Implement and unit-test all 5 patterns before
integration. Each pattern has a named test case. The patterns are the
specification — if any pattern doesn't match legacy behavior, the shell
won't work, and we want to know before attempting integration.

### Risk 2: sfvprintf %! protocol

**What might go wrong:** 48 of 58 test files exercise printf → sfprintf.
The `extf` callback protocol has subtle interactions with format context
stacking (FMTSET/FMTGET). A wrong interaction means wrong output, wrong
return value, or infinite loop.

**Contract area:** B9 (shadow pointer optimization) + the %! protocol's
save/restore discipline around extf calls.

**Mitigation (Pair 6):** Read `sfvprintf.c` source and `print.c`
`extend()` together — they form a cross-library call pair. Test
incrementally with ksh's actual format specifiers (%b, %q, %H, %T).
Delegate standard specifiers to libc `vsnprintf` to reduce the surface
area of custom code.

### Risk 3: Dccache (discipline push during read)

**What might go wrong:** Buffered data caching on discipline push is
subtle. If data predating the discipline is served directly instead of
replayed through the new discipline, the stream's state becomes
inconsistent.

**Contract area:** C2 (non-associativity witness —
[sfio-rewrite-v2.md §C2](sfio-rewrite-v2.md#c2-dccache--non-associativity-witness))
+ the discipline interception layer (sfdisc.c §Dccache).

**Mitigation (Pair 3):** Test with ksh's actual discipline configurations
(outexcept, slowread, piperead). The Dccache mechanism can be implemented
simply: save buffered data on discipline push, replay before reading
through the new discipline. The complex legacy code handles edge cases
(partial records, locked buffers) that the simpler version can address
incrementally.

### Risk 4: Build system integration

**What went wrong (v1 Phase 7):** All 42 functions were implemented but
the build system linked legacy sfio's symbols instead. The build compiled,
linked, and ran — but every sf\* call went to the wrong implementation.
This was invisible until build system ordering was fixed.

**Mitigation:** The staging directory approach avoids this entirely. During
development, new sfio files compile in `src/lib/libsfio/` with their own
archive. Integration testing links against the staging archive explicitly.
The swap (delete old, move new) is atomic — there's no intermediate state
where both implementations exist in the same link line.

### Risk 5: Global state (_Sfextern)

**What might go wrong:** sfio has global state: pools, notification hooks,
exit handler. Missing or incorrectly ordered initialization means the shell
boots in a corrupt I/O state.

**Contract area:** B11 (ksh integration — sfnotify registration),
`_sfcleanup` atexit handler, pool list through `f->pool`.

**Mitigation (Pair 2):** `sflife.c` includes initialization and cleanup.
The atexit handler is straightforward. The notification hook must fire at
the same lifecycle points as legacy — test by verifying `sh.sftable`,
`sh.fdstatus`, and `sh.fdptrs` remain synchronized through ksh's startup
sequence.

### Risk 6: POSIX Issue 8 availability

**What might go wrong:** Not all targets have `pipe2`/`dup3`/`ppoll`/
`posix_close` yet.

**Mitigation (Layer 2):** `configure.sh` probes for each primitive and
provides fallbacks (`pipe` + `fcntl` when `pipe2` unavailable). The
fd-level Issue 8 primitives are available on all Tier 1 targets (glibc
2.9+, musl, macOS 11+, FreeBSD 10+, OpenBSD 5.7+, illumos). Feature probes
ensure correctness on Tier 2 targets.


## Dependency graph

```
Layer 1: Reduction (strictly subtractive)
    1a (stdio, hash) ──┐
    1b (libdll, libsum) ├── all independent, any order
    1c (libcmd)         │
    1d (comp)           │
    1e (platforms)      │
    1f (security)    ───┘
            │
            ▼
Layer 2: Type Foundation (declarative)
    2a (C23 gate)
            │
            ▼
    2b (C23 features) ─── 2c (POSIX Issue 8 probes)
            │                       │
            ▼                       ▼
Layers 3+4: Polarity Realization (constructive)
    Pair 0 (vocabulary) ──────────────────┐
            │                              │
            ▼                              ▼
    Pair 1 (mode transitions)         sfmode.c
            │                              │
            ▼                              ▼
    Pair 2 (context management)       sflife.c
            │                              │
            ▼                              ▼
    Pair 3 (interception)             sfdisc.c
            │                              │
            ▼                              ▼
    Pair 4 (positive)                 sfwrite.c
            │                              │
            ▼                              ▼
    Pair 5 (negative)                 sfread.c
            │                              │
            ▼                              ▼
    Pair 6 (format + optimization)    sfvprintf.c
            │                              │
            ▼                              ▼
    Pair 7 (encoding)                 sfvle.c
            │                              │
            └──────────┬───────────────────┘
                       ▼
                   The swap
```

Layer dependencies are acyclic. Within Layer 1, sub-phases are independent
(any ordering works). Layer 2 depends on Layer 1 (C23 warnings in dead code
would create noise). Layers 3+4 depend on Layer 2 (sfio headers use C23
typed enums; POSIX Issue 8 probes feed into sflife.c and sfread.c). Within
Layers 3+4, pairs are ordered by dependency: sfmode.c must exist before
any other sfio file can call `_sfmode()`, sflife.c must exist before I/O
can be tested, and so on.


## Cross-references

| Document | Role | Location |
|----------|------|----------|
| [SPEC.md](../SPEC.md) | Theoretical foundation: sequent calculus, polarity, duploid framework, critical pair diagnosis | Root |
| [REDESIGN.md](../REDESIGN.md) | What main built: polarity frames, prefix guards, scope unification, all modernization work | Root |
| [sfio-analysis/](sfio-analysis/) | 12-file contract-level analysis of legacy sfio | notes/ |
| [sfio-rewrite-v2.md](sfio-rewrite-v2.md) | sfio endgame specification: polarity architecture, contracts, implementation sequence, risks | notes/ |
| [sfio-rewrite-failure-analysis.md](sfio-rewrite-failure-analysis.md) | Postmortem: three failed attempts, root causes, lessons | notes/ |
| [COMPARISON.md](COMPARISON.md) | Feature vision: ksh26 vs other shells | notes/ |
| [FUTURE.md](FUTURE.md) | Post-implementation features (completions, autosuggestions, editor hooks) | notes/ |

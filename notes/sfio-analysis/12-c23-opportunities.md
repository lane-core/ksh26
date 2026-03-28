# 12: C23 Opportunities

Consolidated reference of C23 modernization opportunities identified across
the other modules. Each entry identifies what changes, why it matters, and
which files are affected.

These are opportunities for the ksh26 codebase (`main` branch). They do NOT
apply to upstream (ksh93/ksh), which targets C99/C11.

---

## 1. Typed enums with fixed underlying types

**What:** Replace 60+ `#define` flag constants with typed enums.

**Why:** Prevents wrong-field-wrong-flag bugs at compile time. Currently
nothing stops you from using a `bits` constant in the `flags` field or
vice versa — they're all `int`.

**Three separate enums:**

| Enum | Field | Underlying type | Constants |
|------|-------|----------------|-----------|
| `sfio_flags_t` | `_flags` | `unsigned short` | SFIO_READ through SFIO_WCWIDTH |
| `sfio_bits_t` | `bits` | `unsigned short` | SFIO_MMAP through SFIO_MVSIZE |
| `sfio_mode_t` | `mode` | `unsigned int` | SFIO_INIT through SFIO_LOCAL |

**Plus:**

| Enum | Context | Constants |
|------|---------|-----------|
| `sfio_event_t` | Exception events | SFIO_NEW through SFIO_EVENT |
| `sfio_except_t` | Exception returns | SFIO_EDONE through SFIO_ECONT |
| `sffmt_flags_t` | Format flags | SFFMT_LEFT through SFFMT_CHOP |

**Files:** `sfio.h`, `sfio_t.h`, `sfhdr.h`

---

## 2. [[nodiscard]]

**What:** Mark all I/O functions whose return values must be checked.

**Why:** Silent ignoring of error returns is a pervasive bug source. Sfio
functions return -1/NULL on error, but callers frequently ignore this.

**Functions to annotate:**

| Category | Functions |
|----------|-----------|
| Read | `sfread`, `sfgetr`, `sfreserve`, `sfgetc`, `sfmove` |
| Write | `sfwrite`, `sfputr`, `sfputc`, `sfnputc`, `sfprintf` |
| Lifecycle | `sfopen`, `sfnew`, `sfclose`, `sfsync`, `sfsetfd` |
| Control | `sfdisc`, `sfset`, `sfpool`, `sfsetbuf` |

**Files:** `sfio.h` (declarations)

---

## 3. [[noreturn]]

**What:** Annotate error handlers that call `exit()` or `abort()`.

**Why:** Enables dead-code elimination and prevents "missing return"
warnings after error paths.

**Candidates:** `sh_exit()`, error handlers in the shell that call
`longjmp` after SFIO errors.

---

## 4. [[reproducible]] / [[unsequenced]]

**What:** Mark pure helper functions.

**Why:** Enables aggressive constant folding and CSE by the compiler.

**Candidates:** `_sfdlen`, `_sfllen`, `_sfulen` (portable encoding length
calculations — pure functions of their argument).

**Files:** `sfio.h` (declarations), `sfio/sfdlen.c`, `sfio/sfllen.c`,
`sfio/sfulen.c`

---

## 5. [[maybe_unused]]

**What:** Suppress warnings for variables used only conditionally.

**Why:** Lock/unlock macros and mode-switching code often have variables
that are only used in one branch. Currently suppressed with `(void)var`
or `reg` (empty register keyword).

**Candidates:** `local` variables from `GETLOCAL`, `dcdown` in SFDCRD/SFDCWR,
conditional variables in platform-specific code.

---

## 6. nullptr

**What:** Replace `NULL` and the `NIL(t)` macro with `nullptr`.

**Why:** Type-safe null pointer. `NIL(t)` (`Legacy: sfhdr.h:180`) is
already just `NULL` — the cast-to-type was removed long ago but the macro
persists for backward compatibility.

**Specific targets:**
- `SFIO_POPSTACK` and `SFIO_POPDISC` — currently `#define ... NULL`
- All `NIL(t)` uses throughout sfio
- Sentinel comparisons (`f->disc == NULL`, `f->push != NULL`, etc.)

**Files:** `sfio.h`, `sfhdr.h`, all sfio/*.c

---

## 7. static_assert

**What:** Compile-time verification of structural assumptions.

**Why:** Sfio has implicit assumptions about struct sizes, field offsets,
flag values, and type widths that are currently verified only by testing.

**Candidates:**

| Assertion | Validates |
|-----------|-----------|
| `sizeof(Sfio_t)` | Struct size hasn't drifted |
| `offsetof(Sfio_t, _flags)` | ABI stability for public fields |
| `offsetof(Sfio_t, _data)` after `_flags` | Field ordering |
| `SFIO_READ < SFIO_WRITE < SFIO_STRING` | Flag value ordering |
| `sizeof(Sfpool_t::array) == 3 * sizeof(Sfio_t*)` | Inline array size |
| `sizeof(Stk_t) == 3 * sizeof(void*)` | Stk_t is exactly 3 pointers (**already done**: stk.h:41) |

**Files:** `sfio_s.h`, `sfio_t.h`, `sfhdr.h`, `stk.h`

---

## 8. constexpr

**What:** Replace `#define` constants with `constexpr` values.

**Why:** Type safety, debugger visibility, no multiple-evaluation hazards.

**Candidates:**

| Constant group | Examples |
|---------------|----------|
| Buffer sizes | `SFIO_BUFSIZE`, `SFIO_GRAIN`, `SFIO_PAGE` |
| VLE thresholds | `SFIO_U1` through `SFIO_U4` |
| Format limits | `SFIO_FDIGITS`, `SFIO_IDIGITS`, `SFIO_MAXDIGITS` |
| Mmap counts | `SFIO_NMAP` |
| Encoding bits | `SFIO_SBITS`, `SFIO_UBITS`, `SFIO_BBITS` |
| Conversion base | `SFIO_RADIX` (64) |
| Timing | `SECOND` (1000) |

**Files:** `sfio.h`, `sfhdr.h`

---

## 9. static inline replacing macros

**What:** Replace `#define` function macros with `static inline` functions.

**Why:** Eliminates re-evaluation hazards (macros evaluate arguments
multiple times), enables type checking, gives debugger-visible symbols.

**Primary targets:**

| Macro | Current location | Issue |
|-------|-----------------|-------|
| `sfputc` | `sfio.h:295` | Evaluates `f` twice |
| `sfgetc` | `sfio.h:298` | Evaluates `f` twice |
| `sfeof` | `sfio.h:307` | Evaluates `f` twice |
| `sferror` | `sfio.h:308` | Evaluates `f` twice |
| `sffileno` | `sfio.h:306` | Evaluates `f` once (ok) |
| `sfvalue` | `sfio.h:311` | Evaluates `f` once (ok) |
| `sfclrerr` | `sfio.h:309` | Evaluates `f` twice, has side effect |

Note: `__INLINE__` is NOT defined on macOS/Clang, so sfio.h currently uses
`#define` macros unconditionally on Darwin. The `#if defined(__INLINE__)`
path (`sfio.h:315-338`) already has inline functions but they're dead code
on our platform.

Benchmark result: inline macros provide 0–2% benefit (within noise). The
macro-to-inline conversion has zero performance cost.

---

## 10. Platform probe elimination

**What:** Replace 20+ feature test macros in `sfhdr.h` targeting extinct
platforms with a 5-platform compile-time dispatch.

**Why:** `sfhdr.h` tests for Research UNIX, Apollo Domain/OS, UWIN, and
other systems that haven't existed for decades. The feature probes add
complexity without value.

**Targets for elimination:**

| Probe | What it tests | Status |
|-------|--------------|--------|
| `_stream_peek` / STREAMS | SVR4 STREAMS peek | Dead (no STREAMS on modern systems) |
| `_mmap_fixed` / `MAP_VARIABLE` | mmap fixed-address mapping | Dead on modern systems |
| `_has_oflags` | Whether O_CREAT exists | Always true since POSIX.1 |
| `_lib_localeconv` | locale.h localeconv() | Always true |
| `_mem_st_blksize_stat` | struct stat has st_blksize | Always true on POSIX |
| Research UNIX O_CREAT fallback | Fallback values for O_CREAT etc. | Dead |

**Replace with:** Compile-time dispatch for Darwin, Linux, FreeBSD, OpenBSD,
NetBSD. Static assert on unexpected platforms.

**Files:** `sfhdr.h`, `FEATURE/sfio`, `FEATURE/mmap`

---

## 11. _Alignas + static_assert

**What:** Explicit alignment specification and verification for structs
with packing requirements.

**Why:** `Sfpool_t`, `Sfrsrv_t`, `Argv_t` have implicit alignment
assumptions (inline arrays, flexible array members, union alignment).
Making these explicit prevents silent ABI breakage when compiler or
platform changes.

**Files:** `sfhdr.h` (Sfpool_t, Sfrsrv_t, Argv_t definitions)

---

## 12. bool returns

**What:** Functions that return yes/no should return `bool`.

**Why:** Self-documenting API. `sfeof(f)` returning `bool` instead of
masked `int` makes the contract explicit.

**Candidates:**

| Function | Current return | Proposed |
|----------|---------------|----------|
| `sfeof(f)` | `f->flags & SFIO_EOF` (int) | `bool` |
| `sferror(f)` | `f->flags & SFIO_ERROR` (int) | `bool` |
| `sfstacked(f)` | `f->push != NULL` (int) | `bool` |

**Files:** `sfio.h` (declarations and inline definitions)

---

## Implementation priority

Ordered by impact/effort ratio:

1. **[[nodiscard]]** — zero code change, catches real bugs immediately
2. **Typed enums** — moderate refactor, eliminates a class of silent bugs
3. **static inline** — mechanical replacement, zero perf cost
4. **constexpr** — mechanical replacement, improves debuggability
5. **nullptr** — mechanical replacement, type safety
6. **static_assert** — additive, no existing code changes (Stk_t already done)
7. **Platform probe elimination** — significant cleanup, reduces sfhdr.h
8. **bool returns** — small API change, self-documenting
9. **[[reproducible]]** — minor, niche benefit
10. **_Alignas** — defensive, low priority unless ABI issues arise

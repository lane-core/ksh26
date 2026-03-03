# sfio Rewrite Failure Analysis

## What happened

Direction 12 attempted to replace sfio with modern I/O primitives. Three
successive approaches were tried, each failing for deeper reasons than
the last:

1. **Phase 5 (stdio/FILE\*)**: Wrapped sfio's API surface with FILE\*
   streams. 36/115 tests passed. Abandoned because FILE\* lifecycle
   (fclose+fdopen on fd changes) can't preserve buffered data through
   sfswap/sfsetfd — a structural mismatch.

2. **Phase 7 (fd+buffer)**: Replaced FILE\* with direct fd+buffer
   management (sh_io_core.c). Implemented all 42 sf\* functions as
   fd-based operations. 0/115 tests passed (all SIGABRT from stubs
   that were never reached because the build system linked the wrong
   symbols). Build system was fixed in Phase 8 Step 0.

3. **Phase 8 (fd+buffer, correct linking)**: After fixing the build
   system, the shell compiled and linked against our implementations.
   Still 0 meaningful test passes because:
   - Static streams started with `mode=0` (neither read nor write)
   - `sfreserve(f, 0, 0)` consumed the entire buffer instead of
     peeking — the -c command string was consumed before the parser
     saw it
   - The `print` builtin silently returned 1 because stdout appeared
     non-writable
   - `exit 42` returned 0 — the shell wasn't executing commands at all

## Root causes

### RC1: Wrong problem formulation

The framing was "replace sfio with stdio." This presupposes that sfio is
an I/O library that happens to be used by ksh, and that any reasonable
I/O library could substitute. This is false.

sfio is not a library that ksh uses. sfio is the semantic substrate of
ksh's execution model. The shell reads input through sfreserve (which
provides the lexer's character stream), writes output through sfwrite
(which interacts with the pool/discipline system for correct flush
ordering), manages temporary storage through sftmp (for here-documents,
command substitution capture), and coordinates subshell I/O through
sfswap/sfstack (which atomically transfer buffer state between stream
identities).

Replacing sfio with stdio is like replacing malloc with a different
allocator — except sfio's contract surface is an order of magnitude
more complex than malloc's, most of it undocumented, and the shell
depends on exact behavioral details that differ between the original
and any replacement.

### RC2: Implementation from summaries, not from source

Each phase was implemented against function signatures and high-level
descriptions of what sfio functions do. The actual behavioral contracts
— especially the subtle ones — were discovered only when tests failed:

- `sfreserve(f, 0, 0)` is a non-consuming peek, not a consume
- `sfreserve` has 4+ distinct calling patterns with different semantics
  depending on the combination of size and type parameters
- sfio's `_sfmode()` runs on every operation and handles GETR restore,
  mode transitions, and cleanup — there is no "just call the function"
- `sfsetbuf(f, f, 0)` is a magic query pattern, not a buffer assignment
- `sfnew` on a pre-existing stream reinitializes without destroying
  STATIC identity
- The discipline chain's Dccache mechanism preserves buffered data
  across discipline pushes

Each of these was a surprise, and each required structural rework to
accommodate. The implementation was perpetually chasing discovered
contracts rather than building from known ones.

### RC3: Dead-end solution topology

The stdio replacement approach has a fundamental topology problem: you
can't get partial credit. Either the replacement handles every sfio
contract exactly right, or the shell doesn't work. There's no useful
intermediate state between "sfio works" and "replacement works." This
means you can't iterate toward correctness — you have to get it right
all at once, which requires knowing all the contracts in advance.

The abort-stub approach was designed to address this (implement
functions incrementally, let the abort tell you what's needed next),
but it failed because ksh's startup path touches nearly every sfio
function. The shell can't even boot without correct implementations
of sfnew, sfsetbuf, sfset, sfopen, sfpool, sfdisc, sfreserve, sfgetr,
sfwrite, sfputr, sfputc, sfprintf, sfsync, sfclose, sfswap, sfstack,
sftmp, sfseek, sfsetfd, and sfpkrd.

### RC4: The libcmd/libast boundary

Progress was clean through Directions 1-11 (polarity frames, C23 types,
build system). The trouble started at Direction 12 when the work crossed
from ksh's own code into the libast dependency boundary. libast's sfio
is not just used by ksh — it's used by libast itself (error reporting,
stk allocator's internal representation, CDT, etc.). Replacing sfio
means replacing it everywhere simultaneously, including in code that
the replacement itself depends on.

## Lessons

1. **Read the source, not summaries.** There is no substitute for
   reading sfio's actual C code. Every "summary" of sfio behavior
   missed critical details that caused cascading failures.

2. **sfio's real API is its behavior, not its signatures.** Two
   functions with identical signatures (`sfreserve(f, 0, 0)` vs
   `sfreserve(f, n, 0)`) have completely different semantics. The
   contract surface is the actual state machine, not the function list.

3. **Discovery-driven restart.** When a mid-implementation discovery
   would have changed structural choices, restart from the expanded
   spec. We did this once (Phase 5 → Phase 7, FILE\* → fd+buffer) but
   should have done it earlier and more decisively.

4. **The problem was the problem.** "Replace sfio with stdio" was the
   wrong problem. The right problem is: "What I/O semantics does ksh
   actually need, and what's the cleanest way to provide them?" This
   may or may not involve stdio, and it definitely requires understanding
   sfio's contracts before choosing a replacement strategy.

5. **Never implement against abort stubs at scale.** The stub approach
   works for 5-10 functions. At 42+ functions where the startup path
   touches nearly all of them, stubs provide no useful intermediate
   state.

6. **Build system correctness is invisible.** Phase 7 implemented all
   functions but linked against sfio's symbols due to include path
   ordering. The build compiled, linked, and ran — but every sf\*
   call went to sfio, not to our code. This was invisible until
   Phase 8 Step 0 fixed the build system and suddenly everything
   changed.

## Polarity analysis: where FILE\* actually fails

An earlier phase of analysis suggested that FILE\*-based POSIX
primitives (open_memstream, fmemopen, getdelim) would work for
positive-polarity operations (writes, formatting) even if they fail
for negative-polarity operations (reads, peeks, buffer locking).

Investigation of the actual sfio source disproves this. sfio's
positive-polarity operations are entangled with negative-polarity
buffer state:

- **sfputc** is an inline buffer-pointer macro: `*f->_next++ = c`.
  It bypasses function calls entirely and writes directly into the
  buffer. fputc would work semantically but can't replicate this.

- **sfwrite** handles LOCKR release. sfwrite(f, buf, 0) is the
  standard idiom for releasing an sfreserve peek lock (sfwrite.c:42-75).
  This is negative-polarity state management through a nominally
  positive-polarity call.

- **sfstruse** does `sfputc(f,0)` then `f->_next = f->_data` —
  NUL-terminate and rewind via direct pointer manipulation.

- **Polarity mixing on the same stream** is confirmed in ksh:
  edit.c:539-543 calls sfreserve(sfstderr, LOCKR) to get the write
  buffer pointer, then sfwrite(sfstderr, ptr, 0) to release it.

The LOCKR protocol crosses the polarity boundary by design. A
dual-representation approach (FILE\* for writes, custom buffer for
reads) would require synchronizing two buffer states at every mode
switch and every LOCKR release — worse than either approach alone.

**Conclusion:** FILE\* cannot serve as the buffer layer for either
polarity. The buffer model must be custom and unified.

POSIX Issue 8 does contribute — but only at the fd layer below the
buffer: pipe2, dup3, ppoll, posix_close, mkostemp, O_CLOFORK. These
eliminate fd-leak races without touching buffer semantics.

## What to do instead

Don't replace sfio. Reimplement it. Target POSIX Issue 8 (IEEE
1003.1-2024) as the standard baseline — but use Issue 8's fd-level
primitives, not its FILE\*-based ones.

sfio is ~12,800 lines. ksh uses ~39 of its 77 exported functions.
The functions ksh doesn't use (scanf family, float conversion, memory
mapping, process co-pipes, stdio compatibility layer) account for
roughly half the code. The functions ksh does use have well-defined
contracts that can be extracted from the sfio source.

A fresh implementation of sfio's contracts — same API, same semantics,
modern C, no legacy baggage — could be ~2,000–3,000 lines. It would:

- Provide the exact sfreserve/sfgetr/sfdisc/sfpool contracts ksh needs
- Eliminate the scanf engine, float conversion, mmap, and popen code
- Eliminate the stdio compatibility layer (ast_stdio.h interception)
- Use C23 idioms, POSIX Issue 8 fd primitives
- Be auditable (3K lines vs 13K lines)
- Preserve all existing call sites unchanged (same API)

See `sfio-rewrite-v2.md` for the detailed proposal.

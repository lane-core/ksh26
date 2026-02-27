# ksh26

ksh26 is a Unix shell. It is an independent fork of
[ksh93u+m](https://github.com/ksh93/ksh), redesigned from ksh93 to
modern standards. ksh26 is a superset of ksh93: every ksh93 script
runs unmodified, but the internals, build system, and platform
targeting are rebuilt for current systems.

ksh26 targets Linux (glibc, musl), macOS, FreeBSD, NetBSD, and OpenBSD.
In hardening and security, we aspire to OpenBSD's standard: reduce
code surface, audit what remains, treat every buffer and format string
as a potential vulnerability. C23 (GCC 14+ / Clang 18+) is required —
typed enums, constexpr, static_assert, and [[nodiscard]]/[[noreturn]]
move the interpreter's structural invariants from comments into the
compiler.


## Approach

ksh93 has the strongest scripting engine in the Bourne shell family:
compound variables, disciplines, arithmetic, parameter expansion. ksh26
keeps the engine and reduces what has accumulated around it. The
strategy is three-fold: fewer lines, stronger types, external
dependencies. Each reinforces the others — a smaller codebase is
easier to type-annotate, and replacing hand-rolled libraries with
maintained projects shrinks the audit surface further.

**Fewer lines.** ksh93u+m carries library code for platforms and
subsystems that no longer exist: a stdio reimplementation, hash
library, atomic ops abstraction, vmalloc, dlopen wrappers. These were
necessary when targeting HP-UX, AIX, IRIX, and pre-POSIX systems
simultaneously. ksh26 targets five modern platforms and deletes the
rest. The AT&T nmake/MAM build system (~12,000 lines) is replaced with
just + samu + a POSIX configure script (~1,600 lines).

**Stronger types.** C23 makes the compiler enforce invariants that
ksh93 maintained by convention and comments. The interpreter's longjmp
modes — an ordered severity scale that determines which errors
propagate and which are caught locally — were `#define` constants
compared with raw integers. They are now a typed enum with `constexpr`
boundary markers and `static_assert` on the ordering. `[[noreturn]]`
and `[[nodiscard]]` catch misuse at compile time. `nullptr`
distinguishes null pointers from integer zero. Less defensive code is
needed when the type system prevents the mistakes the defense was
guarding against.

**External dependencies.** Where ksh93 reimplemented, ksh26 depends.
[samu](https://github.com/michaelforney/samurai) replaces AT&T nmake.
[utf8proc](https://github.com/JuliaStrings/utf8proc) (MIT, same
library Neovim uses) replaces hand-rolled Unicode width tables.
[scdoc](https://git.sr.ht/~sircmpwn/scdoc) replaces custom troff
generation. Each is a small, actively maintained project aligned with
Unix design: do one thing well, expose a clean interface, compose.
Auditing a focused dependency is cheaper than maintaining a sprawling
reimplementation — and when the dependency improves, we get the fix
for free.

**Structural clarity.** The interpreter's implicit state invariants
are made explicit via a polarity frame API informed by sequent
calculus — three upstream bugs were found this way before users hit
them. The reduced, type-annotated codebase is then audited for stack
buffer overflows, format string vulnerabilities, signal handler
safety, and integer overflow.

Details: [REDESIGN.md](REDESIGN.md). Theory: [SPEC.md](SPEC.md).
Feature direction: [COMPARISON.md](COMPARISON.md). Behavioral
differences from upstream: [DEVIATIONS.md](DEVIATIONS.md).


## Changes from ksh93u+m

The interpreter's state management is restructured so that boundary
crossings between value mode (expansion, assignment) and computation
mode (traps, discipline functions) are handled by explicit frame APIs
rather than ad-hoc save/restore. This eliminates a class of bugs where
state leaks across mode boundaries — three such bugs were found by the
analysis and fixed before users hit them. Fixes for two were submitted
upstream.

The AT&T MAM build system (~12,000 lines) is replaced with just +
samu + a POSIX configure script. Dead library code for obsolete
platforms is removed. Every ksh93u+m script runs unmodified.

Implementation details: [REDESIGN.md](REDESIGN.md).


## Building

    just build
    just test

Requires: C23 compiler (GCC 14+ / Clang 18+), `just`, POSIX shell.


## Branches

`main` is the development branch. `legacy` tracks the pre-fork
`ksh93/ksh` dev branch. Bugfixes found during ksh26 work are
submitted back to upstream as PRs.


## Origin

David Korn, AT&T Bell Labs, 1983. ksh 93u+ (2012). ksh93u+m
(2020–present, Martijn Dekker et al.). ksh26 (2025, Lane Biocini).


## References

- Curien, Herbelin. "The duality of computation." ICFP 2000.
- Wadler. "Call-by-Value is Dual to Call-by-Name, Reloaded." RTA 2005.
- Spiwack. "A Dissection of L." 2014.
- Levy. Call-by-Push-Value. Springer 2004.
- Munch-Maccagnoni. "Syntax and Models of a non-Associative
  Composition of Programs and Proofs." PhD thesis, Paris 7, 2013.
- Mangel, Melliès, Munch-Maccagnoni. "Classical notions of computation
  and the Hasegawa-Thielecke theorem." POPL 2026.
- Binder, Tzschentke, Müller, Ostermann. "Grokking the Sequent
  Calculus (Functional Pearl)." ICFP 2024.

Full citations: [SPEC.md](SPEC.md#references).


## License

[Eclipse Public License 2.0](https://www.eclipse.org/org/documents/epl-2.0/EPL-2.0.html)

# ksh26

ksh26 is a Unix shell. It is an independent fork of
[ksh 93u+m](https://github.com/ksh93/ksh).

ksh26 aims to remain API-compatible with ksh93. Existing scripts,
builtins, and POSIX behavior are preserved. Current target is 100%
compatibility; future extensions will not break existing scripts.

ksh26 targets Linux (glibc, musl), macOS, FreeBSD, NetBSD, and OpenBSD.
It requires C23 (GCC 14+ or Clang 18+).


## What is different

ksh93 has the strongest scripting engine in the Bourne shell family:
compound variables, disciplines, arithmetic, parameter expansion. ksh26
keeps the engine and removes what has accumulated around it.

Dead library code for HP-UX, AIX, IRIX, MVS, and pre-POSIX systems is
removed. The AT&T nmake/MAM build system is replaced with just + samu.
The interpreter's implicit state invariants are made explicit via a
polarity frame API informed by sequent calculus. Three upstream bugs
were found this way.

Details: [REDESIGN.md](REDESIGN.md). Theory: [SPEC.md](SPEC.md).
Feature direction: [COMPARISON.md](COMPARISON.md). Behavioral
differences from upstream: [DEVIATIONS.md](DEVIATIONS.md).


## Building

    bin/package make
    bin/package test


## Branches

`main` is the development branch. `upstream` tracks `ksh93/ksh` dev.
Bugfixes found during ksh26 work are submitted back to upstream as PRs.


## Origin

David Korn, AT&T Bell Labs, 1983. ksh 93u+ (2012). ksh 93u+m
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

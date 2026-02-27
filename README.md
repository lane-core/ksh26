# ksh26

A fork of [ksh 93u+m](https://github.com/ksh93/ksh) with principled
internal structure.

ksh93 is a powerful shell with a 40-year lineage: AT&T Research (David Korn,
1983), the AST open-source release (2000), the community-maintained 93u+m
(2020–present). ksh26 inherits all of this and adds a structural refactor of
the interpreter's state management, guided by ideas from programming language
theory.

## The problem

ksh93's interpreter constantly alternates between two modes:

- **Value mode**: word expansion, parameter substitution, name resolution
  (macro.c, name.c)
- **Computation mode**: command execution, trap dispatch, function calls
  (xec.c)

Each mode transition requires saving and restoring global state — `sh.prefix`
(compound assignment context), `sh.namespace`, `sh.st` (scoped interpreter
state), `sh.var_tree` (variable scope). The original code does this ad-hoc at
each call site. Missing or incomplete saves produce subtle corruption: stale
pointers, leaked context, traps that silently stop working.

These bugs are hard to diagnose because the corruption site and the failure
site are separated by arbitrary execution distance.

## The fix

This two-mode structure is not novel. It is the same structure that the
sequent calculus describes formally: values and computations are distinct
categories, and moving between them requires a *shift* — a save/clear/restore
discipline. ksh93 already implements this discipline; it does so without
naming it.

ksh26 names it. A **polarity frame** API (`sh_polarity_enter`,
`sh_polarity_leave`) consolidates the ad-hoc save/restore into a single
mechanism. This includes preserving trap mutations made by handlers (e.g.,
`trap - DEBUG` inside a DEBUG handler), which the ad-hoc approach got wrong in
multiple places.

### What has changed

- Polarity frame API (`struct sh_polarity`) that saves/restores `sh.prefix`,
  `sh.namespace`, `sh.st`, and `sh.var_tree` at mode boundaries. Trap slot
  preservation across the restore is built into the API.
- Lightweight variant (`struct sh_polarity_lite`) for `sh_debug()`, where the
  inner `sh_trap()` call already provides full `sh.st` protection. 4x
  reduction in copy traffic per DEBUG trap invocation.
- Scope dictionary pool for function calls. 8-entry LIFO cache of CDT
  dictionaries, amortizing `dtopen`/`dtclose` on hot function-call paths.
  Measured 8.5% improvement on tight function-call loops.
- Empty DEBUG trap early exit. When the trap string is empty, skip the entire
  frame/string-build/dispatch sequence.
- All 16 case labels in `sh_exec()` annotated with polarity classification
  (value, computation, or mixed).

See [REDESIGN.md](REDESIGN.md) for the full analysis. See
[DEVIATIONS.md](DEVIATIONS.md) for a list of behavioral differences from
upstream 93u+m.

## Building

Requires a POSIX shell, `cc`, `ar`, `getconf`.

```
bin/package make          # build
bin/package test          # test
bin/shtests --man         # test harness documentation
```

The compiled binary lands in `arch/$(bin/package host type)/bin/ksh`.

For build options, feature configuration (`src/cmd/ksh26/SHOPT.sh`), and
platform-specific notes, see the [upstream documentation](https://github.com/ksh93/ksh#installing-from-source).

## Origin

ksh26 is forked from ksh 93u+m, which is forked from ksh 93u+ (2012-08-01),
which descends from David Korn's original KornShell at AT&T Bell Labs. The
93u+m project is maintained by Martijn Dekker and community contributors.

The `dev` branch of this repository tracks upstream `ksh93/ksh` dev and
carries bugfixes that are submitted back as PRs. The `ksh26` branch diverges
with the structural refactor.

## Theoretical background

The polarity frame design draws on work from several research groups.

**Sequent calculus and duality** —
[Pierre-Louis Curien](https://www.irif.fr/~curien/) (CNRS/IRIF) and
[Hugo Herbelin](http://pauillac.inria.fr/~herbelin/) (INRIA),
"The duality of computation," *ICFP*, 2000.
The λμμ̃-calculus as term assignment for classical sequent calculus:
three-sorted structure (terms, coterms, statements) mapping onto ksh93's
producer/consumer/cut architecture.

[Philip Wadler](https://homepages.inf.ed.ac.uk/wadler/) (Edinburgh),
"Call-by-Value is Dual to Call-by-Name, Reloaded," *RTA*, 2005.
CBV/CBN as De Morgan duals via sequent calculus. The critical pair where
evaluation order matters corresponds to `sh.prefix` corruption during
compound assignment interrupted by trap dispatch.

**Duploids and non-associativity** —
[Guillaume Munch-Maccagnoni](https://guillaume.munch.name/) (INRIA/Gallinette),
"Syntax and Models of a non-Associative Composition of Programs and Proofs,"
PhD thesis, Univ. Paris Diderot, 2013. The duploid framework: semantics for
non-associative composition. ksh93's compound assignment nesting is an
instance.

Éléonore Mangel (IRIF),
[Paul-André Melliès](https://www.irif.fr/~mellies/) (CNRS/IRIF), and
G. Munch-Maccagnoni,
"Classical notions of computation and the Hasegawa-Thielecke theorem,"
*POPL*, 2026. Connects duploids to classical notions of computation.

**Value/computation stratification** —
[Paul Blain Levy](https://www.cs.bham.ac.uk/~pbl/) (Birmingham),
*Call-by-Push-Value: A Functional/Imperative Synthesis*, Springer, 2004.
The value/computation distinction underlying the polarity frame concept.

**Polarized calculi** —
[Arnaud Spiwack](https://github.com/aspiwack) (Tweag/Modus),
"A Dissection of L," 2014. Polarized sequent calculus with explicit shift
operators (↓/↑), directly informing the save/clear/restore pattern.

[David Binder](https://binderdavid.github.io/) (Kent/Tübingen),
M. Tzschentke, M. Müller, and
[Klaus Ostermann](https://ps.informatik.uni-tuebingen.de/team/ostermann/)
(Tübingen),
"Grokking the Sequent Calculus (Functional Pearl)," *ICFP*, 2024.
Practical presentation of λμμ̃ as compilation target.
See also [Polarity](https://polarity-lang.github.io/), Binder et al.'s
language with dependent data and codata types, which implements the
symmetric treatment of polarities as a working language design
([source](https://github.com/polarity-lang/polarity)).

See [SPEC.md](SPEC.md) for the full correspondence between ksh93 internals
and the formal framework.

## License

[Eclipse Public License 2.0](https://www.eclipse.org/org/documents/epl-2.0/EPL-2.0.html)

## Contributors

- David Korn (AT&T Research) — original ksh93
- Martijn Dekker and the [93u+m contributors](https://github.com/ksh93/ksh) — maintenance fork
- Lane Biocini — ksh26 fork, polarity frame design

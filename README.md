# ksh26

ksh26 is a Unix shell. Independent fork of
[ksh93u+m](https://github.com/ksh93/ksh), stripped to modern
platforms, rebuilt in C23.

Every ksh93 script runs unmodified.

## Building

    nix develop -c just build
    nix develop -c just test

Or without nix: C23 compiler (GCC 14+ / Clang 18+), `just`, POSIX shell.

    just build
    just test

## Platforms

Linux (glibc, musl), macOS, FreeBSD, NetBSD, OpenBSD.

## What changed

Dead AT&T library code removed. Build system replaced (MAM → just +
samu + POSIX configure). C23 throughout.

The interpreter has two modes — value (expansion, assignment) and
computation (traps, disciplines) — with state that must be saved at
each boundary crossing. Models of computation described by sequent calculus give us a precise
vocabulary for these boundaries; ksh26 uses it to identify every crossing site
and replace ad-hoc save/restore with a uniform frame API.

[REDESIGN.md](REDESIGN.md) — implementation status.
[SPEC.md](SPEC.md) — theoretical analysis.
[DEVIATIONS.md](DEVIATIONS.md) — behavioral differences from upstream.

## Origin

David Korn, AT&T Bell Labs, 1983. ksh93u+m (Martijn Dekker et al.,
2020). ksh26 (Lane Biocini, 2025).

## License

[Eclipse Public License 2.0](https://www.eclipse.org/org/documents/epl-2.0/EPL-2.0.html)

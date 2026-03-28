# Code Style & Conventions

## C Source (ksh/libast/libcmd)
- **Standard**: C23 (`-std=c23`)
- **Indentation**: tabs (8-space width)
- **Braces**: opening brace on own line
- **Comments**: `/* */` only (no `//`)
- **Formatting**: clang-format via `just fmt`

## Shell Scripts (configure.sh, probes, tests)
- ksh93 idioms: `print` not `echo`, `typeset` not `local`/`declare`
- Always quote expansions, `[[ ]]` for conditionals, `(( ))` for arithmetic
- Variable naming: globals UPPER_SNAKE, locals typeset lower
- `set -o nounset -o pipefail -o noclobber` via modernish

## Build System
- Probe stderr: primitives → /dev/null, delegates → probe_run() → $LOGDIR/probe.log
- Never hardcode counts/thresholds — compute at runtime
- Nix phases aligned with stdenv: configurePhase → buildPhase → checkPhase → installPhase
- Tests: err_exit pattern with $LINENO aliasing in _common

## Commit Messages
- Prefixed: fix:, refactor:, cleanup:, add:
- Body explains WHY, not what
- Each PR squashed to single commit

## Key Principles
- Test sanctity: framework adapts to test, not vice versa
- Zero-failure policy: any test failure is a regression until proven otherwise
- Discovery-driven restart: if mid-implementation discovery changes the design, restart
- Retire old code immediately: no shims, no backwards-compat wrappers

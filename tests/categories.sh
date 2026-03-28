# tests/categories.sh — test category manifest
#
# Associates tests with categories for selective execution and
# scheduling control. A test can appear in multiple categories.
#
# Usage:
#   just test --category fast      # run only fast tests (local samu)
#   samu -C build/$HT test-fast    # same via samu directly
#
# The "timing" category controls serial pool assignment in ninja —
# these tests run one at a time to reduce scheduling jitter.
#
# Format: category TEST [TEST ...]

# Tests with sub-second timing assertions that fail under parallel load
timing      builtins io options sigchld signal subshell

# Signal delivery and trap handling tests
signals     signal sigchld

# Locale and multibyte tests
locale      locale

# Tests requiring a controlling terminal (PTY)
interactive pty jobs

# I/O, coprocess, and heredoc tests
io          io coprocess heredoc

# Fast pure-logic tests (no timing, no signals, no I/O waits)
fast        alias append arith arrays arrays2 attributes bracket case
fast        comvar comvario cubetype enum exit expand functions glob
fast        grep loop math nameref namespace pointtype posix quoting
fast        quoting2 readcsv readonly recttype restricted return
fast        sh_match statics substring tilde timetype treemove types
fast        variables vartree1 vartree2

# Tests sensitive to platform path layout (NixOS vs FHS)
platform    builtins path libcmd

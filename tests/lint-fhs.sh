#!/bin/sh
# tests/lint-fhs.sh — detect hardcoded FHS paths in test files
#
# Finds unguarded references to /usr/bin, /bin, /usr/sbin in test scripts.
# Guarded uses (behind [[ -x ]] checks) and command discovery patterns
# (whence -p, command -p) are excluded.
#
# Usage: sh tests/lint-fhs.sh
# Exit 0: no unguarded FHS paths found
# Exit 1: unguarded paths detected (review and either guard or fix)

cd "$(dirname "$0")/.." || exit 1

hits=$(grep -rn '/usr/bin/\|/usr/sbin/\|"/bin/' src/cmd/ksh26/tests/*.sh \
    | grep -v '^\s*#' \
    | grep -v '\[\[.*-[xfd]' \
    | grep -v 'whence\|command -p' \
    | grep -v '_common' \
    | grep -v 'heredoc\|<<' \
    | grep -v 'SHOPT\|expected')

if [ -n "$hits" ]; then
    echo "Unguarded FHS paths in test files:"
    echo "$hits"
    exit 1
else
    echo "No unguarded FHS paths found."
    exit 0
fi

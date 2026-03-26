#!/usr/bin/env sh
# tests/contexts/default.sh — Base test environment setup
# Sourced by run-test for all tests. Keep this minimal and fast.
#
# Available variables (set by run-test before sourcing):
#   $test_name  — base name of the test (e.g. "basic")
#   $mode       — locale mode ("C" or "C.UTF-8")
#   $BUILDDIR   — build output directory
#   $BINDIR     — build bin directory
#   $TESTS      — test source directory
#   $tmp        — per-test temp directory (already cd'd into)

# ── Environment cleanup ───────────────────────────────────────────
# Remove variables that could interfere with test behavior
unset DISPLAY FIGNORE HISTFILE POSIXLY_CORRECT _AST_FEATURES 2>/dev/null || true

# Neutral startup file — prevents user's ~/.kshrc from loading
export ENV=/./dev/null

# ── Shell configuration ───────────────────────────────────────────
export SHELL="$BINDIR/ksh"
export SHCOMP="$BINDIR/shcomp"
export SHTESTS_COMMON="$TESTS/_common"

# Interactive tests read ~/.sh_history — redirect HOME to tmp
# so they don't affect user state or read stale history
export HOME="$tmp"

# ── Path setup ────────────────────────────────────────────────────
# Save original PATH for tests that need it (e.g. whence tests)
export userPATH="$PATH"

# Reset PATH to minimal system paths + our bin dir (matching shtests behavior).
# Tests use 'whence -p' to find external commands; inheriting the user's full
# PATH can find wrapped versions (e.g. nix wrappers) that behave differently
# from the native commands the tests expect.
#
# Nix build sandbox: getconf PATH returns FHS paths (/usr/bin:/bin) that may
# lack coreutils on NixOS, and ksh's builtin getconf can't find external
# commands (like getconf itself) outside the nix store. Keep the nix store
# paths from the sandbox PATH — these ARE the system tools — plus any FHS
# paths that actually exist.
if [ -n "${NIX_BUILD_TOP:-}" ]; then
	_nix_path=""
	_fhs_path=""
	_ifs="$IFS"; IFS=:
	for _d in $PATH; do
		case $_d in
		/nix/store/*)	_nix_path="${_nix_path:+$_nix_path:}$_d" ;;
		esac
	done
	# Also include real FHS paths if they exist (Darwin sandbox has /usr/bin)
	for _d in /usr/bin /bin /usr/sbin /sbin; do
		[ -d "$_d" ] && _fhs_path="${_fhs_path:+$_fhs_path:}$_d"
	done
	IFS="$_ifs"
	PATH="${_nix_path:+$_nix_path:}${_fhs_path:-/usr/bin:/bin}"
else
	PATH=$(getconf PATH 2>/dev/null) || PATH=/usr/bin:/bin:/usr/sbin:/sbin
fi
export PATH="$BINDIR:$PATH"

# ── Locale handling ───────────────────────────────────────────────
# Unset all locale variables so tests can set specific LC_* categories
# without LC_ALL overriding them. For C.UTF-8 tests, set LANG only.
unset LC_ALL LC_COLLATE LC_CTYPE LC_MESSAGES LC_MONETARY LC_NUMERIC LC_TIME LANG 2>/dev/null || true
case "$mode" in
C)	;;  # all unset — tests inherit POSIX locale
*)	export LANG="$mode" ;;
esac

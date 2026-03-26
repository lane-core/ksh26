# tests/lib/safety.sh — shell safety primitives for the ksh26 test harness
#
# Concepts ported from modernish (https://github.com/modernish/modernish)
# by Martijn Dekker. Original code is ISC licensed:
#
# Copyright (c) 2015-2021 Martijn Dekker <martijn@inlv.org>
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#
# This file is an independent reimplementation of the concepts, not a
# copy of modernish code. It is part of ksh26 (EPL-2.0).

# ── Safe defaults ────────────────────────────────────────────────
# Catch unset variable references immediately.
set -o nounset

# Enable pipefail if available (ksh, bash). Graceful no-op on dash.
(set -o pipefail) 2>/dev/null && set -o pipefail

# ── die — fatal exit from any context ────────────────────────────
# Terminates the top-level process even when called from a subshell,
# pipe segment, or command substitution.
# For call-site context, callers expand $LINENO before passing:
#   die "[$LINENO] something failed"
die()
{
	printf 'FATAL: %s\n' "$*" >&2
	kill -s PIPE "$$" 2>/dev/null
	exit 128
}

# ── harden — make command failures fatal ─────────────────────────
# Usage: harden mkdir cp rm date dirname cat mktemp
# Wraps each command as a function that calls die on non-zero exit.
harden()
{
	for _h_cmd in "$@"; do
		case $_h_cmd in
		*[!A-Za-z0-9_-]*) die "harden: unsafe command name: $_h_cmd" ;;
		esac
		eval "${_h_cmd}() { command ${_h_cmd} \"\$@\" || die \"${_h_cmd} failed (exit \$?): \$*\"; }"
	done
}

# ── extern — bypass builtins/functions, call the real binary ─────
# Usage: extern mkdir -p /some/path
# Walks PATH to find the actual executable. Useful when a function
# (e.g., from harden) shadows the command name.
extern()
{
	_ext_cmd="$1"; shift
	[ -n "${PATH:-}" ] || die "extern: PATH is empty"
	_ext_ifs="$IFS"; IFS=:
	for _ext_dir in ${PATH}; do
		[ -z "$_ext_dir" ] && _ext_dir="."
		if [ -x "${_ext_dir}/${_ext_cmd}" ]; then
			IFS="$_ext_ifs"
			"${_ext_dir}/${_ext_cmd}" "$@"
			return
		fi
	done
	IFS="$_ext_ifs"
	die "extern: command not found: $_ext_cmd"
}

# ── pushtrap / poptrap — stack-based trap management ─────────────
# Usage:
#   pushtrap EXIT 'cleanup_function'    # chain new action with existing
#   poptrap EXIT                        # remove most recent action
#
# Actions chain in LIFO order. For EXIT traps, all pushed actions
# execute on exit (most recent first). For signal traps, only the
# top action runs; poptrap restores the previous one.

# Internal: the EXIT trap handler — runs all stacked actions LIFO
_safety_exit_handler()
{
	_se_i=${_trap_exit_count:-0}
	while [ "$_se_i" -gt 0 ]; do
		_se_i=$((_se_i - 1))
		eval "eval \"\${_trap_exit_${_se_i}:-}\""
	done
}

_trap_exit_count=0

pushtrap()
{
	_pt_sig="$1"; shift
	case $_pt_sig in
	EXIT|0)
		eval "_trap_exit_${_trap_exit_count}=\"\$*\""
		_trap_exit_count=$((_trap_exit_count + 1))
		trap '_safety_exit_handler' EXIT
		;;
	*)
		# Non-EXIT signals: use indexed stack (same as EXIT).
		# Avoids trap -p parsing which is non-portable (dash lacks -p).
		eval "_trap_sig_${_pt_sig}_${_trap_sig_count_:-0}=\"\$*\""
		eval "_trap_sig_count_${_pt_sig}=\$((\${_trap_sig_count_${_pt_sig}:-0} + 1))"
		trap "$*" "$_pt_sig"
		;;
	esac
}

poptrap()
{
	_pt_sig="$1"
	case $_pt_sig in
	EXIT|0)
		[ "$_trap_exit_count" -gt 0 ] && _trap_exit_count=$((_trap_exit_count - 1))
		eval "unset _trap_exit_${_trap_exit_count}"
		;;
	*)
		eval "_pt_cnt=\${_trap_sig_count_${_pt_sig}:-0}"
		if [ "$_pt_cnt" -gt 0 ]; then
			_pt_cnt=$((_pt_cnt - 1))
			eval "_trap_sig_count_${_pt_sig}=$_pt_cnt"
			eval "unset _trap_sig_${_pt_sig}_${_pt_cnt}"
			if [ "$_pt_cnt" -gt 0 ]; then
				_pt_prev_idx=$((_pt_cnt - 1))
				eval "trap \"\${_trap_sig_${_pt_sig}_${_pt_prev_idx}}\" $_pt_sig"
			else
				trap - "$_pt_sig"
			fi
		else
			trap - "$_pt_sig"
		fi
		;;
	esac
}

# Sentinel — sourcing scripts check this instead of command -v
_safety_loaded=1

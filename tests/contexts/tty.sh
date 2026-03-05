#!/bin/sh
# tests/contexts/tty.sh — Pseudo-terminal simulation for TTY-dependent tests
# Used by: jobs.sh, pty.sh
#
# These tests require a controlling terminal for job control operations.
# The Nix sandbox and some CI environments don't provide one.

# Only set up TTY if we don't already have one
if [ ! -t 0 ] || [ ! -t 1 ]; then
	# Check if we can use script(1) to provide a PTY
	if command -v script >/dev/null 2>&1; then
		# BSD/macOS script uses different syntax than Linux
		case $(uname -s) in
			Darwin|*BSD)
				# BSD script runs the command directly
				export _KSH_TTY_WRAPPER="script -q /dev/null"
				;;
			Linux|*)
				# Linux script needs --command or legacy syntax
				if script --help 2>&1 | grep -q -- --command; then
					export _KSH_TTY_WRAPPER="script -q /dev/null --command"
				else
					# Legacy Linux script
					export _KSH_TTY_WRAPPER="script -q -c"
				fi
				;;
		esac
	fi

	# Alternative: expect/unbuffer if available
	if [ -z "$_KSH_TTY_WRAPPER" ] && command -v unbuffer >/dev/null 2>&1; then
		export _KSH_TTY_WRAPPER="unbuffer"
	fi

	# Last resort: python pty module
	if [ -z "$_KSH_TTY_WRAPPER" ] && command -v python3 >/dev/null 2>&1; then
		_python_pty='
import pty, sys, os
os.environ["_KSH_IN_PTY"] = "1"
pty.spawn(sys.argv[1:])
'
		export _KSH_TTY_WRAPPER="python3 -c '$_python_pty'"
	fi
fi

# Note: The test runner uses $_KSH_TTY_WRAPPER to wrap execution
# If empty, tests run without TTY simulation (may fail or skip)

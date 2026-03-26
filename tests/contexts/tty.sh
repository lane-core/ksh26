#!/usr/bin/env sh
# tests/contexts/tty.sh — Pseudo-terminal simulation for TTY-dependent tests
# Used by: jobs, pty
#
# These tests require a controlling terminal for job control operations.
# The Nix sandbox and some CI environments don't provide one.
# The run-test script uses $_KSH_TTY_WRAPPER to wrap test execution.

# Only relevant for tests needing a controlling terminal but lacking their
# own PTY management. pty.sh uses the 'pty' binary internally — wrapping
# it in script(1) creates a conflicting outer PTY layer.
case $test_name in jobs) ;; *) return 0 ;; esac

# Only set up TTY wrapper if we don't already have one
if [ ! -t 0 ] || [ ! -t 1 ]; then
	# Check if we can use script(1) to provide a PTY
	if command -v script >/dev/null 2>&1; then
		case $(uname -s) in
			Darwin|*BSD)
				_KSH_TTY_WRAPPER="script -q /dev/null"
				;;
			Linux|*)
				if script --help 2>&1 | grep -q -- --command; then
					_KSH_TTY_WRAPPER="script -q /dev/null --command"
				else
					_KSH_TTY_WRAPPER="script -q -c"
				fi
				;;
		esac
	fi

	# Alternative: expect/unbuffer if available
	if [ -z "$_KSH_TTY_WRAPPER" ] && command -v unbuffer >/dev/null 2>&1; then
		_KSH_TTY_WRAPPER="unbuffer"
	fi

	export _KSH_TTY_WRAPPER
fi

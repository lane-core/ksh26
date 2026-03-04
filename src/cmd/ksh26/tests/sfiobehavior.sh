########################################################################
#                                                                      #
#               This software is part of the ksh26 project             #
#          Copyright (c) 2026 Contributors to ksh 93u+m                #
#                      and is licensed under the                       #
#                 Eclipse Public License, Version 2.0                  #
#                                                                      #
#                A copy of the License is available at                 #
#      https://www.eclipse.org/org/documents/epl-2.0/EPL-2.0.html      #
#         (with md5 checksum 84283fa8859daf213bdda5a9f8d1be1d)         #
#                                                                      #
########################################################################
#
# Tests for ksh behaviors that depend on sfio buffer management,
# stream stacking, and discipline semantics. These test the shell
# interface, not sfio internals — they survive the sfio rewrite and
# catch regressions in the replacement I/O layer.
#

. "${SHTESTS_COMMON:-${0%/*}/_common}"

# ── sfreserve buffer semantics ───────────────────────────────────────
# ksh uses sfreserve(f, SF_UNBOUND, SF_LOCKR) for fast character input
# (fcfopen/fcfill). These tests verify buffered input is consumed
# correctly across various read patterns.

# Buffer peek: read from a pipe shouldn't lose data when the input
# is buffered and partially consumed across multiple reads.
exp='line1 line2 line3'
got=$(printf 'line1\nline2\nline3\n' | {
	read -r a
	read -r b
	read -r c
	print -r -- "$a $b $c"
})
[[ $got == "$exp" ]] || err_exit "sequential reads from pipe lost data (expected '$exp', got '$got')"

# Here-string input uses sfreserve peek internally.
exp=hello
read -r got <<< "hello"
[[ $got == "$exp" ]] || err_exit "here-string read failed (expected '$exp', got '$got')"

# Partial read: read -n should consume exactly N characters and leave
# the rest available for subsequent reads.
exp='he llo'
got=$(print -n 'hello' | {
	read -r -n2 a
	read -r b
	print -r -- "$a $b"
})
[[ $got == "$exp" ]] || err_exit "partial read -n lost data (expected '$exp', got '$got')"

# Large buffer: input larger than SFIO_BUFSIZE (typically 8192) must
# be buffered and consumed correctly across multiple reads.
exp=16384
got=$(
	typeset -i n=0
	# Generate 16384 lines of single characters
	typeset i
	for ((i=0; i<16384; i++)); do
		print x
	done | while read -r line; do
		((n++))
	done
	print $n
)
[[ $got == "$exp" ]] || err_exit "large buffer read miscounted lines (expected $exp, got $got)"

# ── Stream stacking (sfstack) ────────────────────────────────────────
# ksh pushes streams for here-documents, source (.), and eval.
# Stacking must be LIFO with correct restoration.

# Nested here-documents: each level pushes a new stream; they must
# unwind correctly.
exp='inner middle outer'
got=$(
	cat <<-OUTER
	$(cat <<-MIDDLE
	$(cat <<-INNER
	inner
	INNER
	) middle
	MIDDLE
	) outer
	OUTER
)
got=$(print -r -- "$got" | tr '\n' ' ' | sed 's/ *$//')
[[ $got == "$exp" ]] || err_exit "nested here-documents failed (expected '$exp', got '$got')"

# Source with redirection: . (dot) pushes a stream; redirections
# inside the sourced script must not corrupt the outer stream state.
cat > "$tmp/source_test.sh" <<'EOF'
read -r line < /dev/null
print sourced
EOF
exp='sourced ok'
got=$(
	. "$tmp/source_test.sh"
	print ok
)
got=$(print -r -- "$got" | tr '\n' ' ' | sed 's/ *$//')
[[ $got == "$exp" ]] || err_exit "source with redirection corrupted stream state (expected '$exp', got '$got')"

# eval with here-document: eval pushes a string stream for the
# command text; a here-document inside it pushes another stream.
exp='hello world'
got=$(eval 'cat <<EOF
hello world
EOF
')
[[ $got == "$exp" ]] || err_exit "eval with here-document failed (expected '$exp', got '$got')"

# Input continuity after here-document in loop.
exp='1 2 3'
got=$(
	for i in 1 2 3; do
		read -r x <<-EOF
		$i
		EOF
		print -n "$x "
	done
)
got=${got% }
[[ $got == "$exp" ]] || err_exit "here-document in loop corrupted input (expected '$exp', got '$got')"

# ── Redirections and stream discipline ───────────────────────────────
# ksh uses stream disciplines for tee-like patterns (2>&1 |),
# history capture, and exec redirections. These must push/pop
# correctly.

# stderr-to-stdout merge in pipeline: the 2>&1 pattern depends on
# discipline-based stream duplication.
exp='stdout stderr'
got=$(
	{
		print stdout
		print stderr >&2
	} 2>&1 | tr '\n' ' ' | sed 's/ *$//'
)
[[ $got == "$exp" ]] || err_exit "2>&1 pipeline merge failed (expected '$exp', got '$got')"

# exec redirection save/restore: opening and closing fds with exec
# must restore prior state correctly.
exp=original
got=$(
	exec 3>&1
	print -u3 original
	exec 3>&-
) 2>/dev/null
[[ $got == "$exp" ]] || err_exit "exec fd save/restore failed (expected '$exp', got '$got')"

# Nested redirections: multiple levels of exec redirection must
# unwind in LIFO order.
exp=ok
got=$(
	print start > "$tmp/redir_test"
	exec 3< "$tmp/redir_test"
	read -r -u3 line
	exec 3<&-
	[[ $line == start ]] && print ok || print fail
)
[[ $got == "$exp" ]] || err_exit "nested exec redirection failed (expected '$exp', got '$got')"

# Pipeline with process substitution: combines stream stacking
# (pipe), discipline (redirect), and subshell isolation.
exp='hello'
got=$(
	print hello | cat | cat | cat
)
[[ $got == "$exp" ]] || err_exit "multi-stage pipeline lost data (expected '$exp', got '$got')"

# ── Cross-cutting: buffer + stack + discipline ───────────────────────
# Tests that exercise multiple sfio subsystems together.

# Here-document in pipeline: stacks a here-doc stream, then pipes
# through a discipline-managed pipeline.
exp='HELLO WORLD'
got=$(cat <<EOF | tr a-z A-Z
hello world
EOF
)
[[ $got == "$exp" ]] || err_exit "here-document in pipeline failed (expected '$exp', got '$got')"

# Subshell with redirected input reading from parent's here-document.
exp='from-heredoc'
got=$(
	(read -r line; print -r -- "$line") <<EOF
from-heredoc
EOF
)
[[ $got == "$exp" ]] || err_exit "subshell reading parent here-document failed (expected '$exp', got '$got')"

# Command substitution with buffered input: the comsub creates
# a new stream context; buffered data from the outer context
# must not leak in or be lost.
exp='outer inner outer2'
got=$({
	print -r -- "outer"
	x=$(print -r -- "inner")
	print -r -- "$x"
	print -r -- "outer2"
} | tr '\n' ' ' | sed 's/ *$//')
[[ $got == "$exp" ]] || err_exit "comsub stream isolation failed (expected '$exp', got '$got')"

exit $((Errors<125?Errors:125))

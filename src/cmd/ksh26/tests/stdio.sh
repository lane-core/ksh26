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
# Regression tests for sfio → stdio migration (Direction 12).
# These exercise I/O behaviors where the inline-macro and function-call
# dispatch paths could differ: sfputc/sfgetc character I/O, sfeof/sferror
# status checks, sffileno fd tracking, sfvalue byte counts, and string
# buffer (sfstr*) operations.
#

. "${SHTESTS_COMMON:-${0%/*}/_common}"

# ======== sfputc/sfgetc: character-at-a-time I/O ========

# print builtin (sfputc path)
exp='hello world'
got=$(print -r -- 'hello world')
[[ $got == "$exp" ]] || err_exit "print -r -- failed (expected '$exp', got '$got')"

# printf builtin (sfprintf path)
exp='42 3.14'
got=$(printf '%d %.2f' 42 3.14)
[[ $got == "$exp" ]] || err_exit "printf format failed (expected '$exp', got '$got')"

# read builtin (sfgetc path)
print 'test line' | read got
[[ $got == 'test line' ]] || err_exit "read from pipe failed (expected 'test line', got '$got')"

# ======== large I/O: sfwrite/sfread bulk path ========

# Large write through pipe
typeset -i n
n=$(dd if=/dev/zero bs=1 count=65536 2>/dev/null | wc -c)
(( n == 65536 )) || err_exit "large write through pipe: expected 65536 bytes, got $n"

# Multi-line accumulation
exp=1000
got=$(
	typeset -i i=0
	while (( i < 1000 ))
	do
		print -r -- "line $i"
		(( i++ ))
	done | wc -l
)
got=${got##*([[:space:]])}
[[ $got == "$exp" ]] || err_exit "1000-line pipe: expected $exp lines, got '$got'"

# ======== sfeof/sferror: status checks ========

# EOF detection via read return code
print 'single' | { read x; read y; }
(( $? != 0 )) || err_exit "read past EOF should fail"

# Error detection on closed fd
got=$(exec 3>&-; print -u3 test 2>&1) && err_exit "write to closed fd should fail"

# ======== sffileno: fd tracking ========

# exec fd manipulation
exec 3>/dev/null
[[ -w /dev/fd/3 ]] || err_exit "fd 3 not open after exec 3>/dev/null"
exec 3>&-

# fd reuse after close
exec 3>/dev/null
exec 3>&-
exec 3>/dev/null
print -u3 test && exec 3>&- || err_exit "fd reuse after close failed"

# ======== string streams (sfstr*): command substitution ========

# Simple comsub
got=$(print hello)
[[ $got == hello ]] || err_exit "simple comsub failed"

# Nested comsub (exercises strbuf nesting)
got=$(print $(print $(print deep)))
[[ $got == deep ]] || err_exit "nested comsub strbuf: expected 'deep', got '$got'"

# Large comsub output (strbuf growth)
got=$(
	typeset -i i=0
	while (( i < 500 ))
	do
		print -r -- "padding data line $i with extra content to exercise buffer growth"
		(( i++ ))
	done
)
typeset -i lines
lines=$(print -r -- "$got" | wc -l)
lines=${lines##*([[:space:]])}
(( lines == 500 )) || err_exit "large comsub: expected 500 lines, got $lines"

# ======== stdout/stderr separation (sfpool behavior) ========

typeset outfile=$tmp/out.$$ errfile=$tmp/err.$$
{ print -u1 out; print -u2 err; } >"$outfile" 2>"$errfile"
[[ $(<"$outfile") == out ]] || err_exit "stdout capture failed"
[[ $(<"$errfile") == err ]] || err_exit "stderr capture failed"

# Interleaved stdout/stderr
{
	print -u1 'line1'
	print -u2 'err1'
	print -u1 'line2'
	print -u2 'err2'
} >"$outfile" 2>"$errfile"
exp=$'line1\nline2'
[[ $(<"$outfile") == "$exp" ]] || err_exit "interleaved stdout failed"
exp=$'err1\nerr2'
[[ $(<"$errfile") == "$exp" ]] || err_exit "interleaved stderr failed"

# ======== heredoc (string stream + parameter expansion) ========

typeset name="benchmark"
got=$(cat <<-EOF
	Name: $name
	Value: $(( 7 * 6 ))
	EOF
)
exp=$'Name: benchmark\nValue: 42'
[[ $got == "$exp" ]] || err_exit "heredoc expansion failed (expected '$exp', got '$got')"

# ======== sfputr: string + delimiter write ========

# printf with newline (sfputr path via print)
exp=$'a\nb\nc'
got=$(print -r -- a; print -r -- b; print -r -- c)
[[ $got == "$exp" ]] || err_exit "multi-line print failed"

# ======== sfseek/sftell: seeking ========

# read -N (seek-related)
print -r -- 'abcdefghij' | read -N 5 got
[[ $got == abcde ]] || err_exit "read -N 5 failed (expected 'abcde', got '$got')"

# ======== sfvalue: byte count tracking ========

# read -n returns partial input
print -r -- 'xyz' | read -n 2 got
[[ $got == xy ]] || err_exit "read -n 2 failed (expected 'xy', got '$got')"

# ======== cleanup ========
rm -f "$outfile" "$errfile"

exit $((Errors<125?Errors:125))

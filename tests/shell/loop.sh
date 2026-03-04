########################################################################
#                                                                      #
#               This software is part of the ast package               #
#          Copyright (c) 1982-2011 AT&T Intellectual Property          #
#          Copyright (c) 2020-2024 Contributors to ksh 93u+m           #
#                      and is licensed under the                       #
#                 Eclipse Public License, Version 2.0                  #
#                                                                      #
#                A copy of the License is available at                 #
#      https://www.eclipse.org/org/documents/epl-2.0/EPL-2.0.html      #
#         (with md5 checksum 84283fa8859daf213bdda5a9f8d1be1d)         #
#                                                                      #
#                  David Korn <dgk@research.att.com>                   #
#                  Martijn Dekker <martijn@inlv.org>                   #
#                                                                      #
########################################################################

. "${SHTESTS_COMMON:-${0%/*}/_common}"

PS3='ABC '

cat > $tmp/1 <<\!
1) foo
2) bar
3) bam
!

select i in foo bar bam
do	case $i in
	foo)	break;;
	*)	err_exit "select 1 not working"
		break;;
	esac
done 2> /dev/null <<!
1
!

unset i
select i in foo bar bam
do	case $i in
	foo)	err_exit "select foo not working" 2>&3
		break;;
	*)	if	[[ $REPLY != foo ]]
		then	err_exit "select REPLY not correct" 2>&3
		fi
		( set -u; : $i ) || err_exit "select: i not set to null" 2>&3
		break;;
	esac
done  3>&2 2> $tmp/2 <<!
foo
!

# ======
# break, continue

got=$(for i in a b c; do print -n $i; for j in 1 2 3; do print -n $j; break 2; done; done)
exp=a1
[[ $got == "$exp" ]] || err_exit "'break 2' broken (expected '$exp', got '$got')"

got=$(for i in a b c; do print -n $i; for j in 1 2 3; do print -n $j; continue 2; done; done)
exp=a1b1c1
[[ $got == "$exp" ]] || err_exit "'continue 2' broken (expected '$exp', got '$got')"

got=$(for i in a b c; do print -n $i; for j in 1 2 3; do print -n $j; for k in x y z; do print -n $k; break 3; done; done; done)
exp=a1x
[[ $got == "$exp" ]] || err_exit "'break 3' broken (expected '$exp', got '$got')"

got=$(for i in a b c; do print -n $i; for j in 1 2 3; do print -n $j; for k in x y z; do print -n $k; continue 3; done; done; done)
exp=a1xb1xc1x
[[ $got == "$exp" ]] || err_exit "'continue 3' broken (expected '$exp', got '$got')"

# ======
# arithmetic for

exp=': `))'\'' unexpected'
for t in 'for((i=0,i<10,i++))' 'for(())' 'for((;))' 'for((0;))'
do	got=$(set +x; (ulimit -c 0; eval "$t; do :; done") 2>&1)
	[[ $got == *"$exp" ]] || err_exit "$t (expected match of *$(printf %q "$exp"), got $(printf %q "$got"))"
done

# ======
# T1-01: while/until loop semantics

# basic while counting
got=$($SHELL -c 'typeset -i n=0; while (( n < 5 )); do (( n++ )); done; print $n')
exp=5
[[ $got == "$exp" ]] || err_exit "basic while loop counting (expected '$exp', got '$got')"

# while false never executes body
got=$($SHELL -c 'typeset -i n=0; while false; do (( n++ )); done; print $n')
exp=0
[[ $got == "$exp" ]] || err_exit "while false should never execute body (expected '$exp', got '$got')"

# basic until counting
got=$($SHELL -c 'typeset -i n=0; until (( n >= 5 )); do (( n++ )); done; print $n')
exp=5
[[ $got == "$exp" ]] || err_exit "basic until loop counting (expected '$exp', got '$got')"

# until true never executes body
got=$($SHELL -c 'typeset -i n=0; until true; do (( n++ )); done; print $n')
exp=0
[[ $got == "$exp" ]] || err_exit "until true should never execute body (expected '$exp', got '$got')"

# exit status: while-with-break
$SHELL -c 'while true; do break; done' || err_exit "while-with-break should exit 0 (got $?)"

# exit status: while false
$SHELL -c 'while false; do :; done' || err_exit "while false should exit 0 (got $?)"

# exit status: until true
$SHELL -c 'until true; do :; done' || err_exit "until true should exit 0 (got $?)"

# while reading lines from a file
print 'line1\nline2\nline3' > while_input
got=$($SHELL -c '
	typeset result=
	while read line; do
		result+="$line "
	done < while_input
	print -rn "$result"
')
exp='line1 line2 line3 '
[[ $got == "$exp" ]] || err_exit "while read from file" \
	"(expected $(printf %q "$exp"), got $(printf %q "$got"))"

# nested while/until
got=$($SHELL -c '
	typeset -i sum=0 i=1
	while (( i <= 3 )); do
		typeset -i j=1
		until (( j > 3 )); do
			(( sum += i * j, j++ ))
		done
		(( i++ ))
	done
	print $sum
')
exp=36
[[ $got == "$exp" ]] || err_exit "nested while/until (expected '$exp', got '$got')"

# break inside until
got=$($SHELL -c 'typeset -i n=0; until false; do (( ++n >= 3 )) && break; done; print $n')
exp=3
[[ $got == "$exp" ]] || err_exit "break inside until (expected '$exp', got '$got')"

# continue inside while
got=$($SHELL -c '
	typeset -i sum=0 i=0
	while (( i < 5 )); do
		(( i++ ))
		(( i == 3 )) && continue
		(( sum += i ))
	done
	print $sum
')
exp=12
[[ $got == "$exp" ]] || err_exit "continue inside while (expected '$exp', got '$got')"

# continue inside until
got=$($SHELL -c '
	typeset -i sum=0 i=0
	until (( i >= 5 )); do
		(( i++ ))
		(( i == 3 )) && continue
		(( sum += i ))
	done
	print $sum
')
exp=12
[[ $got == "$exp" ]] || err_exit "continue inside until (expected '$exp', got '$got')"

# ======
# T1-02: for i; do (implicit $@)

# basic iteration over positional params
got=$($SHELL -c 'for i; do print -n "$i "; done' x a b c)
exp='a b c '
[[ $got == "$exp" ]] || err_exit "'for i; do' with positional params" \
	"(expected $(printf %q "$exp"), got $(printf %q "$got"))"

# zero arguments: body not executed
got=$($SHELL -c 'for i; do print -n "$i"; done; print done' x)
exp=done
[[ $got == "$exp" ]] || err_exit "'for i; do' with zero args should not execute body (expected '$exp', got '$got')"

# arguments with whitespace preserved
got=$($SHELL -c 'for i; do print -r "$i"; done' x 'a b' 'c d' 'e f')
exp=$'a b\nc d\ne f'
[[ $got == "$exp" ]] || err_exit "'for i; do' should preserve whitespace in args" \
	"(expected $(printf %q "$exp"), got $(printf %q "$got"))"

# inside a ksh function
got=$($SHELL -c 'function f { for i; do print -n "$i "; done; }; f x y z')
exp='x y z '
[[ $got == "$exp" ]] || err_exit "'for i; do' inside ksh function" \
	"(expected $(printf %q "$exp"), got $(printf %q "$got"))"

# after set --
got=$($SHELL -c 'set -- p q r; for i; do print -n "$i "; done')
exp='p q r '
[[ $got == "$exp" ]] || err_exit "'for i; do' after 'set --'" \
	"(expected $(printf %q "$exp"), got $(printf %q "$got"))"

# ======
# T2-30: arithmetic for-loop with empty conditions

# for((;;)) with all conditions empty
got=$($SHELL -c 'typeset -i n=0; for((;;)); do ((++n >= 3)) && break; done; print $n')
exp=3
[[ $got == "$exp" ]] || err_exit "for((;;)) with break" \
	"(expected $(printf %q "$exp"), got $(printf %q "$got"))"

# for((init;;incr)) with empty test
got=$($SHELL -c 'for((i=0;;i++)); do ((i >= 5)) && break; done; print $i')
exp=5
[[ $got == "$exp" ]] || err_exit "for((i=0;;i++)) with empty test" \
	"(expected $(printf %q "$exp"), got $(printf %q "$got"))"

# for((init;;)) with empty increment
got=$($SHELL -c 'for((i=10;;)); do ((i <= 0)) && break; ((i--)); done; print $i')
exp=0
[[ $got == "$exp" ]] || err_exit "for((i=10;;)) with empty increment" \
	"(expected $(printf %q "$exp"), got $(printf %q "$got"))"

# ======
exit $((Errors<125?Errors:125))

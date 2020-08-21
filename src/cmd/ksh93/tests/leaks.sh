########################################################################
#                                                                      #
#               This software is part of the ast package               #
#          Copyright (c) 1982-2012 AT&T Intellectual Property          #
#                      and is licensed under the                       #
#                 Eclipse Public License, Version 1.0                  #
#                    by AT&T Intellectual Property                     #
#                                                                      #
#                A copy of the License is available at                 #
#          http://www.eclipse.org/org/documents/epl-v10.html           #
#         (with md5 checksum b35adb5213ca9657e911e9befb180842)         #
#                                                                      #
#              Information and Software Systems Research               #
#                            AT&T Research                             #
#                           Florham Park NJ                            #
#                                                                      #
#                  David Korn <dgk@research.att.com>                   #
#                                                                      #
########################################################################

function err_exit
{
	print -u2 -n "\t"
	print -u2 -r ${Command}[$1]: "${@:2}"
	let Errors+=1
}
alias err_exit='err_exit $LINENO'

Command=${0##*/}
integer Errors=0

[[ -d $tmp && -w $tmp ]] || { err\_exit "$LINENO" '$tmp not set; run this from shtests. Aborting.'; exit 1; }
builtin vmstate 2>/dev/null || { err\_exit "$LINENO" 'vmstate built-in command not compiled in; skipping tests'; exit 0; }

# Get the current amount of memory usage
function getmem
{
	vmstate --format='%(busy_size)u'
}
n=$(getmem)
if	! let "($n) == ($n) && n > 0"	# not a non-zero number?
then	err\_exit "$LINENO" "vmstate built-in command not functioning; tests cannot be run"
	exit 1
fi

# test for variable reset leak #

function test_reset
{
	integer i N=$1

	for ((i = 0; i < N; i++))
	do	u=$i
	done
}

# Initialise variables used below to avoid false leaks
before=0 after=0 i=0 u=0

# Number of iterations for each test
N=512

# Check results. Add a tolerance of 2 bytes per iteration. Some tests appear to have tiny leaks, but they
# must be vmalloc artefacts; they may increase with the number of iterations, then suddenly go away when the
# number of iterations is large enough (e.g. 10000) and don't return when increasing iterations further.
#
# The function has 'err_exit' in the name so that shtests counts each call as at test.
function err_exit_if_leak
{
	if	((after > before + 2 * N))
	then	err\_exit "$1" "$2 (leaked $((after - before)) bytes after $N iterations)"
	fi
}
alias err_exit_if_leak='err_exit_if_leak "$LINENO"'

# one round to get to steady state -- sensitive to -x

test_reset $N
test_reset $N
before=$(getmem)
test_reset $N
after=$(getmem)
err_exit_if_leak "variable value reset memory leak"

# buffer boundary tests

for exp in 65535 65536
do	got=$($SHELL -c 'x=$(printf "%.*c" '$exp' x); print ${#x}' 2>&1)
	[[ $got == $exp ]] || err_exit "large command substitution failed -- expected $exp, got $got"
done

data="(v=;sid=;di=;hi=;ti='1328244300';lv='o';id='172.3.161.178';var=(k='conn_num._total';u=;fr=;l='Number of Connections';n='22';t='number';))"
read -C stat <<< "$data"
before=$(getmem)
for ((i=0; i < N; i++))
do	print -r -- "$data"
done |	while read -u$n -C stat
	do	:
	done	{n}<&0-
after=$(getmem)
err_exit_if_leak "memory leak with read -C when deleting compound variable"

# extra 'read's to get to steady state
for ((i=0; i < 10; i++))
do	read -C stat <<< "$data"
done
before=$(getmem)
for ((i=0; i < N; i++))
do      read -C stat <<< "$data"
done
after=$(getmem)
# this test can show minor variations in memory usage when run with shcomp: https://github.com/ksh93/ksh/issues/70
err_exit_if_leak "memory leak with read -C when using <<<"

# ======
# Unsetting an associative array shouldn't cause a memory leak
# See https://www.mail-archive.com/ast-users@lists.research.att.com/msg01016.html
typeset -A stuff
before=$(getmem)
for (( i=0; i < N; i++ ))
do
	unset stuff[xyz]
	typeset -A stuff[xyz]
	stuff[xyz][elem0]="data0"
	stuff[xyz][elem1]="data1"
	stuff[xyz][elem2]="data2"
	stuff[xyz][elem3]="data3"
	stuff[xyz][elem4]="data4"
done
unset stuff
after=$(getmem)
err_exit_if_leak 'unset of associative array causes memory leak'

# ======
# Memory leak when resetting PATH and clearing hash table
# ...steady memory state:
command -v ls >/dev/null	# add something to hash table
PATH=/dev/null true		# set/restore PATH & clear hash table
# ...test for leak:
before=$(getmem)
for	((i=0; i < N; i++))
do	PATH=/dev/null true	# set/restore PATH & clear hash table
	command -v ls		# do PATH search, add to hash table
done >/dev/null
after=$(getmem)
err_exit_if_leak 'memory leak on PATH reset before PATH search'
# ...test for another leak that only shows up when building with nmake:
before=$(getmem)
for	((i=0; i < N; i++))
do	PATH=/dev/null true	# set/restore PATH & clear hash table
done >/dev/null
after=$(getmem)
err_exit_if_leak 'memory leak on PATH reset'

# ======
# Defining a function in a virtual subshell
# https://github.com/ksh93/ksh/issues/114

unset -f foo
before=$(getmem)
for ((i=0; i < N; i++))
do	(function foo { :; }; foo)
done
after=$(getmem)
err_exit_if_leak 'ksh function defined in virtual subshell'
typeset -f foo >/dev/null && err_exit 'ksh function leaks out of subshell'

unset -f foo
before=$(getmem)
for ((i=0; i < N; i++))
do	(foo() { :; }; foo)
done
after=$(getmem)
err_exit_if_leak 'POSIX function defined in virtual subshell'
typeset -f foo >/dev/null && err_exit 'POSIX function leaks out of subshell'

# ======
# Sourcing a dot script in a virtual subshell

echo 'echo "$@"' > $tmp/dot.sh
before=$(getmem)
for ((i=0; i < N; i++))
do	(. "$tmp/dot.sh" dot one two three >/dev/null)
done
after=$(getmem)
err_exit_if_leak 'script dotted in virtual subshell'

echo 'echo "$@"' > $tmp/dot.sh
before=$(getmem)
for ((i=0; i < N; i++))
do	(source "$tmp/dot.sh" source four five six >/dev/null)
done
after=$(getmem)
err_exit_if_leak 'script sourced in virtual subshell'

# ======
exit $((Errors<125?Errors:125))

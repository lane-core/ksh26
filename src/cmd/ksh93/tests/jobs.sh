########################################################################
#                                                                      #
#              This file is part of the ksh 93u+m package              #
#             Copyright (c) 2021 Contributors to ksh 93u+m             #
#                    <https://github.com/ksh93/ksh>                    #
#                      and is licensed under the                       #
#                 Eclipse Public License, Version 1.0                  #
#                                                                      #
#                A copy of the License is available at                 #
#          http://www.eclipse.org/org/documents/epl-v10.html           #
#         (with md5 checksum b35adb5213ca9657e911e9befb180842)         #
#                                                                      #
#                  Martijn Dekker <martijn@inlv.org>                   #
#                                                                      #
########################################################################
function err_exit
{
	print -u2 -n "\t"
	print -u2 -r "${Command}[$1]: ${@:2}"
	let Errors++
}
alias err_exit='err_exit $LINENO'

Command=${0##*/}
integer Errors=0

[[ -d $tmp && -w $tmp && $tmp == "$PWD" ]] || { err\_exit "$LINENO" '$tmp not set; run this from shtests. Aborting.'; exit 1; }

# All the tests here should run with job control on
set -o monitor

# ======
# Before 2021-02-11, using a shared-state ${ command substitution; } twice caused ksh to lose track of all running jobs
sleep 1 & p1=$!
sleep 2 & p2=$!
j1=${ jobs; }
[[ $j1 == $'[2] +  Running '*$'\n[1] -  Running '* ]] || err_exit "sleep jobs not registered (got $(printf %q "$j1"))"
: ${ :; } ${ :; }
j2=${ jobs; }
kill $p1 $p2
[[ $j2 == "$j1" ]] || err_exit "jobs lost after shared-state command substitution ($(printf %q "$j2") != $(printf %q "$j1"))"

# ======
exit $((Errors<125?Errors:125))

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

# proto(1) has been removed. This is a backwards compatibility stub that allows
# compiling older AST code (with Mamfiles containing proto commands) using the
# current INIT system. This stub ignores all options, then invokes 'cat'.

while	:
do	case ${1-} in
	-*)	shift
		;;
	*)	break
		;;
	esac
done
case $# in
1)	exec cat "$1"
	;;
*)	echo "$0: this stub only supports one file name argument" >&2
	exit 1
	;;
esac

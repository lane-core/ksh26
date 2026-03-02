#!/bin/ksh
# redirect.ksh — fd manipulation cycles
# Exercises: sfnew, sfclose, sffileno, sfset
typeset -i i=0
typeset file=/tmp/ksh-bench-redirect.$$
while (( i < 3000 ))
do
	exec 3>"$file"
	print -u3 "write $i"
	exec 3>&-
	(( i++ ))
done
rm -f "$file"

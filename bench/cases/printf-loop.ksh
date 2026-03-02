#!/bin/ksh
# printf-loop.ksh — tight sfprintf loop
# Exercises: sfprintf (358 call sites, #1 sf* call)
typeset -i i=0
while (( i < 10000 ))
do
	printf '%d %s\n' "$i" "the quick brown fox jumps over the lazy dog"
	(( i++ ))
done

#!/bin/ksh
# strbuf-build.ksh — string buffer accumulation via command substitution
# Exercises: command substitution I/O path (buffered output via $(print))
typeset -i i=0
while (( i < 2000 ))
do
	x=$(print -r -- "accumulated string number $i with padding data")
	(( i++ ))
done

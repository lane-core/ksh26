#!/bin/ksh
# comsub.ksh — command substitution (fork + pipe I/O)
# Exercises: sfputc (strbuf), sfgetc (pipe read), string stream lifecycle
typeset -i i=0
while (( i < 1500 ))
do
	x=$(print -r -- "iteration $i")
	y=${x%% *}
	(( i++ ))
done

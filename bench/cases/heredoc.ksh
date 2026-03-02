#!/bin/ksh
# heredoc.ksh — heredoc expansion (string stream heavy)
# Exercises: sfstropen, sfputc, sfputr, sfstruse, parameter expansion
typeset -i i=0
typeset name="benchmark"
while (( i < 2000 ))
do
	cat <<-EOF >/dev/null
	Here-document iteration $i
	Name: $name
	Value: $(( i * 3 + 7 ))
	EOF
	(( i++ ))
done

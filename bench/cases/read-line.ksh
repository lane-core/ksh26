#!/bin/ksh
# read-line.ksh — line-by-line file reading
# Exercises: sfgetc (lexer path), sfgetr, read builtin I/O
typeset file=/tmp/ksh-bench-readlines.$$
typeset -i i=0
while (( i < 5000 ))
do
	print "line $i: some sample text for benchmarking purposes"
	(( i++ ))
done > "$file"
while IFS= read -r line
do
	:
done < "$file"
rm -f "$file"

#!/bin/ksh
#
# io-bench.ksh — A/B I/O performance comparison
#
# Compares sfio inline-macro backend vs function-call backend.
# Usage: ksh io-bench.ksh /path/to/ksh-sfio /path/to/ksh-stdio [iterations]
#

set -o nounset

typeset sfio_bin=${1:?'usage: io-bench.ksh <sfio-ksh> <stdio-ksh> [iterations]'}
typeset stdio_bin=${2:?'usage: io-bench.ksh <sfio-ksh> <stdio-ksh> [iterations]'}
typeset -i iterations=${3:-5}

typeset benchdir=${0%/*}/cases

if [[ ! -d $benchdir ]]
then
	print -u2 "error: cannot find $benchdir"
	exit 1
fi
if [[ ! -x $sfio_bin ]]
then
	print -u2 "error: $sfio_bin not executable"
	exit 1
fi
if [[ ! -x $stdio_bin ]]
then
	print -u2 "error: $stdio_bin not executable"
	exit 1
fi

# run_timed: run a ksh binary on a script, print elapsed seconds
# Uses ksh's SECONDS (float) for sub-second wall-clock measurement
run_timed()
{
	typeset bin=$1 script=$2
	typeset -F6 before after
	before=$SECONDS
	"$bin" "$script" >/dev/null 2>&1
	after=$SECONDS
	print -r -- $(( after - before ))
}

print "I/O benchmark: inline macros (sfio) vs function calls (stdio)"
print "  sfio:  $sfio_bin"
print "  stdio: $stdio_bin"
print "  iterations: $iterations"
print ""
printf '%-20s  %12s  %12s  %8s\n' "benchmark" "sfio (s)" "stdio (s)" "ratio"
printf '%-20s  %12s  %12s  %8s\n' "---------" "--------" "---------" "-----"

for case in "$benchdir"/*.ksh
do
	typeset name=${case##*/}
	name=${name%.ksh}

	# Warmup (1 run each, discarded)
	"$sfio_bin" "$case" >/dev/null 2>&1
	"$stdio_bin" "$case" >/dev/null 2>&1

	# Timed runs — collect wall-clock seconds
	typeset -a sfio_times stdio_times
	typeset -i i=0
	while (( i < iterations ))
	do
		sfio_times[i]=$(run_timed "$sfio_bin" "$case")
		stdio_times[i]=$(run_timed "$stdio_bin" "$case")
		(( i++ ))
	done

	# Compute averages using awk
	typeset sfio_avg stdio_avg ratio
	sfio_avg=$(
		typeset -i j=0
		while (( j < iterations ))
		do
			print "${sfio_times[j]}"
			(( j++ ))
		done | awk '{ s += $1; n++ } END { printf "%.3f", s/n }'
	)
	stdio_avg=$(
		typeset -i j=0
		while (( j < iterations ))
		do
			print "${stdio_times[j]}"
			(( j++ ))
		done | awk '{ s += $1; n++ } END { printf "%.3f", s/n }'
	)
	ratio=$(print "$sfio_avg $stdio_avg" | awk '{ if ($1 > 0) printf "%.2f", $2/$1; else print "N/A" }')

	printf '%-20s  %12s  %12s  %7sx\n' "$name" "$sfio_avg" "$stdio_avg" "$ratio"
done

print ""
print "ratio < 1.0 = stdio faster, > 1.0 = sfio faster"

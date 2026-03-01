########################################################################
#                                                                      #
#               This software is part of the ksh26 project             #
#          Copyright (c) 2026 Contributors to ksh 93u+m                #
#                      and is licensed under the                       #
#                 Eclipse Public License, Version 2.0                  #
#                                                                      #
#                A copy of the License is available at                 #
#      https://www.eclipse.org/org/documents/epl-2.0/EPL-2.0.html      #
#         (with md5 checksum 84283fa8859daf213bdda5a9f8d1be1d)         #
#                                                                      #
########################################################################
#
# Regression tests for stk allocator (Direction 12, Step 3).
# Exercises stk write functions through shell operations that hit
# each code path: stkputc, stkputs, stkwrite, stkprintf, stkgrow,
# stkset/stkfreeze.
#

. "${SHTESTS_COMMON:-${0%/*}/_common}"

# ======== stkputc: character-at-a-time via string quoting ========

# sh_fmtq escape loop — builds quoted string char by char via stkputc
x=$'\x01\x02\x03\x04\x05'
got=$(printf '%q' "$x")
eval "y=$got"
[[ $x == "$y" ]] || err_exit "printf %q roundtrip failed on control chars"

# Single-character accumulation in arithmetic
(( 1 + 1 == 2 )) || err_exit "basic arithmetic failed"

# ======== stkputs: string+delimiter via path construction ========

# path_join / cd — builds paths via stkputs(sh.stk, component, '/')
mkdir -p "$tmp/a/b/c/d/e"
cd "$tmp/a/b/c/d/e" && [[ $PWD == "$tmp/a/b/c/d/e" ]] \
	|| err_exit "deep path construction failed"
cd "$tmp" || err_exit "cd back to tmp failed"

# Variable expansion with multiple components
typeset p="$tmp/a/b/c"
[[ -d $p ]] || err_exit "path via variable failed"

# ======== stkwrite: bulk write via read builtin ========

# read -r with large input — stkwrite(sh.stk, buf, n) path
exp=$(printf 'x%.0s' {1..4000})
got=$(print -r -- "$exp" | { read -r line; print -r -- "$line"; })
[[ $got == "$exp" ]] || err_exit "large read -r roundtrip failed (${#exp} chars)"

# Binary-safe write
exp=$'\x00\x01\x02\xff'
got=$(print -r -- "$exp" | { read -r line; print -r -- "$line"; })
[[ $got == "$exp" ]] || err_exit "binary read -r roundtrip failed"

# ======== stkprintf: formatted output via error messages ========

# Arithmetic errors trigger stkprintf in error formatting
exp='arithmetic syntax error'
got=$( (( * )) 2>&1) || :
[[ $got == *"$exp"* ]] || err_exit "arithmetic error format failed"

# printf formatting through shell
exp='num=42 str=hello'
got=$(printf 'num=%d str=%s' 42 hello)
[[ $got == "$exp" ]] || err_exit "printf format via shell failed (expected '$exp', got '$got')"

# ======== stkgrow: force buffer growth past STK_FSIZE (8KB) ========

# Build a string > 8KB to force at least one stkgrow
typeset -i i=0
x=
while (( i < 1000 )); do
	x+='AAAAAAAAAA'   # 10 chars x 1000 = 10KB > 8KB frame
	(( i++ ))
done
(( ${#x} == 10000 )) || err_exit "large string accumulation failed (expected 10000, got ${#x})"

# Nested compound: grows stack during name resolution
typeset -A map
i=0
while (( i < 200 )); do
	map[key_$i]=(value="item_$i" index=$i)
	(( i++ ))
done
[[ ${map[key_199].value} == 'item_199' ]] \
	|| err_exit "compound array with 200 entries failed"

# ======== stkset/stkfreeze: scope boundaries ========

# Function call triggers stkfreeze/stkset cycle
f() { typeset x=$(printf '%0500d' 1); print ${#x}; }
got=$(f)
[[ $got == 500 ]] || err_exit "stk freeze/restore across function call failed (got $got)"

# Nested function calls — multiple stk frames
g() { typeset y=$(printf '%01000d' 2); f; }
got=$(g)
[[ $got == 500 ]] || err_exit "nested stk freeze/restore failed (got $got)"

# ======== growth with realloc move (alias tracking) ========

# Rapid growth pattern that forces multiple reallocs
x=$(
	typeset -i i=0
	while (( i < 50 )); do
		print -n "chunk_${i}_$(printf '%0100d' $i)_"
		(( i++ ))
	done
)
(( ${#x} > 5000 )) || err_exit "multi-realloc growth failed (got ${#x} chars)"

# ======== heredoc expansion (stk used for string assembly) ========

typeset name="stk_test"
got=$(cat <<-EOF
	Name: $name
	Value: $(( 7 * 6 ))
	EOF
)
exp=$'Name: stk_test\nValue: 42'
[[ $got == "$exp" ]] || err_exit "heredoc expansion via stk failed"

# ======== stkcopy: string copy onto stack ========

# Command substitution exercises stkcopy
got=$(print hello)
[[ $got == hello ]] || err_exit "simple comsub (stkcopy path) failed"

# Nested comsub
got=$(print $(print $(print deep)))
[[ $got == deep ]] || err_exit "nested comsub stkcopy failed"

exit $((Errors<125?Errors:125))

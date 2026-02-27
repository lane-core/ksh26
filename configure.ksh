#!/usr/bin/env ksh

# configure.ksh — probe platform, detect features, generate build.ninja
#
# Part of the ksh26 build system: just (porcelain) → configure.ksh → samu
# This script replaces the MAM (Make Abstract Machine) build infrastructure
# with a single-pass configure step that emits a ninja build file.
#
# Usage: ksh configure.ksh [--force]
#   Probes the compiler, runs iffe feature tests, and writes
#   build/$HOSTTYPE/build.ninja
#
# With --force, all probes rerun unconditionally (ignoring cache).
# Without it, probes are skipped when their output is fresher than
# their input — typically cutting reconfigure from minutes to seconds.

set -o nounset -o errexit -o pipefail

# ── Options ───────────────────────────────────────────────────────────

typeset FORCE=false
for _arg in "$@"; do
	case $_arg in
	--force) FORCE=true ;;
	esac
done

# ── HOSTTYPE detection ─────────────────────────────────────────────────
# Produces os.arch-bits, e.g. darwin.arm64-64, linux.x86_64-64.
# Replaces the 850-line hostinfo() function from bin/package.

detect_hosttype()
{
	typeset os arch bits
	os=$(uname -s | tr 'A-Z' 'a-z')
	arch=$(uname -m)
	case $arch in
	aarch64) arch=arm64 ;;
	i?86)    arch=i386 ;;
	esac
	bits=$(getconf LONG_BIT 2>/dev/null) || bits=64
	print "${os}.${arch}-${bits}"
}

# ── Paths ──────────────────────────────────────────────────────────────

PACKAGEROOT=${PACKAGEROOT:-$(cd "$(dirname "$0")" && pwd)}
cd "$PACKAGEROOT"

# Validate HOSTTYPE format (os.arch-bits). Ignore shell builtins
# like bash's HOSTTYPE=aarch64 that aren't in our convention.
case ${HOSTTYPE:-} in
*.*-*)	;;
*)	HOSTTYPE=$(detect_hosttype) ;;
esac
BUILDDIR=build/$HOSTTYPE
OBJDIR=$BUILDDIR/obj
INCDIR=$BUILDDIR/include/ast
LIBDIR=$BUILDDIR/lib
FEATDIR=$BUILDDIR/include/ast/FEATURE

# Absolute paths (needed by iffe)
PACKAGEROOT_ABS=$(cd "$PACKAGEROOT" && pwd)
BUILDDIR_ABS=$PACKAGEROOT_ABS/$BUILDDIR

mkdir -p "$BUILDDIR/bin" "$OBJDIR" "$INCDIR" "$LIBDIR" "$FEATDIR" \
	"$OBJDIR/libast" "$OBJDIR/libsum" "$OBJDIR/libdll" "$OBJDIR/libcmd" \
	"$OBJDIR/ksh26"

# ── Compiler probe ────────────────────────────────────────────────────
# Reuse mamprobe.sh to detect compiler capabilities. mamprobe needs
# lib/probe/C/make/probe reachable via ${PATH_ENTRY%/bin/*}/lib/...
# so we create a temporary probe layout.

CC=${CC:-cc}
CC_PATH=$(command -v "$CC")

# Bootstrap probe infrastructure
PROBE_DIR=$BUILDDIR/probe
mkdir -p "$PROBE_DIR/bin/ok" "$PROBE_DIR/lib/probe/C/make"
cat src/cmd/INIT/C+probe src/cmd/INIT/make.probe > "$PROBE_DIR/lib/probe/C/make/probe"
chmod +x "$PROBE_DIR/lib/probe/C/make/probe"

# Parse mamprobe 'setv name value' output into shell variables
parse_probe_output()
{
	typeset varname value
	while IFS= read -r line; do
		case $line in
		setv\ mam_cc_*)
			line=${line#setv }
			varname=${line%% *}
			case $line in
			*\ *)	value=${line#* } ;;
			*)	value="" ;;
			esac
			case $value in
			*%\{*) continue ;;
			esac
			eval "$varname=\$value"
			;;
		esac
	done
}

typeset mam_cc_AR mam_cc_DEBUG mam_cc_OPTIMIZE mam_cc_NOSTRICTALIASING
typeset mam_cc_TARGET mam_cc_DLL mam_cc_PIC mam_cc_HOSTTYPE
typeset mam_cc_SUFFIX_SHARED mam_cc_SUFFIX_DYNAMIC mam_cc_PREFIX_DYNAMIC
typeset mam_cc_PREFIX_SHARED mam_cc_LD_STRIP mam_cc_AR_ARFLAGS
typeset mam_cc_WARN

# Cache: reuse config.probe if compiler binary hasn't changed
typeset probe_cache=$BUILDDIR/config.probe
if ! $FORCE && [[ -f "$probe_cache" ]] && [[ -s "$probe_cache" ]] \
   && [[ "$probe_cache" -nt "$CC_PATH" ]] \
   && [[ "$probe_cache" -nt configure.ksh ]]; then
	print "configure: using cached compiler probe"
	parse_probe_output < "$probe_cache"
else
	print "configure: probing compiler $CC_PATH ..."
	typeset probe_output
	probe_output=$(PATH="$PACKAGEROOT_ABS/$PROBE_DIR/bin/ok:$PATH" \
		sh src/cmd/INIT/mamprobe.sh - "$CC_PATH" 2>/dev/null)
	parse_probe_output <<< "$probe_output"
	print "$probe_output" > "$probe_cache"
fi

# mamprobe may detect a different HOSTTYPE; use ours
mam_cc_HOSTTYPE=$HOSTTYPE

print "configure: HOSTTYPE=$HOSTTYPE"
print "configure: CC=$CC_PATH"
print "configure: AR=${mam_cc_AR:-ar}"

# ── Compiler flags ────────────────────────────────────────────────────

typeset CFLAGS="-std=c23 ${mam_cc_TARGET:-} ${mam_cc_OPTIMIZE:-} ${mam_cc_NOSTRICTALIASING:-}"
typeset AR="${mam_cc_AR:-ar}"
typeset AR_FLAGS="${mam_cc_AR_ARFLAGS:-}"

# ── Cache key ─────────────────────────────────────────────────────────
# Invalidate all cached probes when compiler or flags change.

typeset CONFIGURE_SELF=$PACKAGEROOT_ABS/configure.ksh
typeset CACHE_KEY="$CC_PATH $CFLAGS"
typeset CACHE_KEY_FILE=$BUILDDIR_ABS/.configure_cache_key

if $FORCE; then
	print "configure: --force: invalidating all cached probes"
	rm -f "$BUILDDIR_ABS"/libast_work/FEATURE/* \
		"$BUILDDIR_ABS"/libsum_work/FEATURE/* \
		"$BUILDDIR_ABS"/libdll_work/FEATURE/* \
		"$BUILDDIR_ABS"/libcmd_work/FEATURE/* \
		"$BUILDDIR_ABS"/ksh26_work/FEATURE/* \
		"$BUILDDIR_ABS"/.iconv_cache \
		"$CACHE_KEY_FILE" 2>/dev/null || true
elif [[ -f "$CACHE_KEY_FILE" ]] && [[ "$(cat "$CACHE_KEY_FILE")" == "$CACHE_KEY" ]]; then
	: # cache key matches — individual probes check their own freshness
else
	if [[ -f "$CACHE_KEY_FILE" ]]; then
		print "configure: compiler or flags changed, invalidating probe cache"
	fi
	rm -f "$BUILDDIR_ABS"/libast_work/FEATURE/* \
		"$BUILDDIR_ABS"/libsum_work/FEATURE/* \
		"$BUILDDIR_ABS"/libdll_work/FEATURE/* \
		"$BUILDDIR_ABS"/libcmd_work/FEATURE/* \
		"$BUILDDIR_ABS"/ksh26_work/FEATURE/* \
		"$BUILDDIR_ABS"/.iconv_cache 2>/dev/null || true
fi
print "$CACHE_KEY" > "$CACHE_KEY_FILE"

# ── Library detection ─────────────────────────────────────────────────
# Detect optional external libraries not always in the default search path.
# On Nix-based macOS, libiconv is a separate derivation outside the
# linker's default -L paths. On stock macOS, it's reexported via libSystem.

typeset ICONV_FLAGS=""
typeset iconv_cache=$BUILDDIR_ABS/.iconv_cache

if [[ -f "$iconv_cache" ]] && [[ "$iconv_cache" -nt "$CONFIGURE_SELF" ]]; then
	ICONV_FLAGS=$(cat "$iconv_cache")
	print "configure: iconv: ${ICONV_FLAGS:-(in libc)} (cached)"
else
	typeset iconv_test='#include <iconv.h>
int main(void) { iconv_open("",""); return 0; }'

	if printf '%s' "$iconv_test" | $CC_PATH $CFLAGS -x c - -o /dev/null 2>/dev/null; then
		ICONV_FLAGS=""
	elif printf '%s' "$iconv_test" | $CC_PATH $CFLAGS -x c - -o /dev/null -liconv 2>/dev/null; then
		ICONV_FLAGS="-liconv"
	else
		typeset _nix_dirs=""
		if [[ -d /nix/store ]]; then
			_nix_dirs=$(find /nix/store -maxdepth 1 -name '*libiconv-*' \
				-not -name '*-dev' -not -name '*.drv' 2>/dev/null \
				| sort -r | head -3 | sed 's|$|/lib|')
		fi
		typeset _d
		for _d in /usr/local/lib /opt/homebrew/lib $_nix_dirs; do
			if [[ -d "$_d" ]] && printf '%s' "$iconv_test" | $CC_PATH $CFLAGS -x c - -o /dev/null -L"$_d" -liconv 2>/dev/null; then
				ICONV_FLAGS="-L$_d -liconv"
				break
			fi
		done
	fi
	print -r -- "$ICONV_FLAGS" > "$iconv_cache"
	[[ -n "$ICONV_FLAGS" ]] && print "configure: iconv: $ICONV_FLAGS" || print "configure: iconv: not found (AST fallback)"
fi

# ── iffe helper ───────────────────────────────────────────────────────
# Install the iffe script so we can use it for feature detection.
# iffe is the "if feature exists" probe tool from the AST project.

mkdir -p "$BUILDDIR/bin"
cp src/cmd/INIT/iffe.sh "$BUILDDIR/bin/iffe"
chmod +x "$BUILDDIR/bin/iffe"

_run_iffe_uncached()
{
	typeset workdir=$1 input=$2
	shift 2

	mkdir -p "$workdir/FEATURE"

	# Separate compiler/linker flags from script args
	typeset -a iffe_flags=() script_args=()
	while (( $# )); do
		case $1 in
		-[IlL]*) iffe_flags+=("$1") ;;
		*)       script_args+=("$1") ;;
		esac
		shift
	done

	# iffe must run from the workdir so FEATURE/ output lands there.
	# -X ast -X std: exclude ast/ and std/ dirs from include search
	# (prevents finding libast wrapper headers before they're generated).
	# ref -I$INCDIR: make generated headers findable.
	(
		cd "$workdir"
		PATH="$BUILDDIR_ABS/bin:$PATH" \
		sh "$BUILDDIR_ABS/bin/iffe" -v -X ast -X std \
			-c "$CC_PATH $CFLAGS" \
			ref -I"$PACKAGEROOT_ABS/$INCDIR" -I"$BUILDDIR_ABS/include" \
			"${iffe_flags[@]}" \
			: run "$input" "${script_args[@]}"
	) 2>/dev/null || true
}

# Probe tracking: background jobs can't update shell variables,
# so we log cache hits/misses to a file and count at the end.
typeset _iffe_log=$BUILDDIR_ABS/.iffe_log
: > "$_iffe_log"

run_iffe()
{
	# $1 = working directory, $2 = input features/name file, $3... = extra args
	typeset workdir=$1 input=$2

	# Derive the FEATURE output name from the input filename
	typeset featname=${input##*/}
	featname=${featname%.sh}
	featname=${featname%.c}
	typeset outfile=$workdir/FEATURE/$featname

	# Cache check: skip if output exists, is non-empty, and is newer
	# than both the input file and configure.ksh itself
	if ! $FORCE && [[ -f "$outfile" ]] && [[ -s "$outfile" ]] \
	   && [[ "$outfile" -nt "$input" ]] \
	   && [[ "$outfile" -nt "$CONFIGURE_SELF" ]]; then
		print cached >> "$_iffe_log"
		return 0
	fi

	print ran >> "$_iffe_log"
	_run_iffe_uncached "$@"
}

# Copy a feature test result to its canonical header location.
# Creates an empty file if the source doesn't exist (some tests are optional).
copy_feature()
{
	if [[ -f "$1" ]] && [[ -s "$1" ]]; then
		cp -f "$1" "$2"
	else
		: > "$2"
	fi
}

# ── Standalone C probe ────────────────────────────────────────────────
# Compile and run a small C program, capturing stdout. Used for probes
# that the old build system ran against AST libraries but that don't
# actually need AST — the originals just used sfio for convenience.

probe_c()
{
	typeset src=$BUILDDIR_ABS/probe$$.c
	typeset bin=$BUILDDIR_ABS/probe$$
	trap 'rm -f "$src" "$bin" "${src%.c}.d"' EXIT
	cat > "$src"
	if $CC_PATH $CFLAGS \
		-I"$PACKAGEROOT_ABS/$INCDIR" -I"$BUILDDIR_ABS/include" \
		-o "$bin" "$src" "$@" 2>/dev/null
	then
		"$bin" 2>/dev/null
		typeset rc=$?
	else
		typeset rc=1
	fi
	rm -f "$src" "$bin" "${src%.c}.d"
	trap - EXIT
	return $rc
}

# ── Feature tests: libast ─────────────────────────────────────────────
# The ordering here matters: standards must run first, then common/lib,
# then map (depends on lib), then the rest.

run_libast_features()
{
	typeset srcdir=$PACKAGEROOT_ABS/src/lib/libast
	typeset workdir=$BUILDDIR_ABS/libast_work
	typeset feat=$workdir/FEATURE

	mkdir -p "$workdir/FEATURE"

	print "configure: running libast feature tests ..."

	# Generate ast_release.h
	(
		if git_branch=$(git branch 2>/dev/null); then
			print '/* generated by configure.ksh */'
			case $git_branch in
			*\*\ [0-9]*.[0-9]*)
				if git diff-index --quiet HEAD 2>/dev/null; then
					print '#ifndef _AST_release'
					print '#    define _AST_release	1'
					print '#endif'
				else
					print '/* on release branch, but changes made */'
				fi
				;;
			*)
				print '/* not on a release branch */'
				;;
			esac
		else
			print '/* not in a git repo */'
			print '#ifndef _AST_release'
			print '#    define _AST_release	1'
			print '#endif'
		fi
	) > "$INCDIR/ast_release.h"

	# ── Tier 0: standards (blocks everything) ──
	run_iffe "$workdir" "$srcdir/features/standards"
	copy_feature "$feat/standards" "$INCDIR/ast_standards.h"

	# ── Tier 1: api, common, lib (independent, all need standards) ──
	run_iffe "$workdir" "$srcdir/features/api" &
	run_iffe "$workdir" "$srcdir/features/common" &
	run_iffe "$workdir" "$srcdir/features/lib" &
	wait
	copy_feature "$feat/api" "$INCDIR/ast_api.h"
	sed '/define _def_map_ast/d' < "$feat/common" > "$INCDIR/ast_common.h"
	copy_feature "$feat/lib" "$INCDIR/ast_lib.h"

	# ── Tier 2: probes that depend on common/lib but not on each other ──
	run_iffe "$workdir" "$srcdir/features/eaccess" &
	run_iffe "$workdir" "$srcdir/features/mmap" &
	run_iffe "$workdir" "$srcdir/features/sig.sh" &
	run_iffe "$workdir" "$srcdir/features/fs" &
	run_iffe "$workdir" "$srcdir/features/sfio" &
	run_iffe "$workdir" "$srcdir/features/map.c" &
	run_iffe "$workdir" "$srcdir/features/tty" &
	run_iffe "$workdir" "$srcdir/features/aso" &
	run_iffe "$workdir" "$srcdir/features/wchar" &
	wait
	copy_feature "$feat/sig" "$INCDIR/sig.h"
	copy_feature "$feat/fs" "$INCDIR/ast_fs.h"
	copy_feature "$feat/map" "$INCDIR/ast_map.h"
	copy_feature "$feat/tty" "$INCDIR/ast_tty.h"
	copy_feature "$feat/wchar" "$INCDIR/ast_wchar.h"

	# Endian stubs (depend on common + map being done)
	mkdir -p "$BUILDDIR_ABS/include/std"
	touch "$BUILDDIR_ABS/include/std/bytesex.h" "$BUILDDIR_ABS/include/std/endian.h"

	# ── Tier 3: probes that need tier 2 outputs ──
	run_iffe "$workdir" "$srcdir/features/sys" &
	run_iffe "$workdir" "$srcdir/features/asometh" &
	run_iffe "$workdir" "$srcdir/features/param.sh" &
	run_iffe "$workdir" "$srcdir/features/fcntl.c" \
		-I"$srcdir/comp" -I"$srcdir/include" &
	wait
	copy_feature "$feat/sys" "$INCDIR/ast_sys.h"
	copy_feature "$feat/param" "$INCDIR/ast_param.h"
	copy_feature "$feat/fcntl" "$INCDIR/ast_fcntl.h"

	# ── Tier 4: limits (needs param + conf, must precede nl_types) ──
	# conf.sh compiles with #include "FEATURE/standards", "FEATURE/common",
	# "FEATURE/param" — so it must run after param.sh (tier 3) completes.
	run_libast_conf
	run_iffe "$workdir" "$srcdir/features/limits.c" \
		-I"$srcdir/comp" -I"$srcdir/include"
	copy_feature "$feat/limits" "$INCDIR/ast_limits.h"

	# ── Tier 5: wide parallel band — all independent of each other ──
	run_iffe "$workdir" "$srcdir/features/omitted" &
	run_iffe "$workdir" "$srcdir/features/tvlib" &
	run_iffe "$workdir" "$srcdir/features/syscall" &
	run_iffe "$workdir" "$srcdir/features/hack" &
	run_iffe "$workdir" "$srcdir/features/tmlib" &
	run_iffe "$workdir" "$srcdir/features/float" &
	run_iffe "$workdir" "$srcdir/features/dirent" &
	run_iffe "$workdir" "$srcdir/features/wctype" &
	run_iffe "$workdir" "$srcdir/features/stdio" &
	run_iffe "$workdir" "$srcdir/features/nl_types" &
	run_iffe "$workdir" "$srcdir/features/mode.c" \
		-I"$srcdir/include" &
	run_iffe "$workdir" "$srcdir/features/ccode" &
	run_iffe "$workdir" "$srcdir/features/time" &
	run_iffe "$workdir" "$srcdir/features/tv" &
	run_iffe "$workdir" "$srcdir/features/ndbm" &
	run_iffe "$workdir" "$srcdir/features/sizeof" &
	run_iffe "$workdir" "$srcdir/features/align.c" &
	run_iffe "$workdir" "$srcdir/features/random" &
	run_iffe "$workdir" "$srcdir/features/siglist" &
	wait

	# Copy FEATURE results to canonical headers
	for name in dirent wctype stdio nl_types mode ccode time float ndbm sizeof random; do
		copy_feature "$feat/$name" "$INCDIR/ast_${name}.h"
	done
	for name in tv align; do
		copy_feature "$feat/$name" "$INCDIR/${name}.h"
	done

	# ── Tier 6: probes that depend on tier 5 outputs ──
	run_iffe "$workdir" "$srcdir/features/signal.c" &
	run_iffe "$workdir" "$srcdir/features/tmx" &
	run_iffe "$workdir" "$srcdir/features/iconv" $ICONV_FLAGS &
	run_iffe "$workdir" "$srcdir/features/sfinit.c" &
	run_iffe "$workdir" "$srcdir/features/locale" &
	run_iffe "$workdir" "$srcdir/features/libpath.sh" &
	wait
	copy_feature "$feat/iconv" "$INCDIR/ast_iconv.h"
	copy_feature "$feat/tmx" "$INCDIR/tmx.h"

	# Copy all FEATURE results to the main feature dir
	cp -f "$feat"/* "$FEATDIR/" 2>/dev/null || true

	print "configure: libast feature tests done"
}

# Generate conf headers (conflim.h, conftab.h, conftab.c) and lc.h
run_libast_conf()
{
	typeset srcdir=$PACKAGEROOT_ABS/src/lib/libast
	typeset workdir=$BUILDDIR/libast_work
	typeset conftab=$srcdir/comp/conf.tab
	mkdir -p "$workdir"

	# Cache: skip if conftab.h exists and is newer than inputs
	if ! $FORCE && [[ -f "$workdir/conftab.h" ]] \
	   && [[ "$workdir/conftab.h" -nt "$conftab" ]] \
	   && [[ "$workdir/conftab.h" -nt "$srcdir/comp/conf.sh" ]] \
	   && [[ "$workdir/conftab.h" -nt "$CONFIGURE_SELF" ]]; then
		return 0
	fi

	# Create the conf script (prepends HOSTTYPE to comp/conf.sh)
	print "HOSTTYPE='$HOSTTYPE'" > "$workdir/conf"
	cat "$srcdir/comp/conf.sh" >> "$workdir/conf"
	chmod +x "$workdir/conf"

	# Run conf to generate conflim.h, conftab.h, conftab.c
	(
		cd "$workdir"
		./conf -v "$srcdir/comp/conf.tab" \
			"$CC_PATH" ${mam_cc_TARGET:-} ${mam_cc_OPTIMIZE:-} \
			${mam_cc_NOSTRICTALIASING:-} 2>/dev/null
	) || true

	# Copy generated conf headers
	for f in conflim.h conftab.h conftab.c; do
		[[ -f "$workdir/$f" ]] && cp -f "$workdir/$f" "$INCDIR/../$f"
	done

	# Generate lc.h and lctab.c using lcgen
	if [[ -f "$srcdir/port/lcgen.c" ]]; then
		$CC_PATH $CFLAGS -o "$workdir/lcgen" "$srcdir/port/lcgen.c" 2>/dev/null || true
		if [[ -x "$workdir/lcgen" ]]; then
			"$workdir/lcgen" "$INCDIR/../lc.h" "$INCDIR/../lctab.c" \
				< "$srcdir/port/lc.tab" 2>/dev/null || true
		fi
	fi
}

# ── Feature tests: libdll ─────────────────────────────────────────────

run_libdll_features()
{
	typeset srcdir=$PACKAGEROOT_ABS/src/lib/libdll
	typeset workdir=$BUILDDIR_ABS/libdll_work

	mkdir -p "$workdir/FEATURE"

	print "configure: running libdll feature tests ..."
	run_iffe "$workdir" "$srcdir/features/dll"
	[[ -f "$workdir/FEATURE/dll" ]] && cp -f "$workdir/FEATURE/dll" "$workdir/dlldefs.h"
	[[ -f "$workdir/FEATURE/dll" ]] && cp -f "$workdir/FEATURE/dll" "$INCDIR/dlldefs.h"
	[[ -f "$workdir/FEATURE/dll" ]] && cp -f "$workdir/FEATURE/dll" "$FEATDIR/dll"
}

# ── Feature tests: libsum ─────────────────────────────────────────────

run_libsum_features()
{
	typeset srcdir=$PACKAGEROOT_ABS/src/lib/libsum
	typeset workdir=$BUILDDIR_ABS/libsum_work

	mkdir -p "$workdir/FEATURE"

	print "configure: running libsum feature tests ..."
	run_iffe "$workdir" "$srcdir/features/sum"
	[[ -f "$workdir/FEATURE/sum" ]] && cp -f "$workdir/FEATURE/sum" "$FEATDIR/sum"
}

# ── Feature tests: libcmd ─────────────────────────────────────────────

run_libcmd_features()
{
	typeset srcdir=$PACKAGEROOT_ABS/src/lib/libcmd
	typeset workdir=$BUILDDIR_ABS/libcmd_work

	mkdir -p "$workdir/FEATURE"

	print "configure: running libcmd feature tests ..."
	run_iffe "$workdir" "$srcdir/features/symlink" &
	run_iffe "$workdir" "$srcdir/features/sockets" &
	run_iffe "$workdir" "$srcdir/features/ids" &
	run_iffe "$workdir" "$srcdir/features/utsname" &
	wait

	# Copy FEATURE results
	cp -f "$workdir/FEATURE"/* "$FEATDIR/" 2>/dev/null || true
}

# ── Feature tests: ksh26 ──────────────────────────────────────────────
#
# The old build ran these tests AFTER building libast, linking output
# tests against -last. Three tests (externs, options, fchdir) have
# output{} blocks that compiled against AST's sfio — not because they
# needed it, but because it was available. We probe those values with
# standalone C instead, so configure runs in a single pass before any
# compilation.

run_ksh26_features()
{
	typeset srcdir=$PACKAGEROOT_ABS/src/cmd/ksh26
	typeset workdir=$BUILDDIR_ABS/ksh26_work

	mkdir -p "$workdir/FEATURE" "$workdir/probe_input"

	print "configure: running ksh26 feature tests ..."

	# math is the slowest ksh26 probe — run it in parallel with the rest
	run_iffe "$workdir" "$srcdir/features/math.sh" -lm "$srcdir/data/math.tab" &
	run_iffe "$workdir" "$srcdir/features/time" &
	run_iffe "$workdir" "$srcdir/features/options" &
	run_iffe "$workdir" "$srcdir/features/fchdir" &
	run_iffe "$workdir" "$srcdir/features/locale" &
	run_iffe "$workdir" "$srcdir/features/cmds" &
	run_iffe "$workdir" "$srcdir/features/rlimits" &
	run_iffe "$workdir" "$srcdir/features/poll" &
	probe_ksh26_externs "$workdir" "$srcdir" &
	wait

	# Supplement options, fchdir, and poll with probes for their
	# AST-dependent tests that iffe couldn't run without libast
	probe_ksh26_options "$workdir"
	probe_ksh26_fchdir "$workdir"
	probe_ksh26_poll "$workdir"

	# ksh26 FEATURE files stay in ksh26_work/FEATURE/ — do NOT copy
	# them to the shared FEATDIR. ksh26 and libast both generate
	# FEATURE/locale and FEATURE/time with different content; the
	# ksh26 cflags include -I$ksh26_work which resolves correctly.
}

# The original externs feature test has two output{} blocks that compile
# and run programs using AST's sfio and stk libraries. The fail{} block
# for the NV_PID test calls exit 1, aborting iffe entirely. Instead,
# we feed iffe just the simple probes and handle the rest ourselves.
probe_ksh26_externs()
{
	typeset workdir=$1 srcdir=$2
	typeset feat=$workdir/FEATURE

	# Cache: externs input is embedded in configure.ksh, so check
	# the FEATURE output against configure.ksh itself
	if ! $FORCE && [[ -f "$feat/externs" ]] && [[ -s "$feat/externs" ]] \
	   && [[ "$feat/externs" -nt "$CONFIGURE_SELF" ]]; then
		return 0
	fi

	# Simple probes — everything iffe can handle without AST.
	# This is the externs file with the two AST-dependent output{} blocks
	# removed (arg_extrabytes and NV_PID).
	cat > "$workdir/probe_input/externs" <<'IFFE'
hdr	nc
mem	exception.name,_exception.name math.h
lib	setreuid,setregid
lib	memcntl sys/mman.h
lib,sys	pstat
lib	setproctitle
reference	unistd.h
extern	nice		int	(int)
extern	setreuid	int	(uid_t,uid_t)
extern	setregid	int	(gid_t,gid_t)
tst	note{ does the system support #! interpreter paths }end cross{
	cat > "$EXECROOT/file$$" <<!
	#! $(command -v env) true
	exit 1
	!
	chmod 755 "$EXECROOT/file$$"
	if	"$EXECROOT/file$$" 2>/dev/null
	then	echo "#define SHELLMAGIC	1"
	fi
	rm -f "$EXECROOT/file$$"
}end
tst	execve_ignores_argv0 note{ does execve(3) ignore the specified argv[0] }end output{
	#include <string.h>
	#include <unistd.h>
	extern char **environ;
	int main(int argc, char *argv[])
	{
		char *orig0 = argv[0], *newenv[2], b[64];
		int i;
		sprintf(b,"_KSH_EXECVE_TEST_%d=y",(int)getpid());
		newenv[0] = b;
		newenv[1] = NULL;
		for (i = 0; environ[i]; i++)
			if (strcmp(environ[i],newenv[0])==0)
				return !(strcmp(argv[0],"TEST_OK")!=0);
		argv[0] = "TEST_OK";
		execve(orig0,argv,newenv);
		return 128;
	}
}end
tst	execve_dir_enoexec note{ does execve(3) set errno to ENOEXEC when trying to execute a directory }end output{
	#include <sys/stat.h>
	#include <unistd.h>
	#include <errno.h>
	extern char **environ;
	int main(int argc, char *argv[])
	{
		char	dirname[64];
		int	e;
		sprintf(dirname,".dir.%u",(unsigned int)getpid());
		mkdir(dirname,0777);
		execve(dirname,argv,environ);
		e = errno;
		rmdir(dirname);
		return !(e == ENOEXEC);
	}
}end
IFFE

	run_iffe "$workdir" "$workdir/probe_input/externs"

	# NV_PID — map sizeof(pid_t) to NV integer attribute flags.
	# The original used sfprintf for output; we use printf.
	probe_c >> "$feat/externs" <<'PROBE'
#include <sys/types.h>
#include <stdint.h>
#include <stdio.h>
int main(void) {
	if (sizeof(pid_t) == sizeof(int16_t))
		printf("#define NV_PID\t(NV_INTEGER|NV_SHORT)\n");
	else if (sizeof(pid_t) == sizeof(int32_t))
		printf("#define NV_PID\t(NV_INTEGER)\n");
	else if (sizeof(pid_t) == 8)
		printf("#define NV_PID\t(NV_INTEGER|NV_LONG)\n");
	return 0;
}
PROBE

	# _arg_extrabytes — extra bytes consumed per argv entry beyond strlen+1.
	# The original did trial-and-error fork/exec using AST's stk allocator.
	# sizeof(char*) is the correct value on modern macOS, Linux, and BSD.
	print '#define _arg_extrabytes	sizeof(char*)' >> "$feat/externs"
}

# SHOPT_GLOBCASEDET — can we detect filesystem case insensitivity?
# The original called AST's pathicase(), which uses pathconf(2).
probe_ksh26_options()
{
	typeset workdir=$1
	typeset feat=$workdir/FEATURE/options

	# Already probed by iffe? Check if SHOPT_GLOBCASEDET is defined
	grep -q SHOPT_GLOBCASEDET "$feat" 2>/dev/null && return

	probe_c >> "$feat" <<'PROBE'
#include <stdio.h>
#include <unistd.h>
int main(void) {
	long r;
#ifdef _PC_CASE_INSENSITIVE
	r = pathconf("/", _PC_CASE_INSENSITIVE);
#elif defined(_PC_CASE_SENSITIVE)
	r = pathconf("/", _PC_CASE_SENSITIVE);
	if (r >= 0) r = !r;  /* invert: case_sensitive=1 means NOT insensitive */
#else
	r = -1;
#endif
	if (r > -1)
		printf("#ifndef SHOPT_GLOBCASEDET\n#   define SHOPT_GLOBCASEDET\t1\n#endif\n");
	return 0;
}
PROBE
}

# fchdir O_SEARCH compatibility — can fchdir use O_SEARCH file descriptors?
# The original used AST's O_SEARCH/O_cloexec macros.
probe_ksh26_fchdir()
{
	typeset workdir=$1
	typeset feat=$workdir/FEATURE/fchdir

	# Already probed?
	grep -q fchdir_osearch_compat "$feat" 2>/dev/null && return

	probe_c >> "$feat" <<'PROBE'
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/wait.h>
int main(void) {
	int flags = O_DIRECTORY | O_NONBLOCK;
	char dir[64];
	pid_t child;
	int n;
#ifdef O_SEARCH
	flags |= O_SEARCH;
#elif defined(O_PATH)
	flags |= O_PATH;
#else
	return 1;  /* no O_SEARCH or O_PATH */
#endif
#ifdef O_CLOEXEC
	flags |= O_CLOEXEC;
#endif
	sprintf(dir, ".probe_fchdir.%u", (unsigned)getpid());
	mkdir(dir, 0777);
	child = fork();
	if (child == 0) {
		n = open(dir, flags);
		if (n < 0) return 1;
		if (fchdir(n) < 0) return 1;
		return 0;
	} else if (child == -1) {
		rmdir(dir);
		return 1;
	}
	waitpid(child, &n, 0);
	rmdir(dir);
	if (WIFEXITED(n) && WEXITSTATUS(n) == 0)
		printf("#define _fchdir_osearch_compat\t1\n");
	return 0;
}
PROBE
}

# poll socketpair probes — the original features/poll has execute{} blocks
# that call sfpkrd() and ast_close() from libast, which isn't built yet.
# We test socketpair peekability using recv(MSG_PEEK) directly — that's
# what sfpkrd uses internally on socket fds.
probe_ksh26_poll()
{
	typeset workdir=$1
	typeset feat=$workdir/FEATURE/poll

	# Already probed?
	grep -q pipe_socketpair "$feat" 2>/dev/null && return

	# pipe_socketpair: can recv(MSG_PEEK) read from a socketpair fd?
	# This is an execute-only test (exit code matters, no stdout).
	typeset src=$BUILDDIR_ABS/probe_poll$$.c
	typeset bin=$BUILDDIR_ABS/probe_poll$$
	trap 'rm -f "$src" "$bin" "${src%.c}.d"' EXIT
	cat > "$src" <<'EXECPROBE'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/wait.h>
#ifndef SHUT_RD
#define SHUT_RD		0
#endif
#ifndef SHUT_WR
#define SHUT_WR		1
#endif
static void handler(int sig) { _exit(0); }
int main(void) {
	int sfd[2];
	char buf[256];
	pid_t pid;
	static char msg[] = "hello world\n";
	if (socketpair(AF_UNIX, SOCK_STREAM, 0, sfd) < 0 ||
	    shutdown(sfd[1], SHUT_RD) < 0 ||
	    shutdown(sfd[0], SHUT_WR) < 0)
		return 1;
	if ((pid = fork()) < 0)
		return 1;
	if (pid) {
		int n;
		close(sfd[1]);
		wait(&n);
		if (recv(sfd[0], buf, sizeof(buf), MSG_PEEK) < 0)
			return 1;
		close(sfd[0]);
		signal(SIGPIPE, handler);
		if (socketpair(AF_UNIX, SOCK_STREAM, 0, sfd) < 0 ||
		    shutdown(sfd[1], SHUT_RD) < 0 ||
		    shutdown(sfd[0], SHUT_WR) < 0)
			return 1;
		close(sfd[0]);
		write(sfd[1], msg, sizeof(msg) - 1);
		return 1;
	} else {
		close(sfd[0]);
		write(sfd[1], msg, sizeof(msg) - 1);
		return 0;
	}
}
EXECPROBE
	if $CC_PATH $CFLAGS -o "$bin" "$src" 2>/dev/null && "$bin" 2>/dev/null; then
		printf '#define _pipe_socketpair\t1\t/* use socketpair() for peekable pipe() */\n' >> "$feat"
	fi
	rm -f "$src" "$bin" "${src%.c}.d"

	# socketpair_devfd: can /dev/fd/N access socketpair fds?
	cat > "$src" <<'EXECPROBE'
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/socket.h>
int main(void) {
	int n, sfd[2];
	close(0);
	open("/dev/null", O_RDONLY);
	if ((n = open("/dev/fd/0", O_RDONLY)) < 0) return 1;
	close(n);
	if (socketpair(AF_UNIX, SOCK_STREAM, 0, sfd) < 0 ||
	    shutdown(sfd[0], 1) < 0 || shutdown(sfd[1], 0) < 0) return 1;
	close(0);
	dup(sfd[0]);
	close(sfd[0]);
	if ((n = open("/dev/fd/0", O_RDONLY)) < 0) return 1;
	return 0;
}
EXECPROBE
	if $CC_PATH $CFLAGS -o "$bin" "$src" 2>/dev/null && "$bin" 2>/dev/null; then
		printf '#define _socketpair_devfd\t1\t/* /dev/fd/N handles socketpair() */\n' >> "$feat"
	fi
	rm -f "$src" "$bin" "${src%.c}.d"

	# socketpair_shutdown_mode: does fchmod work after shutdown?
	cat > "$src" <<'EXECPROBE'
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/socket.h>
int main(void) {
	int sfd[2];
	struct stat st0, st1;
	if (socketpair(AF_UNIX, SOCK_STREAM, 0, sfd) < 0 ||
	    shutdown(sfd[0], 1) < 0 || shutdown(sfd[1], 0) < 0) return 1;
	if (fstat(sfd[0], &st0) < 0 || fstat(sfd[1], &st1) < 0) return 1;
	if ((st0.st_mode & (S_IRUSR|S_IWUSR)) == S_IRUSR &&
	    (st1.st_mode & (S_IRUSR|S_IWUSR)) == S_IWUSR) return 1;
	if (fchmod(sfd[0], S_IRUSR) < 0 || fstat(sfd[0], &st0) < 0 ||
	    (st0.st_mode & (S_IRUSR|S_IWUSR)) != S_IRUSR) return 1;
	if (fchmod(sfd[1], S_IWUSR) < 0 || fstat(sfd[1], &st1) < 0 ||
	    (st1.st_mode & (S_IRUSR|S_IWUSR)) != S_IWUSR) return 1;
	return 0;
}
EXECPROBE
	if $CC_PATH $CFLAGS -o "$bin" "$src" 2>/dev/null && "$bin" 2>/dev/null; then
		printf '#define _socketpair_shutdown_mode\t1\t/* fchmod() after socketpair() shutdown() */\n' >> "$feat"
	fi
	rm -f "$src" "$bin" "${src%.c}.d"
	trap - EXIT
}

# ── Generate headers: git.h ───────────────────────────────────────────

generate_git_h()
{
	typeset outdir=$BUILDDIR/ksh26_work
	mkdir -p "$outdir"

	typeset git_commit=""
	git_commit=$(git rev-parse --short=8 HEAD 2>/dev/null) || true
	case $git_commit in
	[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f])
		print '/* generated by configure.ksh */'
		git update-index --really-refresh >/dev/null 2>&1 || true
		if ! git diff-index --quiet HEAD 2>/dev/null; then
			git_commit=$git_commit/MOD
		fi
		print "#define git_commit   \"$git_commit\""
		;;
	*)
		print '/* not in a git repo */'
		print '#undef git_commit'
		;;
	esac > "$outdir/git.h.new"

	if cmp -s "$outdir/git.h.new" "$outdir/git.h" 2>/dev/null; then
		rm -f "$outdir/git.h.new"
	else
		mv -f "$outdir/git.h.new" "$outdir/git.h"
	fi
}

# ── Generate headers: shopt.h ─────────────────────────────────────────

generate_shopt_h()
{
	typeset outdir=$BUILDDIR/ksh26_work
	mkdir -p "$outdir"

	# Define the SHOPT function that processes each option
	writedef()
	{
		print "${3:-#ifndef SHOPT_$1}"
		print "#   define SHOPT_$1	$2"
		print '#endif'
		print
	}

	SHOPT()
	{
		typeset n=${1%%=*}
		typeset v=${1#*=}
		case $1 in
		'MULTIBYTE=')
			writedef MULTIBYTE 1 '#if !defined(SHOPT_MULTIBYTE) && !AST_NOMULTIBYTE' ;;
		'DEVFD=')
			ls -d /dev/fd/9 9<&0 >/dev/null 2>&1 && writedef DEVFD 1 ;;
		'TEST_L=')
			typeset link=$BUILDDIR_ABS/link$$
			ln -s /dev/null "$link" 2>/dev/null || true
			if env test -l "$link" 2>/dev/null && env test ! -l . 2>/dev/null; then
				writedef TEST_L 1
			fi
			rm -f "$link"
			;;
		'PRINTF_LEGACY=')
			case $(env printf '-zut%s\n' alors 2>/dev/null) in
			-zutalors) writedef PRINTF_LEGACY 1 ;;
			esac
			;;
		*=?*)
			writedef "$n" "$v" ;;
		esac
	}

	{
		print '/* Generated from ksh26/SHOPT.sh by configure.ksh */'
		print
		. "$PACKAGEROOT/src/cmd/ksh26/SHOPT.sh"
		cat <<-'EOF'
		#include "FEATURE/options"

		/* overrides */
		#if SHOPT_SCRIPTONLY
		#   undef SHOPT_ACCT
		#   undef SHOPT_AUDIT
		#   undef SHOPT_ESH
		#   undef SHOPT_HISTEXPAND
		#   undef SHOPT_SYSRC
		#   undef SHOPT_VSH
		#endif
		#if !_sys_acct
		#   undef SHOPT_ACCT
		#endif
		EOF
	} > "$outdir/shopt.h.new"

	if cmp -s "$outdir/shopt.h.new" "$outdir/shopt.h" 2>/dev/null; then
		rm -f "$outdir/shopt.h.new"
	else
		mv -f "$outdir/shopt.h.new" "$outdir/shopt.h"
	fi
}

# ── Generate headers: cmdext.h and cmdlist.h ──────────────────────────

generate_cmd_headers()
{
	typeset srcdir=src/lib/libcmd
	typeset outdir=$BUILDDIR/libcmd_work
	mkdir -p "$outdir"

	# cmdext.h — extern function prototypes for b_* commands
	{
		print '/*'
		print ' * -lcmd extern function prototypes'
		print ' */'
		print
		sed -e '/^b_[a-z_][a-z_0-9]*(/!d' \
			-e 's/^b_//' \
			-e 's/(.*//' \
			-e 's/.*/extern int	b_&(int, char**, Shbltin_t*);/' \
			"$srcdir"/*.c | sort -u
	} > "$outdir/cmdext.h.new"

	# cmdlist.h — CMDLIST() macros
	{
		print '/*'
		print ' * -lcmd function list -- define your own CMDLIST()'
		print ' */'
		print
		sed -e '/^b_[a-z_][a-z_0-9]*(/!d' \
			-e 's/^b_//' \
			-e 's/(.*//' \
			-e 's/.*/CMDLIST(&)/' \
			"$srcdir"/*.c | sort -u
	} > "$outdir/cmdlist.h.new"

	# Install to include dir only if changed (avoids triggering recompilation)
	typeset changed=false
	for h in cmdext.h cmdlist.h; do
		if cmp -s "$outdir/$h.new" "$outdir/$h" 2>/dev/null; then
			rm -f "$outdir/$h.new"
		else
			mv -f "$outdir/$h.new" "$outdir/$h"
			changed=true
		fi
	done
	if $changed; then
		cp -f "$outdir/cmdext.h" "$INCDIR/cmdext.h"
		cp -f "$outdir/cmdlist.h" "$INCDIR/cmdlist.h"
	fi
}

# ── Source file discovery ─────────────────────────────────────────────
# Walk source directories and collect .c files, excluding generated/special files.

collect_libast_sources()
{
	# Exclude: lcgen.c (build tool), astmath.c (probe helper),
	# features/*.c (iffe input, not compiled), conftab.c (generated)
	find src/lib/libast -name '*.c' \
		-not -name 'lcgen.c' \
		-not -name 'astmath.c' \
		-not -path '*/features/*' \
		| sort
}

collect_libsum_sources()
{
	# libsum compiles a single file: sumlib.c (which includes the rest)
	print "src/lib/libsum/sumlib.c"
}

collect_libdll_sources()
{
	find src/lib/libdll -name '*.c' -not -path '*/features/*' | sort
}

collect_libcmd_sources()
{
	find src/lib/libcmd -name '*.c' -not -path '*/features/*' | sort
}

collect_ksh26_sources()
{
	# All .c files in sh/, bltins/, edit/, data/ subdirectories
	# Exclude tests/ and the features/ directory
	find src/cmd/ksh26 -name '*.c' \
		-not -path '*/tests/*' \
		-not -path '*/features/*' \
		| sort
}

# ── Emit build.ninja ──────────────────────────────────────────────────

emit_ninja()
{
	typeset ninja=$BUILDDIR/build.ninja.new
	typeset cc=$CC_PATH
	typeset ar=${mam_cc_AR:-ar}

	# Include paths are absolute so they work from samu's -C directory.
	# ast_std intercepts <stdio.h>, <wchar.h> etc. with AST's wrappers
	# that handle the FILE → Sfio_t redirection.
	typeset ast_inc="-I$PACKAGEROOT_ABS/$INCDIR"
	typeset ast_std="-I$PACKAGEROOT_ABS/$BUILDDIR/include/std"
	typeset ast_inc_parent="-I$PACKAGEROOT_ABS/$BUILDDIR/include"
	typeset src_abs=$PACKAGEROOT_ABS

	print "configure: generating $ninja ..."

	cat > "$ninja" <<NINJA
# build.ninja — generated by configure.ksh
# HOSTTYPE: $HOSTTYPE
# CC: $cc
# All output paths are relative to this file's directory.
# Source and include paths are absolute.

rule cc
  command = $cc $CFLAGS -MD -MF \$out.d \$extra_cflags -c \$in -o \$out
  depfile = \$out.d
  deps = gcc
  description = CC \$in

rule ar
  command = rm -f \$out && $ar cr \$out \$in
  description = AR \$out

rule link
  command = $cc $CFLAGS \$ldflags -o \$out \$in \$libs
  description = LINK \$out

NINJA

	# ── libast ──────────────────────────────────────────────────────

	typeset libast_objs=""
	typeset libast_cflags="-D_BLD_ast -DHOSTTYPE='\"$HOSTTYPE\"' $ast_inc $ast_inc_parent"

	# Include libast subdirectories — source files cross-reference
	# private headers across subdirectories (e.g. tm/tmlocale.c includes
	# port/lclib.h). Exclude features/ and man/ — features/ would shadow
	# the generated FEATURE/ headers on case-insensitive filesystems.
	typeset libast_inc=""
	typeset d
	for d in $src_abs/src/lib/libast/*/; do
		case $d in
		*/features/|*/man/) continue ;;
		esac
		libast_inc="$libast_inc -I$d"
	done
	libast_inc="$libast_inc -I$src_abs/src/lib/libast"

	while IFS= read -r src; do
		typeset base=${src##*/}
		typeset obj=obj/libast/${base%.c}.o

		cat >> "$ninja" <<NINJA
build $obj: cc $src_abs/$src
  extra_cflags = $libast_cflags $libast_inc
NINJA
		libast_objs="$libast_objs $obj"
	done < <(collect_libast_sources)

	# Generated source files (conftab.c, lctab.c)
	if [[ -f "$BUILDDIR/include/conftab.c" ]]; then
		typeset obj=obj/libast/conftab.o
		cat >> "$ninja" <<NINJA
build $obj: cc $BUILDDIR_ABS/include/conftab.c
  extra_cflags = $libast_cflags $libast_inc
NINJA
		libast_objs="$libast_objs $obj"
	fi

	if [[ -f "$BUILDDIR/include/lctab.c" ]]; then
		typeset obj=obj/libast/lctab.o
		cat >> "$ninja" <<NINJA
build $obj: cc $BUILDDIR_ABS/include/lctab.c
  extra_cflags = $libast_cflags $libast_inc
NINJA
		libast_objs="$libast_objs $obj"
	fi

	cat >> "$ninja" <<NINJA

build lib/libast.a: ar $libast_objs

NINJA

	# ── libsum ──────────────────────────────────────────────────────

	typeset libsum_cflags="-I$src_abs/src/lib/libsum $ast_std $ast_inc $ast_inc_parent"

	cat >> "$ninja" <<NINJA
build obj/libsum/sumlib.o: cc $src_abs/src/lib/libsum/sumlib.c
  extra_cflags = $libsum_cflags

build lib/libsum.a: ar obj/libsum/sumlib.o

NINJA

	# ── libdll ──────────────────────────────────────────────────────

	typeset libdll_objs=""
	typeset libdll_cflags="-D_BLD_dll -I$src_abs/src/lib/libdll $ast_std $ast_inc $ast_inc_parent"

	while IFS= read -r src; do
		typeset base=${src##*/}
		typeset obj=obj/libdll/${base%.c}.o
		cat >> "$ninja" <<NINJA
build $obj: cc $src_abs/$src
  extra_cflags = $libdll_cflags
NINJA
		libdll_objs="$libdll_objs $obj"
	done < <(collect_libdll_sources)

	cat >> "$ninja" <<NINJA

build lib/libdll.a: ar $libdll_objs

NINJA

	# ── libcmd ──────────────────────────────────────────────────────

	typeset libcmd_objs=""
	typeset libcmd_cflags="-D_BLD_cmd -DERROR_CATALOG='\"libcmd\"' -DHOSTTYPE='\"$HOSTTYPE\"' -I$src_abs/src/lib/libcmd -I$BUILDDIR_ABS/libcmd_work $ast_std $ast_inc $ast_inc_parent"

	while IFS= read -r src; do
		typeset base=${src##*/}
		typeset obj=obj/libcmd/${base%.c}.o
		cat >> "$ninja" <<NINJA
build $obj: cc $src_abs/$src
  extra_cflags = $libcmd_cflags
NINJA
		libcmd_objs="$libcmd_objs $obj"
	done < <(collect_libcmd_sources)

	# libcmd also needs sumlib.o for checksum builtins
	libcmd_objs="$libcmd_objs obj/libsum/sumlib.o"

	cat >> "$ninja" <<NINJA

build lib/libcmd.a: ar $libcmd_objs

NINJA

	# ── ksh26 (libshell + binaries) ────────────────────────────────

	typeset ksh_objs=""
	typeset ksh_srcdir=src/cmd/ksh26
	typeset ksh_cflags="-D_BLD_ksh -DSH_DICT='\"libshell\"' -D_API_ast=20100309"
	ksh_cflags="$ksh_cflags -I$BUILDDIR_ABS/ksh26_work"
	ksh_cflags="$ksh_cflags -I$src_abs/$ksh_srcdir"
	ksh_cflags="$ksh_cflags -I$src_abs/$ksh_srcdir/include"
	ksh_cflags="$ksh_cflags $ast_std $ast_inc $ast_inc_parent"

	while IFS= read -r src; do
		typeset base=${src##*/}
		typeset obj=obj/ksh26/${base%.c}.o
		typeset extra=""

		case $base in
		pmain.c|shcomp.c) continue ;;
		esac

		case $src in
		*/data/builtins.c|*/bltins/typeset.c|*/sh/path.c)
			extra="-DSHOPT_DYNAMIC=0" ;;
		esac

		cat >> "$ninja" <<NINJA
build $obj: cc $src_abs/$src
  extra_cflags = $ksh_cflags $extra
NINJA
		ksh_objs="$ksh_objs $obj"
	done < <(collect_ksh26_sources)

	cat >> "$ninja" <<NINJA

build lib/libshell.a: ar $ksh_objs

build obj/ksh26/pmain.o: cc $src_abs/$ksh_srcdir/sh/pmain.c
  extra_cflags = $ksh_cflags

build obj/ksh26/shcomp.o: cc $src_abs/$ksh_srcdir/sh/shcomp.c
  extra_cflags = $ksh_cflags

build bin/ksh: link obj/ksh26/pmain.o | lib/libshell.a lib/libcmd.a lib/libast.a lib/libdll.a lib/libsum.a
  libs = -Llib -lshell -lcmd -last -ldll -lsum -lm $ICONV_FLAGS
  ldflags =

build bin/shcomp: link obj/ksh26/shcomp.o | lib/libshell.a lib/libcmd.a lib/libast.a lib/libdll.a lib/libsum.a
  libs = -Llib -lshell -lcmd -last -ldll -lsum -lm $ICONV_FLAGS
  ldflags =

default bin/ksh bin/shcomp
NINJA

	# ── Test targets ──────────────────────────────────────────

	typeset test_runner=$BUILDDIR_ABS/run-test.sh
	typeset tests_dir=$src_abs/src/cmd/ksh26/tests

	cat >> "$ninja" <<NINJA

# ── Tests ──────────────────────────────────────────────────
# Each test runs in C and C.UTF-8 locales in parallel.
# samu test    — run all tests
# samu test/basic.C.stamp — run one test

rule test
  command = sh $test_runner \$in \$mode \$out
  description = TEST \$desc

rule test_serial
  command = sh $test_runner \$in \$mode \$out
  description = TEST \$desc
  pool = serial

pool serial
  depth = 1

NINJA

	typeset all_stamps=""
	typeset setslocale="locale"
	typeset timesensitive="options sigchld subshell"

	for test_sh in "$tests_dir"/*.sh; do
		[[ -f "$test_sh" ]] || continue
		typeset name=${test_sh##*/}
		name=${name%.sh}

		# Time-sensitive tests use the serial rule
		typeset rule="test"
		case " $timesensitive " in
		*" $name "*) rule="test_serial" ;;
		esac

		# C locale test
		cat >> "$ninja" <<NINJA
build test/${name}.C.stamp: $rule $test_sh | bin/ksh bin/shcomp
  mode = C
  desc = $name (C)
NINJA
		all_stamps="$all_stamps test/${name}.C.stamp"

		# C.UTF-8 locale test (skip locale.sh — it sets its own locale)
		case " $setslocale " in
		*" $name "*) ;;
		*)
			cat >> "$ninja" <<NINJA
build test/${name}.C.UTF-8.stamp: $rule $test_sh | bin/ksh bin/shcomp
  mode = C.UTF-8
  desc = $name (C.UTF-8)
NINJA
			all_stamps="$all_stamps test/${name}.C.UTF-8.stamp"
			;;
		esac
	done

	# Phony target to run all tests
	cat >> "$ninja" <<NINJA

build test: phony $all_stamps
NINJA

	typeset stmts
	stmts=$(grep -c '^build ' "$ninja")
	typeset final=${ninja%.new}
	if cmp -s "$ninja" "$final" 2>/dev/null; then
		rm -f "$ninja"
		print "configure: build.ninja unchanged ($stmts build statements)"
	else
		mv -f "$ninja" "$final"
		print "configure: wrote $final ($stmts build statements)"
	fi
}

# ── Generate test infrastructure ──────────────────────────────────────
# Emit a test-env.sh (SHOPT_* exports) and run-test.sh (single-test
# runner) so that ninja can run tests in parallel.

generate_test_env()
{
	typeset outdir=$BUILDDIR
	typeset shopt_h=$outdir/ksh26_work/shopt.h

	{
		print '# test-env.sh — generated by configure.ksh'
		print '# Source this to get SHOPT_* environment variables.'
		print

		# Feed SHOPT.sh through a subshell to capture the exports
		(
			SHOPT()
			{
				typeset n=${1%%=*}
				typeset v=${1#*=}
				case $1 in
				*=?*) print "export SHOPT_$n=$v" ;;
				esac
			}
			. "$PACKAGEROOT/src/cmd/ksh26/SHOPT.sh"
		)

		# Override with probed values from shopt.h
		# Names already start with SHOPT_ so just prefix 'export '
		if [[ -f "$shopt_h" ]]; then
			sed -n '/^#[ 	]*define[ 	][ 	]*SHOPT_/ {
				s/.*define[ 	][ 	]*//
				s/[ 	][ 	]*/=/
				s/^/export /
				p
			}' "$shopt_h"
		fi
	} > "$outdir/test-env.sh"
}

generate_test_runner()
{
	typeset outdir=$BUILDDIR
	typeset runner=$outdir/run-test.sh

	# Write header with configure-time paths, then quoted heredoc body
	print '#!/bin/sh' > "$runner"
	print "PACKAGEROOT='$PACKAGEROOT_ABS'" >> "$runner"
	print "BUILDDIR='$BUILDDIR_ABS'" >> "$runner"

	cat >> "$runner" <<'RUNNER'

test_file="$1"
mode="$2"
stamp="$3"

test_name=$(basename "$test_file" .sh)

# Resolve stamp to absolute path (samu -C makes it relative to build dir)
case $stamp in
/*) ;;
*)  stamp="$BUILDDIR/$stamp" ;;
esac
log="${stamp}.log"

# ── Environment ──────────────────────────────────────────────
unset DISPLAY FIGNORE HISTFILE POSIXLY_CORRECT _AST_FEATURES

. "${0%/*}/test-env.sh"

export ENV=/./dev/null
export SHTESTS_COMMON="${PACKAGEROOT}/src/cmd/ksh26/tests/_common"
export SHELL="${BUILDDIR}/bin/ksh"
export SHCOMP="${BUILDDIR}/bin/shcomp"

PATH=/usr/bin:/bin:/usr/sbin:/sbin
PATH="${BUILDDIR}/bin:$PATH"
export PATH

case $mode in
C)      unset LANG LC_ALL ;;
C.UTF-8) export LANG=C.UTF-8; unset LC_ALL ;;
esac

# Per-test temp directory (cd -P resolves symlinks so $tmp == $PWD in ksh)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ksh26.test.${test_name}.${mode}.XXXXXX") || exit 1
tmp=$(cd -P "$tmp" && pwd) || exit 1
export HOME="$tmp" tmp
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$(dirname "$log")"

# ── Run ──────────────────────────────────────────────────────
cd "$tmp" || exit 1

rc=0
"$SHELL" "$test_file" >"$log" 2>&1 || rc=$?

if [ "$rc" -eq 0 ]; then
	touch "$stamp"
	rm -f "$log"
	exit 0
else
	cat "$log" >&2
	rm -f "$stamp"
	exit "$rc"
fi
RUNNER
	chmod +x "$runner"
}

# ── Install public headers ────────────────────────────────────────────
# Copy source headers into the build include directory so all libraries
# and ksh26 can find them via -I$INCDIR.

install_headers()
{
	print "configure: installing public headers ..."

	# libast public headers
	cp -f src/lib/libast/include/*.h "$INCDIR/"

	# libast std/ wrapper headers (override system headers for AST compat)
	mkdir -p "$BUILDDIR/include/std"
	cp -f src/lib/libast/std/*.h "$BUILDDIR/include/std/"

	# libast private headers needed for compilation
	# These are referenced by source files via relative include paths,
	# but we also need them in the build tree for generated code.
	for d in comp sfio; do
		for f in src/lib/libast/$d/*.h; do
			[[ -f "$f" ]] && cp -f "$f" "$INCDIR/"
		done
	done

	# libsum public headers
	cp -f src/lib/libsum/sum.h "$INCDIR/"

	# libdll public headers
	# dlldefs.h is generated from FEATURE/dll (handled in run_libdll_features)

	# libcmd public headers
	cp -f src/lib/libcmd/cmd.h "$INCDIR/" 2>/dev/null || true

	# ksh26 public headers
	for h in nval shell history; do
		cp -f "src/cmd/ksh26/include/$h.h" "$INCDIR/" 2>/dev/null || true
	done

	# libcmd needs shcmd.h from libast
	# (already in libast/include/)
}

# ── Main ──────────────────────────────────────────────────────────────

print "configure: starting configuration for $HOSTTYPE ..."

# Phase 0: Install public headers (needed by feature tests and compilation)
install_headers

# Phase 1: Feature detection
run_libast_features

# libsum, libdll, libcmd, ksh26 are independent of each other
# (they only depend on libast feature headers being installed)
run_libsum_features &
run_libdll_features &
run_libcmd_features &
run_ksh26_features &
wait

{
	typeset _iffe_cached _iffe_ran
	_iffe_cached=$(grep -c cached "$_iffe_log" 2>/dev/null) || _iffe_cached=0
	_iffe_ran=$(grep -c ran "$_iffe_log" 2>/dev/null) || _iffe_ran=0
	if (( _iffe_cached > 0 )); then
		print "configure: feature probes: $_iffe_ran ran, $_iffe_cached cached"
	fi
}

# Phase 2: Generate headers
generate_git_h
generate_shopt_h
generate_cmd_headers

# Phase 3: Emit build.ninja
emit_ninja

# Phase 4: Test infrastructure
generate_test_env
generate_test_runner

# Ensure test stamp dir exists
mkdir -p "$BUILDDIR/test"

# Install shopt.h where bin/shtests expects it (legacy compat)
mkdir -p "$BUILDDIR/src/cmd/ksh26"
cp -f "$BUILDDIR/ksh26_work/shopt.h" "$BUILDDIR/src/cmd/ksh26/shopt.h"

print "configure: done"

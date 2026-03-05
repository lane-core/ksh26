#!/bin/sh

# configure.sh — probe platform, detect features, generate build.ninja
#
# Part of the ksh26 build system: just (porcelain) → configure.sh → samu
# This script replaces the MAM (Make Abstract Machine) build infrastructure
# with a single-pass configure step that emits a ninja build file.
#
# Usage: sh configure.sh [--force] [--debug] [--asan]
#   Probes the compiler, runs iffe feature tests, and writes
#   build/$HOSTTYPE[-suffix]/build.ninja
#
# With --force, all probes rerun unconditionally (ignoring cache).
# Without it, probes are skipped when their output is fresher than
# their input — typically cutting reconfigure from minutes to seconds.
#
# With --debug, uses -O0 -g for reliable single-step debugging.
# With --asan, enables AddressSanitizer + UBSan.
#
# Flags compose: --debug --asan → build/$HOSTTYPE-debug-asan/
# Each variant runs its own independent feature probes.

set -o nounset -o errexit

# ── Options ───────────────────────────────────────────────────────────

FORCE=false
DEBUG=false
ASAN=false
for _arg in "$@"; do
	case $_arg in
	--force) FORCE=true ;;
	--debug) DEBUG=true ;;
	--asan)  ASAN=true ;;
	esac
done

# ── HOSTTYPE detection ─────────────────────────────────────────────────
# Produces os.arch-bits, e.g. darwin.arm64-64, linux.x86_64-64.
# Replaces the 850-line hostinfo() function from bin/package.

detect_hosttype()
{
	local os arch bits
	os=$(uname -s | tr 'A-Z' 'a-z')
	arch=$(uname -m)
	case $arch in
	aarch64) arch=arm64 ;;
	i?86)    arch=i386 ;;
	esac
	bits=$(getconf LONG_BIT 2>/dev/null) || bits=64
	printf '%s\n' "${os}.${arch}-${bits}"
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
_suffix=""
$DEBUG && _suffix="${_suffix}-debug"
$ASAN  && _suffix="${_suffix}-asan"
BUILDDIR=build/${HOSTTYPE}${_suffix}
OBJDIR=$BUILDDIR/obj
INCDIR=$BUILDDIR/include/ast
LIBDIR=$BUILDDIR/lib
FEATDIR=$BUILDDIR/include/ast/FEATURE

# Absolute paths (needed by iffe)
PACKAGEROOT_ABS=$(cd "$PACKAGEROOT" && pwd)
BUILDDIR_ABS=$PACKAGEROOT_ABS/$BUILDDIR

mkdir -p "$BUILDDIR/bin" "$OBJDIR" "$INCDIR" "$LIBDIR" "$FEATDIR" \
	"$OBJDIR/libast" "$OBJDIR/libcmd" \
	"$OBJDIR/ksh26"

# ── Compiler probe ────────────────────────────────────────────────────
# Detect compiler capabilities directly. Replaces the 3,200-line
# mamprobe.sh + C+probe + make.probe chain that was designed for
# shared library probing across 1990s Unix variants. ksh26 builds
# static archives — we only need AR, optimization, and aliasing flags.

CC=${CC:-cc}
CC_PATH=$(command -v "$CC")

# Temp file for compile probes (dsymutil chokes on /dev/null with -g)
_probe_out=$(mktemp "${TMPDIR:-/tmp}/ksh26.probe.XXXXXX") || exit 1
trap 'rm -f "$_probe_out"' EXIT

# AR: prefer co-located with CC, fall back to PATH
_cc_dir=${CC_PATH%/*}
if [ -x "$_cc_dir/ar" ]; then
	AR="$_cc_dir/ar"
else
	AR=$(command -v ar)
fi

# Optimization: -Os if supported, else -O
# Use here-document instead of pipe to avoid subshell overhead
_optimize=""
if $CC_PATH -Os -x c - -o "$_probe_out" <<'EOF' 2>/dev/null
int main(void){return 0;}
EOF
then
	_optimize="-Os"
elif $CC_PATH -O -x c - -o "$_probe_out" <<'EOF' 2>/dev/null
int main(void){return 0;}
EOF
then
	_optimize="-O"
fi

# Strict aliasing: disable if the flag is accepted
_nostrictaliasing=""
if $CC_PATH -fno-strict-aliasing -x c - -o "$_probe_out" <<'EOF' 2>/dev/null
int main(void){return 0;}
EOF
then
	_nostrictaliasing="-fno-strict-aliasing"
fi

printf '%s\n' "configure: HOSTTYPE=$HOSTTYPE"
printf '%s\n' "configure: CC=$CC_PATH"
printf '%s\n' "configure: AR=$AR"

# ── Compiler flags ────────────────────────────────────────────────────

# Debug info (-g) is always included: zero runtime cost, enables
# useful backtraces. --debug overrides optimization to -O0 for
# reliable single-stepping. --asan adds sanitizer instrumentation.
LDFLAGS=""
if $DEBUG; then
	_optimize="-O0"
fi
if $ASAN; then
	_optimize="${_optimize:+$_optimize }-fsanitize=address,undefined -fno-omit-frame-pointer"
	LDFLAGS="-fsanitize=address,undefined"
fi
CFLAGS="-std=c23 -g $_optimize $_nostrictaliasing ${CFLAGS:-}"

# ── Cache key ─────────────────────────────────────────────────────────
# Invalidate all cached probes when compiler or flags change.

CONFIGURE_SELF=$PACKAGEROOT_ABS/configure.sh
CACHE_KEY="$CC_PATH $CFLAGS"
CACHE_KEY_FILE=$BUILDDIR_ABS/.configure_cache_key

# Optimization: Deduplicate cache invalidation logic.
# Single code path for both --force and compiler-change scenarios.
_invalidate_cache=false
if $FORCE; then
	printf '%s\n' "configure: --force: invalidating all cached probes"
	_invalidate_cache=true
elif [ -f "$CACHE_KEY_FILE" ] && [ "$(cat "$CACHE_KEY_FILE")" = "$CACHE_KEY" ]; then
	: # cache key matches — individual probes check their own freshness
else
	if [ -f "$CACHE_KEY_FILE" ]; then
		printf '%s\n' "configure: compiler or flags changed, invalidating probe cache"
	fi
	_invalidate_cache=true
fi

if $_invalidate_cache; then
	rm -f "$BUILDDIR_ABS"/libast_work/FEATURE/* \
		"$BUILDDIR_ABS"/libcmd_work/FEATURE/* \
		"$BUILDDIR_ABS"/ksh26_work/FEATURE/* \
		"$BUILDDIR_ABS"/pty_work/FEATURE/* \
		"$BUILDDIR_ABS"/.iconv_cache \
		"$BUILDDIR_ABS"/.utf8proc_cache \
		"$CACHE_KEY_FILE" 2>/dev/null || true
fi

printf '%s\n' "$CACHE_KEY" > "$CACHE_KEY_FILE"

# ── Library detection ─────────────────────────────────────────────────
# Detect optional external libraries not always in the default search path.
# On Nix-based macOS, libiconv is a separate derivation outside the
# linker's default -L paths. On stock macOS, it's reexported via libSystem.

ICONV_FLAGS=""
iconv_cache=$BUILDDIR_ABS/.iconv_cache

if [ -f "$iconv_cache" ] && [ "$iconv_cache" -nt "$CONFIGURE_SELF" ]; then
	ICONV_FLAGS=$(cat "$iconv_cache")
	printf '%s\n' "configure: iconv: ${ICONV_FLAGS:-(in libc)} (cached)"
else
	iconv_test='#include <iconv.h>
int main(void) { iconv_open("",""); return 0; }'

	if printf '%s' "$iconv_test" | $CC_PATH $CFLAGS -x c - -o "$_probe_out" 2>/dev/null; then
		ICONV_FLAGS=""
	elif printf '%s' "$iconv_test" | $CC_PATH $CFLAGS -x c - -o "$_probe_out" -liconv 2>/dev/null; then
		ICONV_FLAGS="-liconv"
	else
		_nix_dirs=""
		if [ -d /nix/store ]; then
			_nix_dirs=$(find /nix/store -maxdepth 1 -name '*libiconv-*' \
				-not -name '*-dev' -not -name '*.drv' 2>/dev/null \
				| sort -r | head -3 | sed 's|$|/lib|')
		fi
		for _d in /usr/local/lib /opt/homebrew/lib $_nix_dirs; do
			if [ -d "$_d" ] && printf '%s' "$iconv_test" | $CC_PATH $CFLAGS -x c - -o "$_probe_out" -L"$_d" -liconv 2>/dev/null; then
				ICONV_FLAGS="-L$_d -liconv"
				break
			fi
		done
	fi
	printf '%s\n' "$ICONV_FLAGS" > "$iconv_cache"
	if [ -n "$ICONV_FLAGS" ]; then
		printf '%s\n' "configure: iconv: $ICONV_FLAGS"
	else
		printf '%s\n' "configure: iconv: not found (AST fallback)"
	fi
fi

# ── Optional dependency: utf8proc ─────────────────────────────────────
# utf8proc provides correct Unicode grapheme/width support for the line
# editor (build system). Check system first, fall back to fetching.

UTF8PROC_CFLAGS=""
UTF8PROC_LIBS=""
HAVE_UTF8PROC=0
utf8proc_cache=$BUILDDIR_ABS/.utf8proc_cache

UTF8PROC_VERSION="v2.9.0"
UTF8PROC_REPO="https://github.com/JuliaStrings/utf8proc.git"

if [ -f "$utf8proc_cache" ] && [ "$utf8proc_cache" -nt "$CONFIGURE_SELF" ]; then
	eval "$(cat "$utf8proc_cache")"
	if [ "$HAVE_UTF8PROC" = 1 ]; then
		printf '%s\n' "configure: utf8proc: found (cached)"
	else
		printf '%s\n' "configure: utf8proc: not found (cached)"
	fi
else
	utf8proc_test='#include <utf8proc.h>
int main(void) { utf8proc_grapheme_break(0,0); return 0; }'

	if printf '%s' "$utf8proc_test" | $CC_PATH $CFLAGS -x c - -o "$_probe_out" -lutf8proc 2>/dev/null; then
		UTF8PROC_LIBS="-lutf8proc"
		HAVE_UTF8PROC=1
		printf '%s\n' "configure: utf8proc: system (-lutf8proc)"
	elif command -v pkg-config >/dev/null 2>&1 && pkg-config --exists libutf8proc 2>/dev/null; then
		UTF8PROC_CFLAGS=$(pkg-config --cflags libutf8proc)
		UTF8PROC_LIBS=$(pkg-config --libs libutf8proc)
		HAVE_UTF8PROC=1
		printf '%s\n' "configure: utf8proc: pkg-config ($UTF8PROC_LIBS)"
	else
		# Fetch and build from source
		depdir=$BUILDDIR_ABS/deps/utf8proc
		if [ ! -f "$depdir/utf8proc.c" ]; then
			printf '%s\n' "configure: utf8proc: fetching $UTF8PROC_VERSION ..."
			mkdir -p "$BUILDDIR_ABS/deps"
			git clone --depth 1 --branch "$UTF8PROC_VERSION" \
				"$UTF8PROC_REPO" "$depdir" 2>/dev/null \
				|| { printf '%s\n' "configure: utf8proc: fetch failed (optional)"; }
		fi
		if [ -f "$depdir/utf8proc.c" ]; then
			printf '%s\n' "configure: utf8proc: building from source ..."
			$CC_PATH $CFLAGS -c -o "$depdir/utf8proc.o" \
				-I"$depdir" "$depdir/utf8proc.c" 2>/dev/null \
			&& ar rcs "$depdir/libutf8proc.a" "$depdir/utf8proc.o" 2>/dev/null \
			&& {
				UTF8PROC_CFLAGS="-I$depdir"
				UTF8PROC_LIBS="-L$depdir -lutf8proc"
				HAVE_UTF8PROC=1
				printf '%s\n' "configure: utf8proc: built from source"
			} || printf '%s\n' "configure: utf8proc: build failed (optional)"
		else
			printf '%s\n' "configure: utf8proc: not available (optional)"
		fi
	fi
	cat > "$utf8proc_cache" <<EOF
UTF8PROC_CFLAGS="$UTF8PROC_CFLAGS"
UTF8PROC_LIBS="$UTF8PROC_LIBS"
HAVE_UTF8PROC=$HAVE_UTF8PROC
EOF
fi

# ── libutil detection ─────────────────────────────────────────────────
# On Linux, openpty() lives in libutil (-lutil). On Darwin, it's in
# the default libraries. The pty command needs this at link time.

UTIL_FLAGS=""
case $HOSTTYPE in
linux.*) UTIL_FLAGS="-lutil" ;;
esac

# ── iffe helper ───────────────────────────────────────────────────────
# Install the iffe script so we can use it for feature detection.
# iffe is the "if feature exists" probe tool from the AST project.

mkdir -p "$BUILDDIR/bin"
cp src/cmd/INIT/iffe.sh "$BUILDDIR/bin/iffe"
chmod +x "$BUILDDIR/bin/iffe"

_run_iffe_uncached()
{
	local workdir=$1 input=$2
	shift 2

	mkdir -p "$workdir/FEATURE"

	# Separate compiler/linker flags from script args
	local iffe_flags="" script_args=""
	while [ $# -gt 0 ]; do
		case $1 in
		-[IlL]*) iffe_flags="$iffe_flags $1" ;;
		*)       script_args="$script_args $1" ;;
		esac
		shift
	done

	# iffe must run from the workdir so FEATURE/ output lands there.
	# -X ast -X std: exclude ast/ and std/ dirs from include search
	# (prevents finding libast wrapper headers before they're generated).
	# ref -I$INCDIR: make generated headers findable.
	# DEFPATH: iffe needs this for system utility lookup. Normally
	# set via getconf(1), but getconf may not be available (e.g. Nix sandbox).
	: "${DEFPATH:=$(getconf PATH 2>/dev/null || printf '%s' '/usr/bin:/bin')}"
	export DEFPATH
	(
		cd "$workdir"
		PATH="$BUILDDIR_ABS/bin:$PATH" \
		sh "$BUILDDIR_ABS/bin/iffe" -v -X ast -X std \
			-c "$CC_PATH $CFLAGS" \
			ref -I"$PACKAGEROOT_ABS/$INCDIR" -I"$BUILDDIR_ABS/include" \
			$iffe_flags \
			: run "$input" $script_args
	) 2>/dev/null || true
}

# Probe tracking: background jobs can't update shell variables,
# so we log cache hits/misses to a file and count at the end.
_iffe_log=$BUILDDIR_ABS/.iffe_log
: > "$_iffe_log"

run_iffe()
{
	# $1 = working directory, $2 = input features/name file, $3... = extra args
	local workdir=$1 input=$2

	# Derive the FEATURE output name from the input filename
	local featname=${input##*/}
	featname=${featname%.sh}
	featname=${featname%.c}
	local outfile=$workdir/FEATURE/$featname

	# Cache check: skip if output exists, is non-empty, and is newer
	# than both the input file and configure.sh itself
	if ! $FORCE && [ -f "$outfile" ] && [ -s "$outfile" ] \
	   && [ "$outfile" -nt "$input" ] \
	   && [ "$outfile" -nt "$CONFIGURE_SELF" ]; then
		printf '%s\n' cached >> "$_iffe_log"
		return 0
	fi

	printf '%s\n' ran >> "$_iffe_log"
	_run_iffe_uncached "$@"
}

# Copy a feature test result to its canonical header location.
# Creates an empty file if the source doesn't exist (some tests are optional).
copy_feature()
{
	if [ -f "$1" ] && [ -s "$1" ]; then
		cp -f "$1" "$2"
	else
		: > "$2"
	fi
}

# ── Standalone C probe ────────────────────────────────────────────────
# Compile and run a small C program, capturing stdout. Used for probes
# that the old build system ran against AST libraries but that don't
# actually need AST — the originals just used sfio for convenience.
#
# Optimization: Use temp directory with single trap instead of per-file cleanup.

probe_c()
{
	local _probe_dir=$BUILDDIR_ABS/.probe$$
	local src=$_probe_dir/probe.c
	local bin=$_probe_dir/probe
	
	mkdir -p "$_probe_dir"
	# Expand _probe_dir now (double quotes), not when trap fires (single quotes)
	trap "rm -rf '$_probe_dir'" EXIT
	
	cat > "$src"
	if $CC_PATH $CFLAGS \
		-I"$PACKAGEROOT_ABS/$INCDIR" -I"$BUILDDIR_ABS/include" \
		-o "$bin" "$src" "$@" 2>/dev/null
	then
		"$bin" 2>/dev/null
		local rc=$?
	else
		local rc=1
	fi
	
	# Clear trap to prevent referencing stale _probe_dir
	trap - EXIT
	return $rc
}

# ── Feature tests: libast ─────────────────────────────────────────────
# The ordering here matters: standards must run first, then common/lib,
# then map (depends on lib), then the rest.

run_libast_features()
{
	local srcdir=$PACKAGEROOT_ABS/src/lib/libast
	local workdir=$BUILDDIR_ABS/libast_work
	local feat=$workdir/FEATURE

	mkdir -p "$workdir/FEATURE"

	printf '%s\n' "configure: running libast feature tests ..."

	# Generate ast_release.h
	(
		if git_branch=$(git branch 2>/dev/null); then
			printf '%s\n' '/* generated by configure.sh */'
			case $git_branch in
			*\*\ [0-9]*.[0-9]*)
				if git diff-index --quiet HEAD 2>/dev/null; then
					printf '%s\n' '#ifndef _AST_release'
					printf '%s\n' '#    define _AST_release	1'
					printf '%s\n' '#endif'
				else
					printf '%s\n' '/* on release branch, but changes made */'
				fi
				;;
			*)
				printf '%s\n' '/* not on a release branch */'
				;;
			esac
		else
			printf '%s\n' '/* not in a git repo */'
			printf '%s\n' '#ifndef _AST_release'
			printf '%s\n' '#    define _AST_release	1'
			printf '%s\n' '#endif'
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

	printf '%s\n' "configure: libast feature tests done"
}

# Generate conf headers (conflim.h, conftab.h, conftab.c) and lc.h
run_libast_conf()
{
	local srcdir=$PACKAGEROOT_ABS/src/lib/libast
	local workdir=$BUILDDIR/libast_work
	local conftab=$srcdir/comp/conf.tab
	mkdir -p "$workdir"

	# Cache: skip if conftab.h exists and is newer than inputs
	if ! $FORCE && [ -f "$workdir/conftab.h" ] \
	   && [ "$workdir/conftab.h" -nt "$conftab" ] \
	   && [ "$workdir/conftab.h" -nt "$srcdir/comp/conf.sh" ] \
	   && [ "$workdir/conftab.h" -nt "$CONFIGURE_SELF" ]; then
		return 0
	fi

	# Create the conf script (prepends HOSTTYPE to comp/conf.sh)
	printf '%s\n' "HOSTTYPE='$HOSTTYPE'" > "$workdir/conf"
	cat "$srcdir/comp/conf.sh" >> "$workdir/conf"
	chmod +x "$workdir/conf"

	# Run conf to generate conflim.h, conftab.h, conftab.c
	(
		cd "$workdir"
		./conf -v "$srcdir/comp/conf.tab" \
			"$CC_PATH" $_optimize \
			$_nostrictaliasing 2>/dev/null
	) || true

	# Copy generated conf headers
	for f in conflim.h conftab.h conftab.c; do
		[ -f "$workdir/$f" ] && cp -f "$workdir/$f" "$INCDIR/../$f"
	done

	# Generate lc.h and lctab.c using lcgen
	if [ -f "$srcdir/port/lcgen.c" ]; then
		$CC_PATH $CFLAGS -o "$workdir/lcgen" "$srcdir/port/lcgen.c" 2>/dev/null || true
		if [ -x "$workdir/lcgen" ]; then
			"$workdir/lcgen" "$INCDIR/../lc.h" "$INCDIR/../lctab.c" \
				< "$srcdir/port/lc.tab" 2>/dev/null || true
		fi
	fi
}

# ── Feature tests: libcmd ─────────────────────────────────────────────

run_libcmd_features()
{
	local srcdir=$PACKAGEROOT_ABS/src/lib/libcmd
	local workdir=$BUILDDIR_ABS/libcmd_work

	mkdir -p "$workdir/FEATURE"

	printf '%s\n' "configure: running libcmd feature tests ..."
	run_iffe "$workdir" "$srcdir/features/symlink" &
	run_iffe "$workdir" "$srcdir/features/sockets" &
	run_iffe "$workdir" "$srcdir/features/ids" &
	run_iffe "$workdir" "$srcdir/features/utsname" &
	wait

	# Copy FEATURE results
	cp -f "$workdir/FEATURE"/* "$FEATDIR/" 2>/dev/null || true
}

# ── Feature tests: pty ─────────────────────────────────────────────────

run_pty_features()
{
	local srcdir=$PACKAGEROOT_ABS/src/cmd/builtin
	local workdir=$BUILDDIR_ABS/pty_work

	mkdir -p "$workdir/FEATURE"

	printf '%s\n' "configure: running pty feature tests ..."
	run_iffe "$workdir" "$srcdir/features/pty" -lutil &
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
	local srcdir=$PACKAGEROOT_ABS/src/cmd/ksh26
	local workdir=$BUILDDIR_ABS/ksh26_work

	mkdir -p "$workdir/FEATURE" "$workdir/probe_input"

	printf '%s\n' "configure: running ksh26 feature tests ..."

	# math is the slowest ksh26 probe — run it in parallel with the rest
	run_iffe "$workdir" "$srcdir/features/math.sh" -lm "$srcdir/data/math.tab" &
	run_iffe "$workdir" "$srcdir/features/time" &
	run_iffe "$workdir" "$srcdir/features/options" &
	run_iffe "$workdir" "$srcdir/features/fchdir" &
	run_iffe "$workdir" "$srcdir/features/locale" &
	run_iffe "$workdir" "$srcdir/features/cmds" &
	run_iffe "$workdir" "$srcdir/features/rlimits" &
	run_iffe "$workdir" "$srcdir/features/poll" &
	run_iffe "$workdir" "$srcdir/features/posix8" &
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
	local workdir=$1 srcdir=$2
	local feat=$workdir/FEATURE

	# Cache: externs input is embedded in configure.sh, so check
	# the FEATURE output against configure.sh itself
	if ! $FORCE && [ -f "$feat/externs" ] && [ -s "$feat/externs" ] \
	   && [ "$feat/externs" -nt "$CONFIGURE_SELF" ]; then
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
	printf '%s\n' '#define _arg_extrabytes	sizeof(char*)' >> "$feat/externs"
}

# SHOPT_GLOBCASEDET — can we detect filesystem case insensitivity?
# The original called AST's pathicase(), which uses pathconf(2).
probe_ksh26_options()
{
	local workdir=$1
	local feat=$workdir/FEATURE/options

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
	local workdir=$1
	local feat=$workdir/FEATURE/fchdir

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
	local workdir=$1
	local feat=$workdir/FEATURE/poll

	# Already probed?
	grep -q pipe_socketpair "$feat" 2>/dev/null && return

	# pipe_socketpair: can recv(MSG_PEEK) read from a socketpair fd?
	# This is an execute-only test (exit code matters, no stdout).
	local src=$BUILDDIR_ABS/probe_poll$$.c
	local bin=$BUILDDIR_ABS/probe_poll$$
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
	local outdir=$BUILDDIR/ksh26_work
	mkdir -p "$outdir"

	local git_commit=""
	git_commit=$(git rev-parse --short=8 HEAD 2>/dev/null) || true
	case $git_commit in
	[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f])
		printf '%s\n' '/* generated by configure.sh */'
		git update-index --really-refresh >/dev/null 2>&1 || true
		if ! git diff-index --quiet HEAD 2>/dev/null; then
			git_commit=$git_commit/MOD
		fi
		printf '%s\n' "#define git_commit   \"$git_commit\""
		;;
	*)
		printf '%s\n' '/* not in a git repo */'
		printf '%s\n' '#undef git_commit'
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
	local outdir=$BUILDDIR/ksh26_work
	mkdir -p "$outdir"

	# Define the SHOPT function that processes each option
	writedef()
	{
		printf '%s\n' "${3:-#ifndef SHOPT_$1}"
		printf '%s\n' "#   define SHOPT_$1	$2"
		printf '%s\n' '#endif'
		printf '%s\n' ''
	}

	SHOPT()
	{
		local n=${1%%=*}
		local v=${1#*=}
		case $1 in
		'MULTIBYTE=')
			writedef MULTIBYTE 1 '#if !defined(SHOPT_MULTIBYTE) && !AST_NOMULTIBYTE' ;;
		'DEVFD=')
			ls -d /dev/fd/9 9<&0 >/dev/null 2>&1 && writedef DEVFD 1 ;;
		'TEST_L=')
			local link=$BUILDDIR_ABS/link$$
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
		printf '%s\n' '/* Generated from ksh26/SHOPT.sh by configure.sh */'
		printf '%s\n' ''
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
	local srcdir=src/lib/libcmd
	local outdir=$BUILDDIR/libcmd_work
	mkdir -p "$outdir"

	# cmdext.h — extern function prototypes for b_* commands
	{
		printf '%s\n' '/*'
		printf '%s\n' ' * -lcmd extern function prototypes'
		printf '%s\n' ' */'
		printf '%s\n' ''
		sed -e '/^b_[a-z_][a-z_0-9]*(/!d' \
			-e 's/^b_//' \
			-e 's/(.*//' \
			-e 's/.*/extern int	b_&(int, char**, Shbltin_t*);/' \
			"$srcdir"/*.c | sort -u
	} > "$outdir/cmdext.h.new"

	# cmdlist.h — CMDLIST() macros
	{
		printf '%s\n' '/*'
		printf '%s\n' ' * -lcmd function list -- define your own CMDLIST()'
		printf '%s\n' ' */'
		printf '%s\n' ''
		sed -e '/^b_[a-z_][a-z_0-9]*(/!d' \
			-e 's/^b_//' \
			-e 's/(.*//' \
			-e 's/.*/CMDLIST(&)/' \
			"$srcdir"/*.c | sort -u
	} > "$outdir/cmdlist.h.new"

	# Install to include dir only if changed (avoids triggering recompilation)
	local changed=false
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
# Results are cached to avoid redundant find(1) calls (each runs twice: emit_ninja
# and configure_manifest).

_cached_libast_sources=""
_cached_libcmd_sources=""
_cached_ksh26_sources=""

collect_libast_sources()
{
	if [ -z "$_cached_libast_sources" ]; then
		_cached_libast_sources=$(find src/lib/libast -name '*.c' \
			-not -name 'lcgen.c' \
			-not -name 'astmath.c' \
			-not -path '*/features/*' \
			| sort)
	fi
	printf '%s\n' "$_cached_libast_sources"
}

collect_libcmd_sources()
{
	if [ -z "$_cached_libcmd_sources" ]; then
		_cached_libcmd_sources=$(for f in \
			basename cat cp cut dirname getconf ln mktemp mv stty \
			cmdinit lib \
		; do
			printf '%s\n' "src/lib/libcmd/$f.c"
		done)
	fi
	printf '%s\n' "$_cached_libcmd_sources"
}

collect_ksh26_sources()
{
	if [ -z "$_cached_ksh26_sources" ]; then
		_cached_ksh26_sources=$(find src/cmd/ksh26 -name '*.c' \
			-not -path '*/tests/*' \
			-not -path '*/features/*' \
			| sort)
	fi
	printf '%s\n' "$_cached_ksh26_sources"
}

# ── Emit build.ninja ──────────────────────────────────────────────────

emit_ninja()
{
	local ninja
	ninja=$(mktemp "$BUILDDIR/build.ninja.XXXXXX") || return 1
	trap 'rm -f "$ninja"' RETURN
	local cc=$CC_PATH
	local ar=$AR

	# Include paths are absolute so they work from samu's -C directory.
	# ast_std intercepts <stdio.h>, <wchar.h> etc. with AST's wrappers
	# that handle the FILE → Sfio_t redirection.
	local ast_inc="-I$PACKAGEROOT_ABS/$INCDIR"
	local ast_std="-I$PACKAGEROOT_ABS/$BUILDDIR/include/std"
	local ast_inc_parent="-I$PACKAGEROOT_ABS/$BUILDDIR/include"
	local src_abs=$PACKAGEROOT_ABS

	printf '%s\n' "configure: generating $ninja ..."

	# ── Syscall optimization: single open/write/close ─────────────────────
	# All ninja content is generated inside this grouped command.
	# Reduces ~1500 syscalls to ~4 (was: open/seek/write/close per append).
	{
		cat <<NINJA
# build.ninja — generated by configure.sh
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
  command = $cc $CFLAGS $LDFLAGS \$ldflags -o \$out \$in \$libs
  description = LINK \$out

NINJA

		# ── libast ──────────────────────────────────────────────────────

		local libast_objs=""
		local libast_cflags="-D_BLD_ast -DHOSTTYPE='\"$HOSTTYPE\"' $ast_inc $ast_inc_parent"

		# Include libast subdirectories — source files cross-reference
		# private headers across subdirectories (e.g. tm/tmlocale.c includes
		# port/lclib.h). Exclude features/ and man/ — features/ would shadow
		# the generated FEATURE/ headers on case-insensitive filesystems.
		local libast_inc=""
		local d
		for d in $src_abs/src/lib/libast/*/; do
			case $d in
			*/features/|*/man/) continue ;;
			esac
			libast_inc="$libast_inc -I$d"
		done
		libast_inc="$libast_inc -I$src_abs/src/lib/libast"

		while IFS= read -r src; do
			local base=${src##*/}
			local obj=obj/libast/${base%.c}.o

			printf '\nbuild %s: cc %s/%s\n  extra_cflags = %s %s\n' \
				"$obj" "$src_abs" "$src" "$libast_cflags" "$libast_inc"
			libast_objs="$libast_objs $obj"
		done <<EOF
$(collect_libast_sources)
EOF

		# Generated source files (conftab.c, lctab.c)
		if [ -f "$BUILDDIR/include/conftab.c" ]; then
			local obj=obj/libast/conftab.o
			printf '\nbuild %s: cc %s/include/conftab.c\n  extra_cflags = %s %s\n' \
				"$obj" "$BUILDDIR_ABS" "$libast_cflags" "$libast_inc"
			libast_objs="$libast_objs $obj"
		fi

		if [ -f "$BUILDDIR/include/lctab.c" ]; then
			local obj=obj/libast/lctab.o
			printf '\nbuild %s: cc %s/include/lctab.c\n  extra_cflags = %s %s\n' \
				"$obj" "$BUILDDIR_ABS" "$libast_cflags" "$libast_inc"
			libast_objs="$libast_objs $obj"
		fi

		printf '\nbuild lib/libast.a: ar%s\n' "$libast_objs"

		# ── libcmd ──────────────────────────────────────────────────────

		local libcmd_objs=""
		local libcmd_cflags="-D_BLD_cmd -DERROR_CATALOG='\"libcmd\"' -DHOSTTYPE='\"$HOSTTYPE\"' -I$src_abs/src/lib/libcmd -I$BUILDDIR_ABS/libcmd_work $ast_std $ast_inc $ast_inc_parent"

		while IFS= read -r src; do
			local base=${src##*/}
			local obj=obj/libcmd/${base%.c}.o
			printf '\nbuild %s: cc %s/%s\n  extra_cflags = %s\n' \
				"$obj" "$src_abs" "$src" "$libcmd_cflags"
			libcmd_objs="$libcmd_objs $obj"
		done <<EOF
$(collect_libcmd_sources)
EOF

		printf '\nbuild lib/libcmd.a: ar%s\n' "$libcmd_objs"

		# ── ksh26 (libshell + binaries) ────────────────────────────────

		local ksh_objs=""
		local ksh_srcdir=src/cmd/ksh26
		local ksh_cflags="-D_BLD_ksh -DSH_DICT='\"libshell\"' -D_API_ast=20100309"
		ksh_cflags="$ksh_cflags -I$BUILDDIR_ABS/ksh26_work"
		ksh_cflags="$ksh_cflags -I$src_abs/$ksh_srcdir"
		ksh_cflags="$ksh_cflags -I$src_abs/$ksh_srcdir/include"
		ksh_cflags="$ksh_cflags $ast_std $ast_inc $ast_inc_parent"

		while IFS= read -r src; do
			local base=${src##*/}
			local obj=obj/ksh26/${base%.c}.o
			local extra=""

			case $base in
			pmain.c|shcomp.c) continue ;;
			esac

			case $src in
			*/data/builtins.c|*/bltins/typeset.c|*/sh/path.c)
				extra="-DSHOPT_DYNAMIC=0" ;;
			esac

			printf '\nbuild %s: cc %s/%s\n  extra_cflags = %s %s\n' \
				"$obj" "$src_abs" "$src" "$ksh_cflags" "$extra"
			ksh_objs="$ksh_objs $obj"
		done <<EOF
$(collect_ksh26_sources)
EOF

		# pty needs: its own FEATURE/pty, libcmd headers, AST headers
		local pty_cflags="-DERROR_CATALOG='\"builtin\"' -I$BUILDDIR_ABS/pty_work -I$src_abs/src/lib/libcmd $ast_std $ast_inc $ast_inc_parent"

		printf '\nbuild lib/libshell.a: ar%s\n' "$ksh_objs"

		cat <<NINJA

build obj/ksh26/pmain.o: cc $src_abs/$ksh_srcdir/sh/pmain.c
  extra_cflags = $ksh_cflags

build obj/ksh26/shcomp.o: cc $src_abs/$ksh_srcdir/sh/shcomp.c
  extra_cflags = $ksh_cflags

build bin/ksh: link obj/ksh26/pmain.o | lib/libshell.a lib/libcmd.a lib/libast.a
  libs = -Llib -lshell -lcmd -last -lm $ICONV_FLAGS
  ldflags =

build bin/shcomp: link obj/ksh26/shcomp.o | lib/libshell.a lib/libcmd.a lib/libast.a
  libs = -Llib -lshell -lcmd -last -lm $ICONV_FLAGS
  ldflags =

# ── pty (test utility) ────────────────────────────────────
build obj/pty/pty.o: cc $src_abs/src/cmd/builtin/pty.c
  extra_cflags = $pty_cflags

build obj/pty/pty_main.o: cc $src_abs/src/cmd/builtin/pty_main.c
  extra_cflags = $pty_cflags

build bin/pty: link obj/pty/pty_main.o obj/pty/pty.o | lib/libcmd.a lib/libast.a
  libs = -Llib -lcmd -last -lm $ICONV_FLAGS $UTIL_FLAGS
  ldflags =

default bin/ksh bin/shcomp bin/pty
NINJA

		# ── Test targets ──────────────────────────────────────────

		local test_runner=$BUILDDIR_ABS/run-test.sh
		local tests_dir=$src_abs/tests/shell

		cat <<NINJA

# ── Tests ──────────────────────────────────────────────────
# Each test runs in C and C.UTF-8 locales in parallel.
# samu test    — run all tests
# samu test/basic.C.stamp — run one test

rule test
  command = \$wrapper sh $test_runner \$in \$mode \$out
  description = TEST \$desc

rule test_serial
  command = \$wrapper sh $test_runner \$in \$mode \$out
  description = TEST \$desc
  pool = serial

pool serial
  depth = 1

NINJA

		local all_stamps=""
		local timesensitive="builtins io options sigchld signal subshell"

		for test_sh in "$tests_dir"/*.sh; do
			[ -f "$test_sh" ] || continue
			local name=${test_sh##*/}
			name=${name%.sh}

			# Time-sensitive tests use the serial rule
			local rule="test"
			case " $timesensitive " in
			*" $name "*) rule="test_serial" ;;
			esac

			# Extra build dependencies and wrapper for specific tests
			local extra_deps="" test_wrapper=""
			case "$name" in
			pty) extra_deps=" bin/pty"; test_wrapper="unbuffer" ;;
			esac

			# C locale test
			printf '\nbuild test/%s.C.stamp: %s %s | bin/ksh bin/shcomp%s run-test.sh test-env.sh\n  mode = C\n  desc = %s (C)\n  wrapper = %s\n' \
				"$name" "$rule" "$test_sh" "$extra_deps" "$name" "$test_wrapper"
			all_stamps="$all_stamps test/${name}.C.stamp"

			# C.UTF-8 locale test
			printf '\nbuild test/%s.C.UTF-8.stamp: %s %s | bin/ksh bin/shcomp%s run-test.sh test-env.sh\n  mode = C.UTF-8\n  desc = %s (C.UTF-8)\n  wrapper = %s\n' \
				"$name" "$rule" "$test_sh" "$extra_deps" "$name" "$test_wrapper"
			all_stamps="$all_stamps test/${name}.C.UTF-8.stamp"
		done

		# Phony target to run all tests
		printf '\nbuild test: phony%s\n' "$all_stamps"

	} > "$ninja"  # ← Single write operation for entire ninja file

	local stmts
	stmts=$(grep -c '^build ' "$ninja")
	local final=$BUILDDIR/build.ninja
	if cmp -s "$ninja" "$final" 2>/dev/null; then
		rm -f "$ninja"
		printf '%s\n' "configure: build.ninja unchanged ($stmts build statements)"
	else
		mv -f "$ninja" "$final"
		printf '%s\n' "configure: wrote $final ($stmts build statements)"
	fi
}

# ── Generate test infrastructure ──────────────────────────────────────
# Emit a test-env.sh (SHOPT_* exports) and run-test.sh (single-test
# runner) so that ninja can run tests in parallel.

generate_test_env()
{
	local outdir=$BUILDDIR
	local shopt_h=$outdir/ksh26_work/shopt.h

	{
		printf '%s\n' '# test-env.sh — generated by configure.sh'
		printf '%s\n' '# Source this to get SHOPT_* environment variables.'
		printf '%s\n' ''

		# Feed SHOPT.sh through a subshell to capture the exports
		(
			SHOPT()
			{
				local n=${1%%=*}
				local v=${1#*=}
				case $1 in
				*=?*) printf '%s\n' "export SHOPT_$n=$v" ;;
				esac
			}
			. "$PACKAGEROOT/src/cmd/ksh26/SHOPT.sh"
		)

		# Override with probed values from shopt.h
		# Names already start with SHOPT_ so just prefix 'export '
		if [ -f "$shopt_h" ]; then
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
	local outdir=$BUILDDIR
	local runner=$outdir/run-test.sh

	# Use dash for the test runner — it's a known-good POSIX shell
	# that doesn't depend on the ksh we're actively developing.
	# Falls back to /bin/sh if dash isn't on PATH.
	local runner_sh
	runner_sh=$(command -v dash 2>/dev/null || echo /bin/sh)

	# Paths are determined at runtime for Nix sandbox compatibility.
	# In local dev, these resolve to the build directory.
	# In Nix builds, these resolve to $out or the build directory.
	# Syscall optimization: single write (was: 4 separate open/write/close).
	{
		printf '%s\n' "#!$runner_sh"
		printf '%s\n' '# Runtime path resolution (supports Nix sandbox and local dev)'
		printf '%s\n' ': "${PACKAGEROOT:=$(cd "$(dirname "$0")/../.." && pwd)}"'
		printf '%s\n' ': "${BUILDDIR:=$PACKAGEROOT/build/'"$HOSTTYPE"'}"'
		cat <<'RUNNER'

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

# Per-test temp directory (cd -P resolves symlinks so $tmp == $PWD in ksh)
# This MUST be created before sourcing context files (fixtures.sh needs it)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ksh26.test.${test_name}.${mode}.XXXXXX") || exit 1
tmp=$(cd -P "$tmp" && pwd) || exit 1
export HOME="$tmp" tmp
trap 'rm -rf "$tmp"' EXIT

# ── Context Adaptations ─────────────────────────────────────
# Source context files for test environment setup
# Per CLAUDE.md "Immutable Test Sanctity": framework adapts to test, not vice versa

# Base context (always sourced)
. "${PACKAGEROOT}/tests/contexts/default.sh"

# Test-specific contexts (sourced if they exist)
_context_dir="${PACKAGEROOT}/tests/contexts"
for _ctx in tty fixtures timing; do
	if [ -f "$_context_dir/$_ctx.sh" ]; then
		# Source context in a subshell to check if it applies to this test
		# Context files check $test_name and set up environment accordingly
		. "$_context_dir/$_ctx.sh"
	fi
done

# SHOPT_* variables from test-env.sh
. "${0%/*}/test-env.sh"

mkdir -p "$(dirname "$log")"

# ── Memory limit ──────────────────────────────────────────────
# Prevent runaway allocations from killing the machine.
# Linux: ulimit -v works (kernel-enforced). Darwin: ulimit -v is
# a no-op (Apple removed RLIMIT_AS), so we poll RSS instead.
_memlimit_kb=524288  # 512 MiB
_use_rss_monitor=false
if ! ulimit -v "$_memlimit_kb" 2>/dev/null; then
	case $(uname -s) in
	Darwin) _use_rss_monitor=true ;;
	esac
fi

# RSS monitor: poll child process RSS, kill on excess
_rss_monitor() {
	_parent=$1 _max=$2
	while kill -0 "$_parent" 2>/dev/null; do
		sleep 1
		for _child in $(pgrep -P "$_parent" 2>/dev/null); do
			_rss=$(ps -o rss= -p "$_child" 2>/dev/null) || continue
			if [ "${_rss:-0}" -gt "$_max" ]; then
				kill -KILL "$_child" 2>/dev/null
				return
			fi
		done
	done
}

# ── Run ──────────────────────────────────────────────────────
cd "$tmp" || exit 1

rc=0
# Per-test timeout (60s). GNU timeout (from coreutils) handles
# process groups and signal semantics correctly — ksh catches
# SIGTERM internally, so naive kill-based approaches misclassify
# timeouts. The nix devshell guarantees coreutils; non-nix users
# get _nix-warn and a no-timeout fallback.
if command -v timeout >/dev/null 2>&1; then
	if $_use_rss_monitor; then
		# Darwin: run timeout in background so we can monitor RSS
		timeout 60 "$SHELL" "$test_file" >"$log" 2>&1 &
		_tpid=$!
		_rss_monitor "$_tpid" "$_memlimit_kb" &
		_mpid=$!
		wait "$_tpid" 2>/dev/null || rc=$?
		kill "$_mpid" 2>/dev/null; wait "$_mpid" 2>/dev/null
	else
		timeout 60 "$SHELL" "$test_file" >"$log" 2>&1 || rc=$?
	fi
else
	"$SHELL" "$test_file" >"$log" 2>&1 || rc=$?
fi

# ── Classify and record ───────────────────────────────────────
summary="${BUILDDIR}/test/summary.log"
desc="${test_name}.${mode}"

if [ "$rc" -eq 0 ]; then
	if [ -f "$tmp/.skip_reason" ]; then
		reason=$(cat "$tmp/.skip_reason")
		printf 'ok - %s # SKIP %s\n' "$desc" "$reason" >> "$summary"
	else
		printf 'ok - %s\n' "$desc" >> "$summary"
	fi
	touch "$stamp"
	rm -f "$log"
	exit 0
fi

case $rc in
124)  detail="timeout" ;;
139)  detail="SEGV signal 11" ;;
134)  detail="ABRT signal 6" ;;
137)  detail="KILL signal 9" ;;
*)    nerr=$(grep -c 'FAIL:' "$log" 2>/dev/null) || nerr=0
      if [ "$nerr" -gt 0 ]; then
          detail="$nerr errors"
      else
          detail="exit $rc"
      fi
      ;;
esac

printf 'not ok - %s # %s\n' "$desc" "$detail" >> "$summary"
cat "$log" >&2
rm -f "$stamp"
exit "$rc"
RUNNER
	} > "$runner"  # ← Single write for entire runner script
	chmod +x "$runner"
}

# ── Install public headers ────────────────────────────────────────────
# Copy source headers into the build include directory so all libraries
# and ksh26 can find them via -I$INCDIR.

install_headers()
{
	printf '%s\n' "configure: installing public headers ..."

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
			[ -f "$f" ] && cp -f "$f" "$INCDIR/"
		done
	done

	# libcmd public headers
	cp -f src/lib/libcmd/cmd.h "$INCDIR/" 2>/dev/null || true

	# ksh26 public headers
	for h in nval shell history sh_io sh_strbuf; do
		cp -f "src/cmd/ksh26/include/$h.h" "$INCDIR/" 2>/dev/null || true
	done

	# libcmd needs shcmd.h from libast
	# (already in libast/include/)
}

# ── Main ──────────────────────────────────────────────────────────────

printf '%s\n' "configure: starting configuration for $HOSTTYPE ..."

# Phase 0: Install public headers (needed by feature tests and compilation)
install_headers

# Phase 1: Feature detection
run_libast_features

# libcmd, ksh26, pty are independent of each other
# (they only depend on libast feature headers being installed)
run_libcmd_features &
run_ksh26_features &
run_pty_features &
wait

{
	# Optimization: Single-pass count instead of two grep -c calls
	_iffe_cached=0
	_iffe_ran=0
	while read -r _line; do
		case $_line in
			cached) _iffe_cached=$((_iffe_cached + 1)) ;;
			ran) _iffe_ran=$((_iffe_ran + 1)) ;;
		esac
	done < "$_iffe_log" 2>/dev/null
	if [ "$_iffe_cached" -gt 0 ]; then
		printf '%s\n' "configure: feature probes: $_iffe_ran ran, $_iffe_cached cached"
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

# Phase 5: Write configure manifest
# Lists all inputs that should trigger a reconfigure when changed.
# The justfile compares this against the current state to detect
# when build.ninja is stale (new source files, changed features, etc.)
{
	# configure.sh itself
	printf '%s\n' "configure.sh"
	# Feature input files
	find src/lib/libast/features src/lib/libcmd/features \
		src/cmd/ksh26/features src/cmd/builtin/features \
		-type f 2>/dev/null | sort
	# Source file list (additions/deletions invalidate build.ninja)
	collect_libast_sources | sort
	collect_libcmd_sources | sort
	collect_ksh26_sources | sort
	# Test files (additions/deletions change test stamp count)
	find tests/shell -name '*.sh' 2>/dev/null | sort
	# SHOPT config (affects test-env.sh)
	printf '%s\n' "src/cmd/ksh26/SHOPT.sh"
} > "$BUILDDIR/.configure_manifest"

printf '%s\n' "configure: done"

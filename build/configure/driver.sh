#
# driver.sh — probe driver + batch helpers + orchestration
#
# Depends: modernish (safe, harden, var/local, mktemp, extern)
# Provides: parse_options, detect_hosttype, setup_paths, gate_c23,
#           check_cache, setup_dirs, write_cache_key, write_manifest,
#           choose, trylibs, hdr, lib, mem, typ, dat, sys,
#           try_variants, sysdep, probe_compile, probe_link,
#           probe_execute, probe_output, atomic_write,
#           run_probes, run_generators, run_emitters

# ── Options + environment ────────────────────────────────────────

parse_options()
{
	opt_force=0
	opt_debug=0
	opt_asan=0
	_host_triple=""
	_sysdep_overrides=""
	for arg do
		case $arg in
		--force)	opt_force=1 ;;
		--debug)	opt_debug=1 ;;
		--asan)		opt_asan=1 ;;
		--host=*)	_host_triple="${arg#--host=}" ;;
		--with-sysdep-*=*)
			_key=${arg#--with-sysdep-}
			_val=${_key#*=}
			_key=${_key%%=*}
			# Newline-anchored entries prevent substring collision
			_sysdep_overrides="${_sysdep_overrides}
|${_key}: ${_val}"
			;;
		*)	die "unknown option: $arg" ;;
		esac
	done
}

# Map a GNU target triple to our HOSTTYPE format (os.arch-bits).
triple_to_hosttype()
{
	case "$1" in
	aarch64-linux*|aarch64-*-linux*)	put "linux.aarch64-64" ;;
	x86_64-linux*|x86_64-*-linux*)		put "linux.x86_64-64" ;;
	arm-linux*|arm-*-linux*)		put "linux.arm-32" ;;
	aarch64-*darwin*|arm64-*darwin*)		put "darwin.arm64-64" ;;
	x86_64-*darwin*)			put "darwin.x86_64-64" ;;
	*)	die "unknown host triple: $1" ;;
	esac
}

_CROSS_COMPILE=0

detect_hosttype()
{
	if not str empty "$_host_triple"; then
		HOSTTYPE=$(triple_to_hosttype "$_host_triple")
		_CROSS_COMPILE=1
	else
		LOCAL _os _arch; BEGIN
			_os=$(uname -s | tr 'A-Z' 'a-z')
			_arch=$(uname -m)
			case $_arch in
			arm64)		_arch=arm64-64 ;;
			x86_64)		_arch=x86_64-64 ;;
			aarch64)	_arch=aarch64-64 ;;
			esac
			HOSTTYPE="${_os}.${_arch}"
		END
	fi
}

setup_paths()
{
	CC=${CC:-cc}
	CFLAGS_BASE="-std=c23 -Os -fno-strict-aliasing"
	LDFLAGS_BASE=""

	_variant=""
	if test "$opt_debug" -eq 1; then
		_variant="-debug"
		CFLAGS_BASE="-std=c23 -g -O0 -fno-strict-aliasing -D_BLD_DEBUG"
	fi
	if test "$opt_asan" -eq 1; then
		_variant="${_variant}-asan"
		CFLAGS_BASE="${CFLAGS_BASE} -fsanitize=address,undefined -fno-omit-frame-pointer"
		LDFLAGS_BASE="-fsanitize=address,undefined"
	fi

	BUILDDIR="$PACKAGEROOT/build/${HOSTTYPE}${_variant}"
	OBJDIR="$BUILDDIR/obj"
	LIBDIR="$BUILDDIR/lib"
	BINDIR="$BUILDDIR/bin"
	LOGDIR="$BUILDDIR/log"
	FEATDIR="$BUILDDIR/feat"
	SYSDEPS="$BUILDDIR/sysdeps"
	PROBE_DEFS="$BUILDDIR/probe_defs.h"

	SRC="$PACKAGEROOT/src"
	LIBAST_SRC="$SRC/lib/libast"
	LIBCMD_SRC="$SRC/lib/libcmd"
	KSH_SRC="$SRC/cmd/ksh26"
	INIT_SRC="$SRC/cmd/INIT"
	PTY_SRC="$SRC/cmd/builtin"
	PROBES_DIR="$PACKAGEROOT/build/probes"
	PROBES_DATA="$PROBES_DIR/data"

	ICONV_LIB=""
	ICONV_CFLAGS=""
	LIBS=""
	SAMU="$BINDIR/samu"

	# Standard libast include paths — used by any probe that needs
	# prior FEATURE results or libast headers at compile time.
	# If libast's include structure changes, update this one variable.
	LIBAST_INCS="-I$FEATDIR/libast -I$LIBAST_SRC -I$LIBAST_SRC/comp -I$LIBAST_SRC/include"
}

gate_c23()
{
	LOCAL _dir _src _out; BEGIN
		mktemp -dsC; _dir=$REPLY
		_src="${_dir}/gate.c"
		_out="${_dir}/gate"
		put '#if defined(__clang__)
#  if __clang_major__ < 18
#    error "ksh26 requires Clang 18+ for C23 support"
#  endif
#elif defined(__GNUC__)
#  if __GNUC__ < 14
#    error "ksh26 requires GCC 14+ for C23 support"
#  endif
#else
#  error "ksh26 requires GCC 14+ or Clang 18+"
#endif
int main(void) { return 0; }
' >|"$_src"
		if ! "$CC" $CFLAGS_BASE -o "$_out" "$_src" 2>/dev/null; then
			die "C23 compiler required (GCC 14+ or Clang 18+)" \
				"CC=$CC" \
				"$("$CC" --version 2>/dev/null | head -1)"
		fi
	END
}

check_cache()
{
	LOCAL _cache_key _cc_version _self_mtime _shopt_mtime _current_key _old_key; BEGIN
		_cache_key="$BUILDDIR/.configure_cache_key"
		_cc_version=$("$CC" --version 2>/dev/null | head -1) || _cc_version=""
		_self_mtime=$(stat -f '%m' "$PACKAGEROOT/configure.sh" 2>/dev/null \
			|| stat -c '%Y' "$PACKAGEROOT/configure.sh" 2>/dev/null) || _self_mtime=0
		_shopt_mtime=$(stat -f '%m' "$KSH_SRC/SHOPT.sh" 2>/dev/null \
			|| stat -c '%Y' "$KSH_SRC/SHOPT.sh" 2>/dev/null) || _shopt_mtime=0
		_current_key="CC=$(extern -v "$CC" 2>/dev/null || put "$CC") VER=$_cc_version CFLAGS=$CFLAGS_BASE LDFLAGS=$LDFLAGS_BASE SELF=$_self_mtime SHOPT=$_shopt_mtime"
		if ! let "opt_force" && test -f "$_cache_key"; then
			_old_key=$(cat "$_cache_key")
			if str eq "$_old_key" "$_current_key" && test -f "$BUILDDIR/build.ninja"; then
				return 0
			fi
		fi
		_CURRENT_CACHE_KEY=$_current_key
		return 1
	END
}

setup_dirs()
{
	mkdir -p "$OBJDIR/libast" "$OBJDIR/libcmd" "$OBJDIR/ksh26" \
		"$LIBDIR" "$BINDIR" "$LOGDIR" \
		"$FEATDIR/libast/ast" "$FEATDIR/libast/std" \
		"$FEATDIR/libcmd" "$FEATDIR/ksh26" \
		"$FEATDIR/pty" "$BUILDDIR/test" \
		|| die "failed to create build directories"
	# Clean prior FEATURE output and header copies.
	# Probes regenerate everything; stale headers cause false positives.
	rm -rf "$FEATDIR/libast/FEATURE" "$FEATDIR/ksh26/FEATURE" \
		"$FEATDIR/libcmd/FEATURE" "$FEATDIR/pty/FEATURE"
	rm -f "$FEATDIR/libast"/ast_*.h "$FEATDIR/libast"/sig.h \
		"$FEATDIR/libast"/tv.h "$FEATDIR/libast"/tmx.h \
		"$FEATDIR/libast"/align.h "$FEATDIR/libast"/cmdext.h \
		"$FEATDIR/libast"/cmdlist.h "$FEATDIR/libast"/ast_release.h
	mkdir -p "$FEATDIR/libast/FEATURE" "$FEATDIR/ksh26/FEATURE" \
		"$FEATDIR/libcmd/FEATURE" "$FEATDIR/pty/FEATURE"
	# Symlink libast source dirs into FEATDIR so -I$FEATDIR/libast
	# can find comp/, include/, std/, port/, features/.
	for _d in comp include std port features; do
		[ -L "$FEATDIR/libast/$_d" ] || \
			ln -sf "$LIBAST_SRC/$_d" "$FEATDIR/libast/$_d"
	done
	>|"$SYSDEPS"
	putln "/* generated from sysdeps by configure.sh */" >|"$PROBE_DEFS"
}

write_cache_key()
{
	put "$_CURRENT_CACHE_KEY" >|"$BUILDDIR/.configure_cache_key"
}

# ── Library detection ────────────────────────────────────────────

detect_libs()
{
	LOCAL _src _out; BEGIN
		configure_log "library detection"

		# iconv: try libc → -liconv → pkg-config
		mktemp -dsC; _src=$REPLY
		put '#include <iconv.h>
int main(void) { iconv_open("",""); return 0; }
' >|"$_src/iconv.c"
		if "$CC" $CFLAGS_BASE -o "$_src/iconv" "$_src/iconv.c" $LDFLAGS_BASE 2>/dev/null; then
			configure_log "iconv ... libc"
		elif "$CC" $CFLAGS_BASE -o "$_src/iconv" "$_src/iconv.c" -liconv $LDFLAGS_BASE 2>/dev/null; then
			ICONV_LIB="-liconv"
			configure_log "iconv ... -liconv"
		elif command -v pkg-config >/dev/null 2>&1 && pkg-config --exists iconv 2>/dev/null; then
			ICONV_CFLAGS=$(pkg-config --cflags iconv 2>/dev/null)
			ICONV_LIB=$(pkg-config --libs iconv 2>/dev/null)
			configure_log "iconv ... pkg-config ($ICONV_LIB)"
		else
			configure_log "iconv ... not found (i18n \$\"...\" will be non-functional)"
		fi

		# -lm — always needed for ksh arithmetic
		LIBS="$ICONV_LIB"
		put '#include <math.h>
int main(void) { return (int)sin(0.0); }
' >|"$_src/lm.c"
		if "$CC" $CFLAGS_BASE -o "$_src/lm" "$_src/lm.c" -lm $LDFLAGS_BASE 2>/dev/null; then
			LIBS="$LIBS -lm"
			configure_log "sin in -lm ... yes"
		fi

		# -lutil — test linkage only (openpty)
		put 'int openpty(int*,int*,char*,void*,void*);
volatile void *_p;
int main(void) { _p = (void*)openpty; return 0; }
' >|"$_src/lutil.c"
		if "$CC" $CFLAGS_BASE -o "$_src/lutil" "$_src/lutil.c" -lutil $LDFLAGS_BASE 2>/dev/null; then
			LIBS="$LIBS -lutil"
			configure_log "openpty in -lutil ... yes"
		else
			configure_log "openpty in -lutil ... no"
		fi
	END
}

# ── DEFPATH detection ────────────────────────────────────────────
# Replicates bin/package lines 1649-1720: construct a default PATH
# from directories where standard utilities actually exist. This is
# compiled into ksh via conftab.c and used for `command -p` and
# `getconf PATH`. On NixOS, /usr/bin doesn't exist — utilities are
# in /run/current-system/sw/bin or nix store paths.

detect_defpath()
{
	if [ -n "${DEFPATH:-}" ]; then
		configure_log "DEFPATH ... $DEFPATH (from environment)"
		export DEFPATH
		return 0
	fi
	# Try getconf PATH first (NixOS patches glibc to return correct paths)
	_sys_path=$(PATH="/run/current-system/sw/bin:/usr/bin:/bin:$PATH" getconf PATH 2>/dev/null) \
		|| _sys_path="/usr/bin:/bin:/usr/sbin:/sbin"
	# Build DEFPATH from directories that actually contain standard utilities
	DEFPATH=""
	_save_ifs="$IFS"; IFS=:
	for _d in $_sys_path $PATH; do
		IFS="$_save_ifs"
		case "$_d" in
		/*) ;;
		*) continue ;;
		esac
		# Must contain at least one standard utility
		[ -x "$_d/ls" ] || [ -x "$_d/cat" ] || [ -x "$_d/sh" ] || continue
		# Dedup
		case ":$DEFPATH:" in
		*":$_d:"*) continue ;;
		esac
		DEFPATH="${DEFPATH:+$DEFPATH:}$_d"
	done
	IFS="$_save_ifs"
	# NixOS fix: add default profile directory (upstream bin/package lines 1698-1720)
	if [ -e /etc/NIXOS ] && [ -d /nix/var/nix/profiles/default/bin ]; then
		case ":$DEFPATH:" in
		*":/nix/var/nix/profiles/default/bin:"*) ;;
		*) DEFPATH="${DEFPATH:+$DEFPATH:}/nix/var/nix/profiles/default/bin" ;;
		esac
	fi
	[ -z "$DEFPATH" ] && DEFPATH="/usr/bin:/bin"
	export DEFPATH
	configure_log "DEFPATH ... $DEFPATH"
}

# ── samu bootstrap ───────────────────────────────────────────────

bootstrap_samu()
{
	if test -x "$SAMU"; then
		return 0
	fi
	configure_log "bootstrapping samu"
	"$CC" $CFLAGS_BASE -o "$SAMU" "$INIT_SRC"/samu/*.c 2>&1 || \
		die "failed to compile samu"
	configure_log "samu ... ok"
}

bootstrap_setsid()
{
	_setsid="$BINDIR/setsid"
	if test -x "$_setsid"; then
		return 0
	fi
	# Portable setsid(2) wrapper for process group isolation.
	# Tests that broadcast signals (kill -s INT 0) need their own
	# session so signals don't escape to the test runner.
	cat >|"$BINDIR/setsid.c" <<-'SETSID'
	#include <unistd.h>
	int main(int argc, char **argv) {
		if (argc < 2) return 1;
		setsid();
		execvp(argv[1], argv + 1);
		return 127;
	}
	SETSID
	if "$CC" $CFLAGS_BASE -o "$_setsid" "$BINDIR/setsid.c" 2>/dev/null; then
		configure_log "setsid ... ok"
		rm -f "$BINDIR/setsid.c"
	else
		configure_log "setsid ... skipped (tests will run without process group isolation)"
		rm -f "$BINDIR/setsid.c"
	fi
}

write_manifest()
{
	{
		putln "$PACKAGEROOT/configure.sh"
		find "$PACKAGEROOT/src/lib/libast/features" \
			"$PACKAGEROOT/src/lib/libcmd/features" \
			"$PACKAGEROOT/src/cmd/ksh26/features" \
			"$PACKAGEROOT/src/cmd/builtin/features" \
			-type f 2>/dev/null | sort
		putln "$KSH_SRC/SHOPT.sh"
	} >|"$BUILDDIR/.configure_manifest"
}

# ── Atomic write ─────────────────────────────────────────────────

atomic_write()
{
	# Usage: { content } | atomic_write TARGET
	# Returns 0 if changed, 1 if unchanged.
	LOCAL _target _new; BEGIN
		_target=$1
		_new="${_target}.new"
		cat >|"$_new"
		if test -f "$_target" && cmp -s "$_new" "$_target"; then
			rm -f "$_new"
			return 1
		else
			mv -f "$_new" "$_target"
			return 0
		fi
	END
}

# ── Sysdeps recording ───────────────────────────────────────────

sysdep()
{
	# Usage: sysdep KEY VALUE
	# Appends KEY: VALUE to the sysdeps file.
	# Checks manual overrides first (newline+pipe anchored).
	LOCAL _key _val _ov; BEGIN
		_key=$1; _val=$2
		# Anchored lookup prevents substring collision
		# Entries stored as \n|KEY: VALUE
		case "$_sysdep_overrides" in
		*"
|${_key}: "*)
			_ov=${_sysdep_overrides#*"
|${_key}: "}
			_val=${_ov%%"
"*}
			;;
		esac
		putln "${_key}: ${_val}" >>"$SYSDEPS"
	END
}

# ── Probe primitives ────────────────────────────────────────────
# Following skalibs's choose c|cl|clr model.
# Each primitive reads C source from a file (not stdin).

_probe_tmpdir=":uninitialized:"
_PROBE_STD_INC=""		# set after tier 0: #include "/path/to/ast_standards.h"
_probe_out_file=""		# monolith compat: temp binary prefix
_PROBE_LOG=""			# monolith compat: compiler output log
_PROBE_STDERR=/dev/null		# stderr destination (set by run_one_probe per probe type)

probe_run()
{
	# Run a command with stderr directed to the current probe log.
	# Primitive probes: _PROBE_STDERR=/dev/null (silent, expected failures).
	# Delegate probes: _PROBE_STDERR=$LOGDIR/probe.log (logged for inspection).
	"$@" 2>>"$_PROBE_STDERR"
}

probe_init()
{
	mktemp -dsC; _probe_tmpdir=$REPLY
	_probe_out_file="${_probe_tmpdir}/mc"
	_PROBE_LOG="$LOGDIR/probe.log"
	: >|"$_PROBE_LOG"
}

_probe_guard()
{
	case $_probe_tmpdir in
	:uninitialized:)
		die "probe_init() not called before probe"
		;;
	esac
}

probe_compile()
{
	# Usage: probe_compile SRCFILE [extra_cflags]
	# Compile only (cc -c). Returns 0 on success.
	# -include probe_defs.h makes prior-tier results visible to C code.
	_probe_guard
	"$CC" $CFLAGS_BASE -include "$PROBE_DEFS" ${2:-} -c "$1" \
		-o "${_probe_tmpdir}/out.o" 2>/dev/null
}

probe_link()
{
	# Usage: probe_link SRCFILE [extra_flags]
	# Compile + link. Returns 0 on success.
	_probe_guard
	"$CC" $CFLAGS_BASE -include "$PROBE_DEFS" $LDFLAGS_BASE ${2:-} \
		-o "${_probe_tmpdir}/out" "$1" 2>/dev/null
}

probe_execute()
{
	# Usage: probe_execute SRCFILE [extra_flags]
	# Compile + link + run. Returns exit code of the program.
	# Cross-compilation: can't run, return failure.
	test "$_CROSS_COMPILE" -eq 1 && return 1
	probe_link "$1" "${2:-}" && "${_probe_tmpdir}/out" 2>/dev/null
}

probe_output()
{
	# Usage: probe_output SRCFILE [extra_flags]
	# Compile + link + run. Stdout from the program is passed through
	# to the caller (use $(...) or >> to capture).
	# Cross-compilation: can't run, return failure.
	# Returns: exit code of the program.
	test "$_CROSS_COMPILE" -eq 1 && return 1
	LOCAL _src _flags; BEGIN
		_src=$1; _flags=${2:-}
		probe_link "$_src" "$_flags" || return 1
		"${_probe_tmpdir}/out"
	END
}

# ── Native header path detection (nxt probe) ────────────────────

probe_nxt()
{
	# Usage: probe_nxt HEADER_BASENAME
	# Finds the native (system-provided) header path by running the
	# preprocessor and scanning # line markers. Returns a relative
	# path that bypasses the AST std/ wrappers, or empty if not found.
	LOCAL _hdr _src _result _path; BEGIN
		_hdr=$1
		_src="${_probe_tmpdir}/nxt_${_hdr}.c"
		putln "#include <${_hdr}.h>" >|"$_src"
		_result=""
		if "$CC" $CFLAGS_BASE -E "$_src" >|"${_probe_tmpdir}/nxt.i" 2>/dev/null; then
			_path=$(sed -n "s/^#[line ]*[0-9][0-9]* *\"\([^\"]*\/${_hdr}\.h\)\".*/\1/p" \
				"${_probe_tmpdir}/nxt.i" | \
				grep -v "$FEATDIR" | grep -v "$LIBAST_SRC" | head -1)
			if not str empty "$_path"; then
				# Try relative path first
				putln "#include <../include/${_hdr}.h>" >|"$_src"
				if "$CC" $CFLAGS_BASE -E "$_src" >/dev/null 2>/dev/null; then
					_result="../include/${_hdr}.h"
				else
					_result="$_path"
				fi
			fi
		fi
		put "$_result"
	END
}

# ── Compile-from-stdin variants (for batch helpers) ──────────────

_probe_stdin_compile()
{
	# Compile C source from stdin. Returns 0 on success.
	_probe_guard
	cat >|"${_probe_tmpdir}/stdin.c"
	"$CC" $CFLAGS_BASE -include "$PROBE_DEFS" ${1:-} \
		-c "${_probe_tmpdir}/stdin.c" \
		-o "${_probe_tmpdir}/stdin.o" 2>/dev/null
}

_probe_stdin_link()
{
	_probe_guard
	cat >|"${_probe_tmpdir}/stdin.c"
	"$CC" $CFLAGS_BASE -include "$PROBE_DEFS" $LDFLAGS_BASE ${1:-} \
		-o "${_probe_tmpdir}/stdin" "${_probe_tmpdir}/stdin.c" 2>/dev/null
}

# ── choose (skalibs pattern) ────────────────────────────────────

choose()
{
	# Usage: choose MODE NAME DESCRIPTION [extra_flags]
	# MODE: c (compile), cl (compile+link), clr (compile+link+run)
	# Looks for build/probes/try_NAME.c
	LOCAL _mode _name _desc _flags _src _result; BEGIN
		_mode=$1; _name=$2; _desc=$3; _flags=${4:-}
		_src="$PROBES_DIR/try_${_name}.c"
		if ! test -f "$_src"; then
			putln "  choose: missing probe file: $_src" >&2
			return 1
		fi
		_result=no
		case $_mode in
		c)	probe_compile "$_src" "$_flags" && _result=yes ;;
		cl)	probe_link "$_src" "$_flags" && _result=yes ;;
		clr)	probe_execute "$_src" "$_flags" && _result=yes ;;
		esac
		putln "  probe: $_desc ... $_result" >&2
		sysdep "$_name" "$_result"
	END
}

# ── trylibs (skalibs pattern) ───────────────────────────────────

trylibs()
{
	# Usage: trylibs NAME DESCRIPTION SRCFILE LIB1 [LIB2 ...]
	# Tries linking with each library in order. Records the first
	# that succeeds as NAME.lib in sysdeps.
	LOCAL _name _desc _src _found; BEGIN
		_name=$1; _desc=$2; _src=$3; shift 3
		_found=""
		for _lib do
			if probe_link "$_src" "$_lib"; then
				_found=$_lib
				break
			fi
		done
		if not str empty "$_found"; then
			putln "  probe: $_desc ... yes ($_found)" >&2
			sysdep "$_name" "yes"
			sysdep "${_name}_lib" "$_found"
		else
			putln "  probe: $_desc ... no" >&2
			sysdep "$_name" "no"
		fi
	END
}

# ── Batch helpers (iffe vocabulary as shell functions) ───────────
# These generate #define lines on stdout. Caller captures and
# writes to the appropriate FEATURE file.

hdr()
{
	# Usage: hdr NAME1 NAME2 ...
	# Tests #include <NAME.h>. Emits _hdr_NAME defines to stdout.
	# Names with slashes (e.g., arpa/inet) become _hdr_arpa_inet in defines.
	LOCAL _h _v _safe; BEGIN
		for _h do
			_v=0
			_probe_stdin_compile <<-EOF && _v=1
				#include <${_h}.h>
				int _probe_dummy;
			EOF
			_safe=$(putln "$_h" | tr '/' '_')
			putln "#define _hdr_${_safe}	${_v}"
			sysdep "hdr_${_safe}" "$( test "$_v" -eq 1 && put yes || put no )"
		done
	END
}

sys()
{
	# Usage: sys NAME1 NAME2 ...
	# Tests #include <sys/NAME.h>. Emits _sys_NAME defines.
	LOCAL _s _v; BEGIN
		for _s do
			_v=0
			_probe_stdin_compile <<-EOF && _v=1
				#include <sys/${_s}.h>
				int _probe_dummy;
			EOF
			putln "#define _sys_${_s}	${_v}"
			sysdep "sys_${_s}" "$( test "$_v" -eq 1 && put yes || put no )"
		done
	END
}

lib()
{
	# Usage: lib NAME1 NAME2 ... [-- LIBS]
	# Tests function linkage. Emits _lib_NAME defines.
	# Pass 1: split args into names and libs at the -- separator.
	# Pass 2: probe each name with the collected libs.
	LOCAL _f _v _libs _names _sep_seen; BEGIN
		_libs=""
		_names=""
		_sep_seen=0
		for _f do
			case $_f in
			--)	_sep_seen=1; continue ;;
			esac
			if test "$_sep_seen" -eq 1; then
				_libs="${_libs} ${_f}"
			else
				_names="${_names} ${_f}"
			fi
		done
		for _f in $_names; do
			_v=0
			_probe_stdin_link "$_libs" <<-EOF && _v=1
				extern int ${_f}();
				int main(void) { return ${_f}(); }
			EOF
			putln "#define _lib_${_f}	${_v}"
			sysdep "lib_${_f}" "$( test "$_v" -eq 1 && put yes || put no )"
		done
	END
}

mem()
{
	# Usage: mem [HEADER ...] STRUCT.MEMBER [STRUCT.MEMBER ...]
	# Headers (containing / or ending in .h) precede struct.member specs.
	# Tests struct member existence. Emits _mem_MEMBER_STRUCT defines.
	LOCAL _spec _struct _member _hdrs _hdr_inc _v; BEGIN
		_hdrs=""
		for _spec do
			case $_spec in
			*/*.h|*.h)
				# Header argument (sys/types.h, dirent.h, etc.)
				_hdrs="${_hdrs} ${_spec}"
				;;
			*.*)	# struct.member spec (dirent.d_fileno, tm.tm_zone, etc.)
				_struct=${_spec%%.*}
				_member=${_spec#*.}
				_v=0
				_hdr_inc=""
				for _h in $_hdrs; do
					_hdr_inc="${_hdr_inc}#include <${_h}>
"
				done
				_probe_stdin_compile <<-EOF && _v=1
					${_hdr_inc}struct ${_struct} _probe_s;
					int _probe_v = sizeof(_probe_s.${_member});
				EOF
				putln "#define _mem_${_member}_${_struct}	${_v}"
				sysdep "mem_${_member}_${_struct}" "$( test "$_v" -eq 1 && put yes || put no )"
				;;
			*)	# Bare name — treat as header without .h extension
				_hdrs="${_hdrs} ${_spec}"
				;;
			esac
		done
	END
}

typ()
{
	# Usage: typ TYPE [HEADER] ["= DEFAULT"]
	# Tests type existence. Emits _typ_TYPE define.
	LOCAL _type _v _default _hdr_inc; BEGIN
		_type=$1; shift
		_default=""
		_hdr_inc=""
		for _arg do
			case $_arg in
			"= "*)	_default=${_arg#= } ;;
			=*)	_default=${_arg#=} ;;
			*)	_hdr_inc="${_hdr_inc}#include <${_arg}>
" ;;
			esac
		done
		_v=0
		_probe_stdin_compile <<-EOF && _v=1
			${_hdr_inc}static ${_type} _probe_v;
			int _probe_n = sizeof(_probe_v);
		EOF
		putln "#define _typ_${_type}	${_v}"
		sysdep "typ_${_type}" "$( test "$_v" -eq 1 && put yes || put no )"
		if test "$_v" -eq 0 && not str empty "$_default"; then
			putln "#define ${_type}	${_default}"
		fi
	END
}

dat()
{
	# Usage: dat NAME1 NAME2 ...
	# Tests data symbol linkage. Emits _dat_NAME defines.
	LOCAL _d _v; BEGIN
		for _d do
			_v=0
			_probe_stdin_link <<-EOF && _v=1
				extern int ${_d};
				int main(void) { return (int)${_d}; }
			EOF
			putln "#define _dat_${_d}	${_v}"
			sysdep "dat_${_d}" "$( test "$_v" -eq 1 && put yes || put no )"
		done
	END
}

# ── try_variants (iffe group mechanism) ──────────────────────────

try_variants()
{
	# Usage: try_variants SRCFILE FLAG1 FLAG2 ...
	# Compile+run SRCFILE with each flag in order.
	# Stops at first success. Captures stdout.
	LOCAL _src _flag; BEGIN
		_src=$1; shift
		for _flag do
			if probe_output "$_src" "$_flag"; then
				return 0
			fi
		done
		return 1
	END
}

# ── Monolith-compatible probe wrappers ────────────────────────────
# These match the monolith's probe API behavior:
# - Read C source from stdin (heredocs)
# - $_PROBE_STD_INC provides the standards preamble (full-path include)
# - No -include probe_defs.h (monolith doesn't use it)
# - Temp files in $_probe_tmpdir
#
# Naming: _mc_* to avoid collision with the file-based probe_* functions.
# Translation: monolith's probe_compile → _mc_compile, etc.

_mc_compile()
{
	# Monolith's probe_compile: compile-only C from stdin.
	# Usage: _mc_compile [extra_flags] <<'EOF'
	_probe_guard
	cat >|"${_probe_tmpdir}/mc.c"
	"$CC" $CFLAGS_BASE ${1:-} -c \
		-o "${_probe_tmpdir}/mc.o" "${_probe_tmpdir}/mc.c" 2>/dev/null
}

_mc_link()
{
	# Monolith's probe_link: compile+link C from stdin.
	_probe_guard
	cat >|"${_probe_tmpdir}/mc.c"
	"$CC" $CFLAGS_BASE $LDFLAGS_BASE ${1:-} \
		-o "${_probe_tmpdir}/mc" "${_probe_tmpdir}/mc.c" 2>/dev/null
}

_mc_execute()
{
	# Monolith's probe_execute: compile+link+run C from stdin, check exit code.
	# Cross-compilation: consume stdin but can't run, return failure.
	_probe_guard
	cat >|"${_probe_tmpdir}/mc.c"
	test "$_CROSS_COMPILE" -eq 1 && return 1
	if "$CC" $CFLAGS_BASE $LDFLAGS_BASE ${1:-} \
		-o "${_probe_tmpdir}/mc" "${_probe_tmpdir}/mc.c" 2>/dev/null; then
		"${_probe_tmpdir}/mc" 2>/dev/null
	else
		return 1
	fi
}

_mc_output()
{
	# Monolith's probe_output: compile+link+run, capture stdout.
	# Returns captured output via printf (no trailing newline added).
	# Cross-compilation: consume stdin, return empty output.
	_probe_guard
	cat >|"${_probe_tmpdir}/mc.c"
	_mco_result=""
	if test "$_CROSS_COMPILE" -eq 0 && "$CC" $CFLAGS_BASE $LDFLAGS_BASE ${1:-} \
		-o "${_probe_tmpdir}/mc" "${_probe_tmpdir}/mc.c" 2>/dev/null; then
		_mco_result=$("${_probe_tmpdir}/mc" 2>/dev/null) || true
	fi
	printf '%s' "$_mco_result"
}

_mc_hdr()
{
	# Monolith's probe_hdr: test #include <name.h>.
	_mc_compile <<EOF
${_PROBE_STD_INC}
#include <$1>
int x;
EOF
}

_mc_sys()
{
	# Monolith's probe_sys: test #include <sys/name.h>.
	_mc_compile <<EOF
${_PROBE_STD_INC}
#include <sys/$1.h>
int x;
EOF
}

_mc_header_strict()
{
	# Monolith's probe_header_strict: strict header test (rejects #error in stderr).
	# Usage: _mc_header_strict HEADER [extra_cflags]
	_probe_guard
	cat >|"${_probe_tmpdir}/mc.c" <<EOF
${_PROBE_STD_INC}
#include <$1>
int x;
EOF
	"$CC" $CFLAGS_BASE ${2:-} -c \
		-o "${_probe_tmpdir}/mc.o" "${_probe_tmpdir}/mc.c" \
		2>"${_probe_tmpdir}/mc.hdr.e"
	_mchs_rc=$?
	if [ "$_mchs_rc" = 0 ] && [ -s "${_probe_tmpdir}/mc.hdr.e" ]; then
		if grep -q '#.*error' "${_probe_tmpdir}/mc.hdr.e" 2>/dev/null; then
			_mchs_rc=1
		fi
	fi
	rm -f "${_probe_tmpdir}/mc.o" "${_probe_tmpdir}/mc.hdr.e"
	return $_mchs_rc
}

_mc_lib()
{
	# Monolith's probe_lib: test function linkage.
	# Usage: _mc_lib FUNCNAME [LIBS]
	_mc_link "${2:-}" <<EOF
${_PROBE_STD_INC}
extern int ${1}();
volatile void *_p;
int main(void) { _p = (void*)${1}; return 0; }
EOF
}

_mc_mem()
{
	# Monolith's probe_mem: test struct member existence.
	# Usage: _mc_mem STRUCT FIELD HDR...
	_mcm_struct=$1; _mcm_field=$2; shift 2
	_mcm_inc="${_PROBE_STD_INC}"
	for _mcm_h do
		_mcm_inc="${_mcm_inc}
#include <${_mcm_h}>"
	done
	_mc_compile <<EOF
${_mcm_inc}
static struct ${_mcm_struct} _i;
int n = sizeof(_i.${_mcm_field});
EOF
}

_mc_typ()
{
	# Monolith's probe_typ: test type existence.
	# Usage: _mc_typ TYPE [HDR...]
	_mct_type=$1; shift
	_mct_inc="${_PROBE_STD_INC}
#include <sys/types.h>"
	for _mct_h do
		_mct_inc="${_mct_inc}
#include <${_mct_h}>"
	done
	_mc_compile <<EOF
${_mct_inc}
static ${_mct_type} _i;
int n = sizeof(_i);
EOF
}

_mc_dat()
{
	# Monolith's probe_dat: test data symbol linkage.
	# Usage: _mc_dat SYM [HDR]
	_mcd_inc="${_PROBE_STD_INC}"
	if [ $# -ge 2 ] && [ -n "$2" ]; then
		_mcd_inc="${_mcd_inc}
#include <${2}>"
	fi
	_mc_link <<EOF
${_mcd_inc}
extern int ${1};
int main(void) { return ${1}; }
EOF
}

_mc_nxt()
{
	# Monolith's probe_nxt: locate native header path via preprocessor.
	# Uses _PROBE_STD_INC in the C source (unlike the driver's probe_nxt).
	_probe_guard
	_mcn_hdr=$1
	_mcn_src="${_probe_tmpdir}/nxt_${_mcn_hdr}.c"
	echo "${_PROBE_STD_INC}
#include <${_mcn_hdr}.h>" >|"$_mcn_src"
	_mcn_result=""
	if "$CC" $CFLAGS_BASE -E "$_mcn_src" >|"${_probe_tmpdir}/nxt.i" 2>/dev/null; then
		_mcn_path=$(sed -n "s/^#[line ]*[0-9][0-9]* *\"\([^\"]*\/${_mcn_hdr}\.h\)\".*/\1/p" \
			"${_probe_tmpdir}/nxt.i" | \
			grep -v "$FEATDIR" | grep -v "$LIBAST_SRC" | head -1)
		if [ -n "$_mcn_path" ]; then
			echo "${_PROBE_STD_INC}
#include <../include/${_mcn_hdr}.h>" >|"$_mcn_src"
			if "$CC" $CFLAGS_BASE -E "$_mcn_src" >/dev/null 2>/dev/null; then
				_mcn_result="../include/${_mcn_hdr}.h"
			else
				_mcn_result="$_mcn_path"
			fi
		fi
	fi
	printf '%s' "$_mcn_result"
}

# ── Probe result propagation ────────────────────────────────────

regenerate_probe_defs()
{
	# Regenerate probe_defs.h from sysdeps.
	# Called after each tier completes.
	# Dedup: last entry wins (sort -t: -k1,1 -u takes the first,
	# but tac|sort -u|tac preserves last-wins semantics).
	{
		putln "/* generated from sysdeps by configure.sh */"
		tac "$SYSDEPS" | sort -t: -k1,1 -u | tac | while IFS=': ' read -r _key _val; do
			case $_val in
			yes)	putln "#define _${_key}	1" ;;
			no)	putln "#define _${_key}	0" ;;
			[0-9]*)	putln "#define _${_key}	${_val}" ;;
			esac
		done
	} >|"$PROBE_DEFS"
}

# ── Probe dispatch ───────────────────────────────────────────────

_probes_dir="$CONFIGURE_DIR/probes"

run_one_probe()
{
	# Usage: run_one_probe NAME TYPE LIB
	# Dispatches a single probe based on its type.
	# Output (FEATURE content) goes to $FEATDIR/$LIB/FEATURE/$NAME.
	LOCAL _name _type _lib _script _feat_dir _feat_file _fn; BEGIN
		_name=$1; _type=$2; _lib=$3
		_feat_dir="$FEATDIR/${_lib}/FEATURE"
		_feat_file="$_feat_dir/${_name#*-}"
		mkdir -p "$_feat_dir"

		# Route stderr: delegate probes log to file, primitives discard
		case $_type in
		complex|delegate|shell|generator)
			_PROBE_STDERR="$LOGDIR/probe.log" ;;
		*)
			_PROBE_STDERR=/dev/null ;;
		esac

		_script="$_probes_dir/${_name}.sh"
		if test -f "$_script"; then
			# Per-probe script exists — source and call its function.
			# Function names use underscores (not hyphens) for dash compat.
			. "$_script"
			_fn="probe_$(putln "$_name" | tr '-' '_')"
			"$_fn" "$_feat_file"
		else
			case $_type in
			cl)
				choose cl "$_name" "$_name" ;;
			clr)
				choose clr "$_name" "$_name" ;;
			c)
				choose c "$_name" "$_name" ;;
			static|batch|complex|delegate|shell|generator)
				putln "  SKIP: $_name (no probe script yet)" >&2 ;;
			*)
				putln "  ERROR: $_name: unknown type '$_type'" >&2 ;;
			esac
		fi
	END
}

# ── Phase orchestration ──────────────────────────────────────────

run_probes()
{
	probe_init
	# Load manifest (registers all probes)
	. "$CONFIGURE_DIR/manifest.sh"
	putln "[configure] ${_manifest_count} probes registered" >&2

	# Load generator helpers
	. "$CONFIGURE_DIR/gen-features.sh"

	# Execute probes tier-by-tier.
	# Uses a temp file (not a pipe) so the while-read loop runs in the
	# current shell — shell variables set inside probes persist.
	LOCAL _tier _mf _name _t _deps _type _lib _copies _n; BEGIN
		_mf="${_probe_tmpdir}/manifest.txt"
		putln "$_manifest_probes" >|"$_mf"
		_tier=0
		_n=0
		while test "$_tier" -le 7; do
			while IFS='|' read -r _name _t _deps _type _lib _copies; do
				case $_name in ''|'#'*) continue ;; esac
				test "$_t" -eq "$_tier" || continue
				_n=$((_n + 1))
				printf '[%d/%d] PROBE %s\n' "$_n" "$_manifest_count" "$_name" >&2
				run_one_probe "$_name" "$_type" "$_lib"
			done < "$_mf"

			# Post-tier: copy features and regenerate probe_defs
			copy_features
			fixup_ast_common

			# After tier 0: ast_standards.h is now available.
			# Set the preamble that all subsequent probes include
			# in their C source for platform feature-test macros.
			# Also generate ast_release.h — tier 1's common probe
			# needs _AST_release for __builtin_unreachable test.
			if test "$_tier" -eq 0; then
				_PROBE_STD_INC="#include \"$FEATDIR/libast/ast_standards.h\""
				test -s "$FEATDIR/libast/ast_standards.h" || \
					die "ast_standards.h is empty after tier 0"
				. "$CONFIGURE_DIR/emit/headers.sh"
				generate_ast_release_h
			fi

			regenerate_probe_defs
			_tier=$((_tier + 1))
		done
	END
}

run_generators()
{
	putln "[configure] generating headers" >&2

	# Source emitter modules
	. "$CONFIGURE_DIR/emit/headers.sh"
	. "$CONFIGURE_DIR/emit/sources.sh"

	# Generate derived headers
	generate_ast_release_h
	generate_git_h
	generate_shopt_h
	generate_cmd_headers

	# Post-probe: install std/ wrappers and endian stubs
	install_std_wrappers
	install_endian_stubs
}

run_emitters()
{
	putln "[configure] emitting build.ninja" >&2

	# Source emitter modules
	. "$CONFIGURE_DIR/emit/ninja.sh"
	. "$CONFIGURE_DIR/emit/test-infra.sh"

	# Generate build.ninja and test infrastructure
	emit_ninja
	generate_test_env
}

# ── Logging helper (used by emitters) ────────────────────────────

configure_log()
{
	printf '[configure] %s\n' "$1" >&2
}

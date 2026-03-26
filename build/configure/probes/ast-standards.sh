# probe: ast-standards — platform feature-test macros
# Tier 0 (root of all probes). Detects platform and emits
# the feature-test macro block that enables POSIX/platform APIs.
#
# Lifted from monolith probe_ast_standards with minimal changes:
# - probe_compile → _mc_compile
# - output path from $1 (driver convention)

probe_ast_standards()
{
	_pas_out="$1"    # output file path

	# Cache check: skip if output exists and is newer than source
	if [ "$opt_force" = 0 ] && [ -f "$_pas_out" ] \
	   && [ "$_pas_out" -nt "$LIBAST_SRC/features/standards" ]; then
		return 0
	fi

	# Step 1: determine u_long availability (nodefine — not emitted)
	_typ_u_long=0
	if _mc_compile <<'EOF'
#include <sys/types.h>
static u_long _i;
int n = sizeof(_i);
EOF
	then
		_typ_u_long=1
	fi

	# Step 2: platform detection cascade
	_pas_platform=""
	_pas_block=""

	# --- BSD (Free, Net, Open, et al) ---
	if [ -z "$_pas_platform" ] && _mc_compile "-D_typ_u_long=$_typ_u_long" <<'EOF'
#include <limits.h>
#include <unistd.h>
#include <sys/param.h>
#include <sys/types.h>
#include <wchar.h>
#if !(BSD && !__APPLE__ && !__MACH__ && !NeXTBSD)  /* NeXT/macOS falsely claim to be BSD */
#error not BSD
#endif
int _do_these_compile_ = _POSIX_PATH_MAX & _SC_PAGESIZE;
#if _typ_u_long
u_long _test_dummy_;
#endif
int main(void)
{
	wchar_t _wchar_dummy_ = 0;
	wcwidth(_wchar_dummy_);
	return 0;
}
EOF
	then
		_pas_platform="BSD (Free, Net, Open, et al)"
		_pas_block='#define _XOPEN_SOURCE	9900
#define _POSIX_C_SOURCE 21000101L
#define _BSD_SOURCE	1	/* OpenBSD needs this */
#define _NETBSD_SOURCE	1	/* NetBSD needs this */
#define __BSD_VISIBLE	1	/* FreeBSD needs this */'
	fi

	# --- Darwin (macOS, Mac OS X) ---
	if [ -z "$_pas_platform" ] && _mc_compile "-D_typ_u_long=$_typ_u_long" <<'EOF'
#define _DARWIN_C_SOURCE 1
#include <limits.h>
#include <unistd.h>
#include <sys/param.h>
#include <sys/types.h>
#include <wchar.h>
#if !(__APPLE__ && __MACH__ && NeXTBSD)
#error not Darwin
#endif
int _do_these_compile_ = _POSIX_PATH_MAX & _SC_PAGESIZE;
#if _typ_u_long
u_long _test_dummy_;
#endif
int main(void)
{
	wchar_t _wchar_dummy_ = 0;
	wcwidth(_wchar_dummy_);
	return 0;
}
EOF
	then
		_pas_platform="Darwin (macOS, Mac OS X)"
		_pas_block='#ifndef _DARWIN_C_SOURCE
#define _DARWIN_C_SOURCE 1
#endif'
	fi

	# --- SunOS (Solaris, illumos) ---
	if [ -z "$_pas_platform" ] && _mc_compile "-D_typ_u_long=$_typ_u_long" <<'EOF'
#define _XPG7
#define _XPG6
#define _XPG5
#define _XPG4_2
#define _XPG4
#define _XPG3
#define __EXTENSIONS__	1
#undef _XOPEN_SOURCE
#define _XOPEN_SOURCE	9900
#undef _POSIX_C_SOURCE
#include <limits.h>
#include <unistd.h>
#include <sys/types.h>
#include <wchar.h>
#if !__sun
#error dark
#endif
int _do_these_compile_ = _POSIX_PATH_MAX & _SC_PAGESIZE;
#if _typ_u_long
u_long _test_dummy_;
#endif
int main(void)
{
	wchar_t _wchar_dummy_ = 0;
	wcwidth(_wchar_dummy_);
	return 0;
}
EOF
	then
		_pas_platform="SunOS (Solaris, illumos)"
		_pas_block='#define _XPG7
#define	_XPG6
#define	_XPG5
#define _XPG4_2
#define _XPG4
#define _XPG3
#define __EXTENSIONS__	1
#undef _XOPEN_SOURCE
#define	_XOPEN_SOURCE	9900
#undef _POSIX_C_SOURCE
#if __SUNPRO_C
#undef 	NULL
#define	NULL	0
#endif /* __SUNPRO_C */'
	fi

	# --- GNU (glibc) or Android ---
	if [ -z "$_pas_platform" ] && _mc_compile "-D_typ_u_long=$_typ_u_long" <<'EOF'
#define _GNU_SOURCE	1
#define _FILE_OFFSET_BITS 64
#define _TIME_BITS 64
#include <limits.h>
#include <unistd.h>
#include <features.h>
#include <sys/types.h>
#include <wchar.h>
#if !__GLIBC__ && !__ANDROID_API__
#error not GNU or Android
#endif
int _do_these_compile_ = _POSIX_PATH_MAX & _SC_PAGESIZE;
#if _typ_u_long
u_long _test_dummy_;
#endif
int main(void)
{
	wchar_t _wchar_dummy_ = 0;
	wcwidth(_wchar_dummy_);
	return 0;
}
EOF
	then
		_pas_platform="GNU (glibc) or Android"
		_pas_block='#ifndef _GNU_SOURCE
#define _GNU_SOURCE	1
#endif
#ifndef _FILE_OFFSET_BITS
#define _FILE_OFFSET_BITS 64
#endif
#ifndef _TIME_BITS
#define _TIME_BITS 64
#endif'
	fi

	# --- _ALL_SOURCE & _POSIX_SOURCE & _POSIX_C_SOURCE & _XOPEN_SOURCE & __EXTENSIONS__ ---
	if [ -z "$_pas_platform" ] && _mc_compile "-D_typ_u_long=$_typ_u_long" <<'EOF'
#define _ALL_SOURCE	1
#define _POSIX_SOURCE	1
#define _POSIX_C_SOURCE	21000101L
#define _XOPEN_SOURCE	9900
#define __EXTENSIONS__	1
#include <sys/types.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <limits.h>
int _do_these_compile_ = _POSIX_PATH_MAX & _SC_PAGESIZE;
#if _typ_u_long
u_long _test_dummy_;
#endif
EOF
	then
		_pas_platform="_ALL_SOURCE & _POSIX_SOURCE & _POSIX_C_SOURCE & _XOPEN_SOURCE & __EXTENSIONS__ works"
		_pas_block='#ifndef _ALL_SOURCE
#define _ALL_SOURCE	1
#endif
#ifndef _POSIX_SOURCE
#define _POSIX_SOURCE	1
#endif
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE	21000101L
#endif
#ifndef _XOPEN_SOURCE
#define _XOPEN_SOURCE	9900
#endif
#ifndef __EXTENSIONS__
#define __EXTENSIONS__	1
#endif'
	fi

	# --- _ALL_SOURCE & _POSIX_SOURCE & _XOPEN_SOURCE & __EXTENSIONS__ ---
	if [ -z "$_pas_platform" ] && _mc_compile "-D_typ_u_long=$_typ_u_long" <<'EOF'
#define _ALL_SOURCE	1
#define _POSIX_SOURCE	1
#define _XOPEN_SOURCE	9900
#define __EXTENSIONS__	1
#include <sys/types.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <limits.h>
int _do_these_compile_ = _POSIX_PATH_MAX & _SC_PAGESIZE;
#if _typ_u_long
u_long _test_dummy;
#endif
EOF
	then
		_pas_platform="_ALL_SOURCE & _POSIX_SOURCE & _XOPEN_SOURCE & __EXTENSIONS__ works"
		_pas_block='#ifndef _ALL_SOURCE
#define _ALL_SOURCE	1
#endif
#ifndef _POSIX_SOURCE
#define _POSIX_SOURCE	1
#endif
#ifndef _XOPEN_SOURCE
#define _XOPEN_SOURCE	9900
#endif
#ifndef __EXTENSIONS__
#define __EXTENSIONS__	1
#endif'
	fi

	# --- _POSIX_SOURCE & _POSIX_C_SOURCE & _XOPEN_SOURCE & __EXTENSIONS__ ---
	if [ -z "$_pas_platform" ] && _mc_compile "-D_typ_u_long=$_typ_u_long" <<'EOF'
#define _POSIX_SOURCE	1
#define _POSIX_C_SOURCE	21000101L
#define _XOPEN_SOURCE	9900
#define __EXTENSIONS__	1
#include <sys/types.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <limits.h>
int _do_these_compile_ = _POSIX_PATH_MAX & _SC_PAGESIZE;
#if _typ_u_long
u_long _test_dummy;
#endif
EOF
	then
		_pas_platform="_POSIX_SOURCE & _POSIX_C_SOURCE & _XOPEN_SOURCE & __EXTENSIONS__ works"
		_pas_block='#ifndef _POSIX_SOURCE
#define _POSIX_SOURCE	1
#endif
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE	21000101L
#endif
#ifndef _XOPEN_SOURCE
#define _XOPEN_SOURCE	9900
#endif
#ifndef __EXTENSIONS__
#define __EXTENSIONS__	1
#endif'
	fi

	# --- _POSIX_SOURCE & _XOPEN_SOURCE & __EXTENSIONS__ ---
	if [ -z "$_pas_platform" ] && _mc_compile "-D_typ_u_long=$_typ_u_long" <<'EOF'
#define _POSIX_SOURCE	1
#define _XOPEN_SOURCE	1
#define __EXTENSIONS__	1
#include <sys/types.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <limits.h>
int _do_these_compile_ = _POSIX_PATH_MAX & _SC_PAGESIZE;
#if _typ_u_long
u_long _test_dummy;
#endif
EOF
	then
		_pas_platform="_POSIX_SOURCE & _XOPEN_SOURCE & __EXTENSIONS__ works"
		_pas_block='#ifndef _POSIX_SOURCE
#define _POSIX_SOURCE	1
#endif
#ifndef _XOPEN_SOURCE
#define _XOPEN_SOURCE	1
#endif
#ifndef __EXTENSIONS__
#define __EXTENSIONS__	1
#endif'
	fi

	# --- _XOPEN_SOURCE & __EXTENSIONS__ ---
	if [ -z "$_pas_platform" ] && _mc_compile "-D_typ_u_long=$_typ_u_long" <<'EOF'
#define _XOPEN_SOURCE	1
#define __EXTENSIONS__	1
#include <sys/types.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <limits.h>
int _do_these_compile_ = _POSIX_PATH_MAX & _SC_PAGESIZE;
#if _typ_u_long
u_long _test_dummy;
#endif
EOF
	then
		_pas_platform="_XOPEN_SOURCE & __EXTENSIONS__ works"
		_pas_block='#ifndef _XOPEN_SOURCE
#define _XOPEN_SOURCE	1
#endif
#ifndef __EXTENSIONS__
#define __EXTENSIONS__	1
#endif'
	fi

	# --- _XOPEN_SOURCE only ---
	if [ -z "$_pas_platform" ] && _mc_compile "-D_typ_u_long=$_typ_u_long" <<'EOF'
#define _XOPEN_SOURCE	1
#include <sys/types.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <limits.h>
int _do_these_compile_ = _POSIX_PATH_MAX & _SC_PAGESIZE;
#if _typ_u_long
u_long _test_dummy;
#endif
EOF
	then
		_pas_platform="_XOPEN_SOURCE works"
		_pas_block='#ifndef _XOPEN_SOURCE
#define _XOPEN_SOURCE	1
#endif'
	fi

	# --- __EXTENSIONS__ only (final fallback) ---
	if [ -z "$_pas_platform" ] && _mc_compile "-D_typ_u_long=$_typ_u_long" <<'EOF'
#define __EXTENSIONS__	1
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <limits.h>
int _do_these_compile_ = _POSIX_PATH_MAX & _SC_PAGESIZE;
#if _typ_u_long
u_long _test_dummy;
#endif
EOF
	then
		_pas_platform="__EXTENSIONS__ works"
		_pas_block='#ifndef __EXTENSIONS__
#define __EXTENSIONS__	1
#endif'
	fi


	# Step 3: emit the header
	{
		echo "/* : : generated by configure.sh probe_ast_standards : : */"
		echo "#ifndef _def_standards_ast"
		echo "#define _def_standards_ast	1"
		echo "#define _sys_types	1	/* #include <sys/types.h> ok */"
		if [ -n "$_pas_platform" ]; then
			echo "/* ${_pas_platform} */"
			echo "$_pas_block"
		fi
		echo ""
		echo "#endif"
	} | atomic_write "$_pas_out" || true
}

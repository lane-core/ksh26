# probe: ast-common — integer types, float types, va_list, compiler features
# Tier 1 (largest probe). Detects core type sizes, generates _ast_int*_t,
# _ast_flt*_t, sizeof macros, va_list handling, and compiler capabilities.
#
# Lifted from monolith probe_ast_common with API translations:
# - probe_hdr → _mc_hdr, probe_sys → _mc_sys, probe_typ → _mc_typ
# - probe_compile → _mc_compile, probe_execute → _mc_execute
# - probe_output → _mc_output
# - output path from $1

probe_ast_common()
{
	_out="$1"

	# Cache check
	if [ "$opt_force" = 0 ] && [ -f "$_out" ] \
	   && [ "$_out" -nt "$LIBAST_SRC/features/common" ]; then
		return 0
	fi

	_inc_dir="$FEATDIR/libast"

	# ── Header probes ──
	_hdr_defines=""
	for _h in pthread stdarg stddef stdint inttypes types unistd; do
		if _mc_hdr "${_h}.h"; then
			_hdr_defines="${_hdr_defines}#define _hdr_${_h}	1	/* #include <${_h}.h> ok */
"
		fi
	done

	# sys types
	_sys_types=0
	if _mc_sys types; then
		_sys_types=1
	fi

	# typ __va_list stdio.h — implicit header sequence from iffe
	_typ_hdr_defines=""
	if _mc_hdr "time.h"; then
		_typ_hdr_defines="${_typ_hdr_defines}#define _hdr_time	1	/* #include <time.h> ok */
"
	fi
	if _mc_sys "time"; then
		_typ_hdr_defines="${_typ_hdr_defines}#define _sys_time	1	/* #include <sys/time.h> ok */
"
	fi
	if _mc_sys "times"; then
		_typ_hdr_defines="${_typ_hdr_defines}#define _sys_times	1	/* #include <sys/times.h> ok */
"
	fi
	if _mc_hdr "stdlib.h"; then
		_typ_hdr_defines="${_typ_hdr_defines}#define _hdr_stdlib	1	/* #include <stdlib.h> ok */
"
	fi
	if _mc_hdr "stdio.h"; then
		_typ_hdr_defines="${_typ_hdr_defines}#define _hdr_stdio	1	/* #include <stdio.h> ok */
"
	fi

	# ── ast_LL test (LL numeric suffix) ──
	_ast_LL=0
	if _mc_compile <<'EOF'
int i = 1LL;
unsigned int u = 1ULL;
EOF
	then
		_ast_LL=1
	fi

	# ── Integer type sizing (output block) ──
	_int_types=$(_mc_output <<EOF
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#define _ast_LL $_ast_LL
#define _ast_int8_t long
#define _ast_int8_str "long"
#define elementsof(x) (sizeof(x)/sizeof(x[0]))
static char i_char = 1;
static short i_short = 1;
static int i_int = 1;
static long i_long = 1L;
#if _ast_LL
static _ast_int8_t i_long_long = 1LL;
static unsigned _ast_int8_t u_long_long = 18446744073709551615ULL;
#else
static _ast_int8_t i_long_long = 1;
static unsigned _ast_int8_t u_long_long = 18446744073709551615;
#endif
static struct { char* name; int size; char* swap; } int_type[] = {
	"char", sizeof(char), (char*)&i_char,
	"short", sizeof(short), (char*)&i_short,
	"int", sizeof(int), (char*)&i_int,
	"long", sizeof(long), (char*)&i_long,
	_ast_int8_str, sizeof(_ast_int8_t), (char*)&i_long_long,
};
static int int_size[] = { 1, 2, 4, 8 };
int main(void) {
	int t, s, m = 1, b = 1, w = 0;
	unsigned _ast_int8_t p;
	char buf[64];
	if (int_type[elementsof(int_type)-1].size <= 4) return 1;
	p = 0x12345678;
	p <<= 32;
	p |= 0x9abcdef0;
	sprintf(buf, "0x%016llx", p);
	if (strcmp(buf, "0x123456789abcdef0")) return 1;
	for (s = 0; s < elementsof(int_size); s++) {
		for (t = 0; t < elementsof(int_type) && int_type[t].size < int_size[s]; t++);
		if (t < elementsof(int_type)) {
			m = int_size[s];
			printf("#define _ast_int%d_t\t\t%s\n", m, int_type[t].name);
			if (m > 1) { if (*int_type[t].swap) w |= b; b <<= 1; }
		}
	}
	printf("#define _ast_intmax_t\t\t_ast_int%d_t\n", m);
	if (m == sizeof(long)) printf("#define _ast_intmax_long\t\t1\n");
	printf("#define _ast_intswap\t\t%d\n", w);
	printf("\n");
	return 0;
}
EOF
)

	# ── sizeof types (output block) ──
	_sizeof_types=$(_mc_output <<'EOF'
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#define elementsof(x) (sizeof(x)/sizeof(x[0]))
static struct { char* name; int size; int cond; } types[] = {
	"short", sizeof(short), 0,
	"int", sizeof(int), 0,
	"long", sizeof(long), 0,
	"size_t", sizeof(size_t), 0,
	"pointer", sizeof(void*), 0,
	"float", sizeof(float), 0,
	"double", sizeof(double), 0,
	"long_double", sizeof(long double), 0,
};
int main(void) {
	int t;
	for (t = 0; t < elementsof(types); t++)
		printf("#define _ast_sizeof_%s%s	%d	/* sizeof(%s) */\n",
			types[t].name,
			strlen(types[t].name) < 4 ? "\t" : "",
			types[t].size, types[t].name);
	printf("\n");
	return 0;
}
EOF
)

	# ── Float types (output block) ──
	_flt_types=$(_mc_output <<'EOF'
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#define elementsof(x) (sizeof(x)/sizeof(x[0]))
static struct { char* name; int size; } flt_type[] = {
	"float", sizeof(float),
	"double", sizeof(double),
	"long double", sizeof(long double),
};
int main(void) {
	int t, m = 1, e = elementsof(flt_type);
	if (flt_type[e - 1].size <= sizeof(double)) e--;
	else {
		long double p; char buf[64];
		p = 1.12345E-55;
		sprintf(buf, "%1.5LE", p);
		if (strcmp(buf, "1.12345E-55")) e--;
	}
	for (t = 0; t < e; t++) {
		while (t < (e - 1) && flt_type[t].size == flt_type[t + 1].size) t++;
		m = flt_type[t].size;
		printf("#define _ast_flt%d_t\t\t%s\n", flt_type[t].size, flt_type[t].name);
	}
	printf("#define _ast_fltmax_t\t\t_ast_flt%d_t\n", m);
	if (m == sizeof(double)) printf("#define _ast_fltmax_double\t\t1\n");
	return 0;
}
EOF
)

	# ── Standard integer types (typ probes) ──
	_typ_defines=""
	for _t in int8_t uint8_t int16_t uint16_t int32_t uint32_t \
		  int64_t uint64_t intmax_t intptr_t uintmax_t uintptr_t; do
		if _mc_typ "$_t" stdint.h; then
			_typ_defines="${_typ_defines}#define _typ_${_t}	1	/* ${_t} is a type */
"
		fi
	done

	# ── va_list handling (output block) ──
	# TRY=1: *ap++ dereference (modern stdarg.h)
	_va_list=$(_mc_output <<'EOF'
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
static void varyfunny(int* p, ...) {
	va_list ap;
	va_start(ap, p);
	*p = *ap++ != 0;
	va_end(ap);
}
int main(void) {
	int r;
	printf("\n#ifndef va_listref\n");
	printf("#ifndef\tva_start\n");
	printf("#include <stdarg.h>\n");
	printf("#endif\n");
	varyfunny(&r);
	printf("#define va_listref(p) (p)\t");
	printf("/* pass va_list to varargs function */\n");
	if (sizeof(va_list) > sizeof(void*))
		printf("#define va_listval(p) (*(p))\t");
	else
		printf("#define va_listval(p) (p)\t");
	printf("/* retrieve va_list from va_arg(ap,va_listarg) */\n");
	printf("#define va_listarg va_list\t");
	printf("/* va_arg() va_list type */\n");
	printf("#endif\n");
	return 0;
}
EOF
)
	# TRY=2: *ap++ with -Dvoid=char
	if [ -z "$_va_list" ]; then
		_va_list=$(_mc_output "-Dvoid=char" <<'EOF'
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
static void varyfunny(int* p, ...) {
	va_list ap;
	va_start(ap, p);
	*p = *ap++ != 0;
	va_end(ap);
}
int main(void) {
	int r;
	printf("\n#ifndef va_listref\n");
	printf("#ifndef\tva_start\n");
	printf("#include <stdarg.h>\n");
	printf("#endif\n");
	varyfunny(&r);
	printf("#define va_listref(p) (p)\t");
	printf("/* pass va_list to varargs function */\n");
	if (sizeof(va_list) > sizeof(void*))
		printf("#define va_listval(p) (*(p))\t");
	else
		printf("#define va_listval(p) (p)\t");
	printf("/* retrieve va_list from va_arg(ap,va_listarg) */\n");
	printf("#define va_listarg va_list\t");
	printf("/* va_arg() va_list type */\n");
	printf("#endif\n");
	return 0;
}
EOF
)
	fi
	# TRY=3: *ap dereference (no increment)
	if [ -z "$_va_list" ]; then
		_va_list=$(_mc_output <<'EOF'
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
static void varyfunny(int* p, ...) {
	va_list ap;
	va_start(ap, p);
	*p = *ap != 0;
	va_end(ap);
}
int main(void) {
	int r;
	printf("\n#ifndef va_listref\n");
	printf("#ifndef\tva_start\n");
	printf("#include <stdarg.h>\n");
	printf("#endif\n");
	varyfunny(&r);
	printf("#define va_listref(p) (p)\t");
	printf("/* pass va_list to varargs function */\n");
	if (sizeof(va_list) > sizeof(void*))
		printf("#define va_listval(p) (*(p))\t");
	else
		printf("#define va_listval(p) (p)\t");
	printf("/* retrieve va_list from va_arg(ap,va_listarg) */\n");
	printf("#define va_listarg va_list*\t");
	printf("/* va_arg() va_list type */\n");
	printf("#endif\n");
	return 0;
}
EOF
)
	fi
	# TRY=4: ap++ (pointer comparison, no dereference)
	if [ -z "$_va_list" ]; then
		_va_list=$(_mc_output <<'EOF'
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
static void varyfunny(int* p, ...) {
	va_list ap;
	va_start(ap, p);
	*p = ap++ != 0;
	va_end(ap);
}
int main(void) {
	int r;
	printf("\n#ifndef va_listref\n");
	printf("#ifndef\tva_start\n");
	printf("#include <stdarg.h>\n");
	printf("#endif\n");
	varyfunny(&r);
	printf("#define va_listref(p) (p)\t");
	printf("/* pass va_list to varargs function */\n");
	if (sizeof(va_list) > sizeof(void*))
		printf("#define va_listval(p) (*(p))\t");
	else
		printf("#define va_listval(p) (p)\t");
	printf("/* retrieve va_list from va_arg(ap,va_listarg) */\n");
	printf("#define va_listarg va_list\t");
	printf("/* va_arg() va_list type */\n");
	printf("#endif\n");
	return 0;
}
EOF
)
	fi
	# Fallback (pass by reference)
	if [ -z "$_va_list" ]; then
		_va_list='
#ifndef va_listref
#ifndef	va_start
#include <stdarg.h>
#endif
#define va_listref(p) (&(p))	/* pass va_list to varargs function */
#define va_listval(p) (*(p))	/* retrieve va_list from va_arg(ap,va_listarg) */
#define va_listarg va_list*	/* va_arg() va_list type */
#endif'
	fi

	# ── UNREACHABLE, __func__, __FUNCTION__, _Static_assert ──
	_unreachable='#define UNREACHABLE()	abort()'
	if [ -f "$_inc_dir/ast_release.h" ]; then
		_ur_result=$(_mc_output "-I$_inc_dir" <<'EOF'
#include <stdio.h>
#include "ast_release.h"
void testfn(int a) {
	switch(a) {
	case 0: __builtin_unreachable();
	default:
#if _AST_release
		printf("#define UNREACHABLE()\t__builtin_unreachable()\n");
#else
		printf("#define UNREACHABLE()\tabort()\n");
#endif
	}
}
int main(int argc, char *argv[]) { testfn(argc); return 0; }
EOF
)
		if [ -n "$_ur_result" ]; then
			_unreachable="$_ur_result"
		fi
	fi

	# __func__ test
	_has_func=""
	if _mc_execute <<'EOF'
#include <string.h>
int testfn(void) { return strcmp(__func__,"testfn")==0; }
int main(void) { return !(testfn && strcmp(__func__,"main")==0); }
EOF
	then
		_has_func='#define _has___func__	1	/* does this compiler have __func__ */'
	fi

	# __FUNCTION__ test
	_has_FUNCTION=""
	if _mc_execute <<'EOF'
#include <string.h>
int testfn(void) { return strcmp(__FUNCTION__,"testfn")==0; }
int main(void) { return !(testfn && strcmp(__FUNCTION__,"main")==0); }
EOF
	then
		_has_FUNCTION='#define _has___FUNCTION__	1	/* does this compiler have __FUNCTION__ */'
	fi

	# _Static_assert test
	_has_static_assert=""
	if _mc_execute <<'EOF'
int main(void) { _Static_assert(2 + 2 == 4, "poof goes reality"); }
EOF
	then
		_has_static_assert='#define _has__Static_assert	1	/* does this compiler have _Static_assert */'
	fi

	# ── Emit the header ──
	{
		echo "/* : : generated by configure.sh probe_ast_common : : */"
		echo "#ifndef _AST_COMMON_H"
		echo "#define _AST_COMMON_H	1"
		# _sys_types
		[ "$_sys_types" = 1 ] && echo "#define _sys_types	1	/* #include <sys/types.h> ok */"
		# hdr probes (pthread, stdarg, stddef, stdint, inttypes, unistd)
		printf '%s' "$_hdr_defines"
		# typ implicit headers (time, sys/time, sys/times, stdlib, stdio)
		printf '%s' "$_typ_hdr_defines"
		# cat block: pragma diagnostics + backward compat macros
		cat <<'CATBLOCK'
#if __clang__
#pragma clang diagnostic ignored "-Wmissing-braces"
#pragma clang diagnostic ignored "-Wparentheses"
#pragma clang diagnostic ignored "-Wstring-plus-int"
#pragma clang diagnostic ignored "-Wunused-value"
#pragma clang diagnostic ignored "-Wmissing-field-initializers"
#pragma clang diagnostic ignored "-Woverlength-strings"
#elif __GNUC__
#pragma GCC diagnostic ignored "-Wpragmas"
#pragma GCC diagnostic ignored "-Wmissing-braces"
#pragma GCC diagnostic ignored "-Wparentheses"
#pragma GCC diagnostic ignored "-Wunused-result"
#pragma GCC diagnostic ignored "-Wunused-value"
#pragma GCC diagnostic ignored "-Wmissing-field-initializers"
#pragma GCC diagnostic ignored "-Woverlength-strings"
#endif

/* AST backward compatibility macros */
#undef	_NIL_
#define	_NIL_(x)	NULL
#undef	_STD_
#define	_STD_		1
#undef	_ARG_
#define	_ARG_(x)	x
#undef	_VOID_
#define	_VOID_		void
#undef	_BEGIN_EXTERNS_
#define	_BEGIN_EXTERNS_
#undef	_END_EXTERNS_
#define	_END_EXTERNS_
#undef __EXTERN__
#define __EXTERN__(T,obj)	extern T obj
#undef __DEFINE__
#define __DEFINE__(T,obj,val)	T obj = val
#undef	__STD_C
#define	__STD_C		1
#undef	Void_t
#define	Void_t		void

/* __INLINE__, if defined, is the inline keyword */
#if !defined(__INLINE__) && defined(_WIN32) && !defined(__GNUC__)
#	define __INLINE__	__inline
#endif
CATBLOCK
		echo ""
		# _ast_LL
		[ "$_ast_LL" = 1 ] && echo "#define _ast_LL	1	/* LL numeric suffix supported */"
		# Integer types from output block (ends with blank line)
		[ -n "$_int_types" ] && printf '%s\n\n' "$_int_types"
		# Sizeof types from output block (ends with blank line)
		[ -n "$_sizeof_types" ] && printf '%s\n\n' "$_sizeof_types"
		# Float types from output block
		[ -n "$_flt_types" ] && printf '%s\n' "$_flt_types"
		# Standard integer type defines
		printf '%s' "$_typ_defines"
		# va_list handling
		printf '%s\n' "$_va_list"
		# cat block: conditional includes
		cat <<'CATBLOCK2'
#ifndef _AST_STD_H
#	if _hdr_stddef
#	include	<stddef.h>
#	endif
#	if _sys_types
#	include	<sys/types.h>
#	endif
#	if _hdr_stdint
#	include	<stdint.h>
#	else
#		if _hdr_inttypes
#		include	<inttypes.h>
#		endif
#	endif
#endif
#ifndef _AST_STD_H
#	define _def_map_ast	1
#	if !_def_map_ast
#		include <ast_map.h>
#	endif
#endif
CATBLOCK2
		echo ""
		# UNREACHABLE
		echo "$_unreachable"
		# __func__, __FUNCTION__, _Static_assert
		[ -n "$_has_func" ] && echo "$_has_func"
		[ -n "$_has_FUNCTION" ] && echo "$_has_FUNCTION"
		[ -n "$_has_static_assert" ] && echo "$_has_static_assert"
		echo "#endif"
	} | atomic_write "$_out" || true
}

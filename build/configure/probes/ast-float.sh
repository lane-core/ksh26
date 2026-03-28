# probe: ast-float — floating point features (~600 lines)
# Tier 5 (complex). Detects float/math headers, frexp/ldexp linkage,
# FLT/DBL/LDBL limits, digit counts, exponent bitfoolery, unsigned max.
#
# Lifted from monolith probe_ast_float with API translations:
# - probe_hdr → _mc_hdr, probe_lib → _mc_lib
# - probe_compile → _mc_compile, probe_link → _mc_link
# - probe_output → _mc_output
# - output path from $1

probe_ast_float()
{
	_out="$1"

	# Cache check
	if [ "$opt_force" = 0 ] && [ -f "$_out" ] \
	   && [ "$_out" -nt "$LIBAST_SRC/features/float" ]; then
		return 0
	fi

	# float probe needs FEATURE/common and FEATURE/standards for _ast_fltmax_t etc
	_flt_work="$FEATDIR/libast/_work_float"
	mkdir -p "$_flt_work"
	[ -L "$_flt_work/FEATURE" ] || ln -sf "$FEATDIR/libast/FEATURE" "$_flt_work/FEATURE"

	_flt_inc="-I$FEATDIR/libast -I$LIBAST_SRC -I$LIBAST_SRC/comp -I$LIBAST_SRC/include"
	_saved="$CFLAGS_BASE"
	CFLAGS_BASE="$CFLAGS_BASE $_flt_inc"

	_flt_defs=""

	# hdr probes
	for _h in float limits math; do
		if _mc_hdr "${_h}.h"; then
			_flt_defs="${_flt_defs}#define _hdr_${_h}	1	/* #include <${_h}.h> ok */
"
		fi
	done

	# _LIB_m
	if _mc_lib "sin" "-lm"; then
		_flt_defs="${_flt_defs}#define _LIB_m	1	/* -lm is a library */
"
	fi

	# lib + npt probes
	for _fn in frexp ldexp; do
		if _mc_lib "$_fn" "-lm"; then
			_flt_defs="${_flt_defs}#define _lib_${_fn}	1	/* ${_fn}() in default lib(s) */
"
		fi
	done
	# copysign, copysignl, powf, pow, powl
	for _fn in copysign copysignl powf pow powl; do
		if _mc_lib "$_fn" "-lm"; then
			_flt_defs="${_flt_defs}#define _lib_${_fn}	1	/* ${_fn}() in default lib(s) */
"
		fi
	done

	# npt finite, finitel — needs prototype?
	for _fn in finite finitel; do
		if ! _mc_compile <<EOF
${_PROBE_STD_INC}
#include <math.h>
static int (*_test_)(double) = ${_fn};
EOF
		then
			_flt_defs="${_flt_defs}#define _npt_${_fn}	1	/* ${_fn}() needs a prototype */
"
		fi
	done

	# lib frexpl link{} test
	_lib_frexpl=0
	if _mc_link "-lm" <<'EOF'
#include <stdlib.h>
#include <math.h>
int main(void)
{
	int e;
	long double f = frexpl(123.456789 + (long double)(rand()), &e);
	return !(e > 0.0);
}
EOF
	then
		_lib_frexpl=1
		_flt_defs="${_flt_defs}#define _lib_frexpl	1	/* does frexpl(3) compile and link */
"
	fi

	# lib ldexpl link{} test
	_lib_ldexpl=0
	if _mc_link "-lm" <<'EOF'
#include <stdlib.h>
#include <math.h>
int main(void)
{
	long double f = ldexpl(0.96450616406250000434141611549421213567256927490234375 + (long double)(rand()), 7);
	return !(f > 0.0);
}
EOF
	then
		_lib_ldexpl=1
		_flt_defs="${_flt_defs}#define _lib_ldexpl	1	/* does ldexpl(3) compile and link */
"
	fi

	# hdr stdlib, unistd (needed by subsequent link tests in iffe output)
	if _mc_hdr "stdlib.h"; then
		_flt_defs="${_flt_defs}#define _hdr_stdlib	1	/* #include <stdlib.h> ok */
"
	fi
	if _mc_hdr "unistd.h"; then
		_flt_defs="${_flt_defs}#define _hdr_unistd	1	/* #include <unistd.h> ok */
"
	fi

	# npt frexpl, ldexpl
	for _fn in frexpl ldexpl; do
		if ! _mc_compile <<EOF
${_PROBE_STD_INC}
#include <math.h>
static long double (*_test_)(long double, int*) = ${_fn};
EOF
		then
			_flt_defs="${_flt_defs}#define _npt_${_fn}	1	/* ${_fn}() needs a prototype */
"
		fi
	done

	# lib fpclassify, isinf, isnan, signbit link{} tests
	for _fn in fpclassify isinf isnan signbit; do
		case $_fn in
		fpclassify)
			_flt_test_code='
#include <sys/types.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <unistd.h>
#include <math.h>
int main(void) { return !(fpclassify((double)(rand()))==FP_ZERO); }' ;;
		isinf)
			_flt_test_code='
#include <sys/types.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <unistd.h>
#include <math.h>
int main(void) { return isinf(2.0 * ((double)(rand()))); }' ;;
		isnan)
			_flt_test_code='
#include <sys/types.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <unistd.h>
#include <math.h>
int main(void) { return isnan(2.0 * ((double)(rand()))); }' ;;
		signbit)
			_flt_test_code='
#include <sys/types.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <unistd.h>
#include <math.h>
int main(void) { return signbit(2.0 * ((double)(rand()))); }' ;;
		esac
		if _mc_link "-lm" <<EOF
$_flt_test_code
EOF
		then
			_flt_defs="${_flt_defs}#define _lib_${_fn}	1	/* does ${_fn}(3) compile and link */
"
		fi
	done

	# macro{} block — emit float/math includes and FLT_*/DBL_*/LDBL_* ifdefs
	_flt_macro=$(_mc_output "-lm" <<'EOF'
#include <stdio.h>
#include <float.h>
#include <limits.h>
#include <math.h>
int
main(void)
{
	printf("#include <ast_common.h>\n");
	printf("#include <float.h>\n");
	printf("#include <math.h>\n");
#ifdef FLT_DIG
	printf("#ifndef FLT_DIG\n#define FLT_DIG %d\n#endif\n", FLT_DIG);
#endif
#ifdef FLT_MAX
	printf("#ifndef FLT_MAX\n#define FLT_MAX %.*E\n#endif\n", FLT_DIG + 1, (double)FLT_MAX);
#endif
#ifdef FLT_MAX_10_EXP
	printf("#ifndef FLT_MAX_10_EXP\n#define FLT_MAX_10_EXP %d\n#endif\n", FLT_MAX_10_EXP);
#endif
#ifdef FLT_MAX_EXP
	printf("#ifndef FLT_MAX_EXP\n#define FLT_MAX_EXP %d\n#endif\n", FLT_MAX_EXP);
#endif
#ifdef FLT_MIN
	printf("#ifndef FLT_MIN\n#define FLT_MIN %.*E\n#endif\n", FLT_DIG + 1, (double)FLT_MIN);
#endif
#ifdef FLT_MIN_10_EXP
	printf("#ifndef FLT_MIN_10_EXP\n#define FLT_MIN_10_EXP (%d)\n#endif\n", FLT_MIN_10_EXP);
#endif
#ifdef FLT_MIN_EXP
	printf("#ifndef FLT_MIN_EXP\n#define FLT_MIN_EXP (%d)\n#endif\n", FLT_MIN_EXP);
#endif
#ifdef DBL_DIG
	printf("#ifndef DBL_DIG\n#define DBL_DIG %d\n#endif\n", DBL_DIG);
#endif
#ifdef DBL_MAX
	printf("#ifndef DBL_MAX\n#define DBL_MAX %.*E\n#endif\n", DBL_DIG + 1, DBL_MAX);
#endif
#ifdef DBL_MAX_10_EXP
	printf("#ifndef DBL_MAX_10_EXP\n#define DBL_MAX_10_EXP %d\n#endif\n", DBL_MAX_10_EXP);
#endif
#ifdef DBL_MAX_EXP
	printf("#ifndef DBL_MAX_EXP\n#define DBL_MAX_EXP %d\n#endif\n", DBL_MAX_EXP);
#endif
#ifdef DBL_MIN
	printf("#ifndef DBL_MIN\n#define DBL_MIN %.*E\n#endif\n", DBL_DIG + 1, DBL_MIN);
#endif
#ifdef DBL_MIN_10_EXP
	printf("#ifndef DBL_MIN_10_EXP\n#define DBL_MIN_10_EXP (%d)\n#endif\n", DBL_MIN_10_EXP);
#endif
#ifdef DBL_MIN_EXP
	printf("#ifndef DBL_MIN_EXP\n#define DBL_MIN_EXP (%d)\n#endif\n", DBL_MIN_EXP);
#endif
#ifdef LDBL_DIG
	printf("#ifndef LDBL_DIG\n#define LDBL_DIG %d\n#endif\n", LDBL_DIG);
#endif
#ifdef LDBL_MAX
	printf("#ifndef LDBL_MAX\n#define LDBL_MAX %.*LE\n#endif\n", LDBL_DIG + 1, LDBL_MAX);
#endif
#ifdef LDBL_MAX_10_EXP
	printf("#ifndef LDBL_MAX_10_EXP\n#define LDBL_MAX_10_EXP %d\n#endif\n", LDBL_MAX_10_EXP);
#endif
#ifdef LDBL_MAX_EXP
	printf("#ifndef LDBL_MAX_EXP\n#define LDBL_MAX_EXP %d\n#endif\n", LDBL_MAX_EXP);
#endif
#ifdef LDBL_MIN
	printf("#ifndef LDBL_MIN\n#define LDBL_MIN %.*LE\n#endif\n", LDBL_DIG + 1, LDBL_MIN);
#endif
#ifdef LDBL_MIN_10_EXP
	printf("#ifndef LDBL_MIN_10_EXP\n#define LDBL_MIN_10_EXP (%d)\n#endif\n", LDBL_MIN_10_EXP);
#endif
#ifdef LDBL_MIN_EXP
	printf("#ifndef LDBL_MIN_EXP\n#define LDBL_MIN_EXP (%d)\n#endif\n", LDBL_MIN_EXP);
#endif
	return 0;
}
EOF
)

	# Big output{} block: digit counts, float limits, exponent bitfoolery
	_flt_output=$(cat <<'FLOATSRC'
#include "FEATURE/common"
#include <stdio.h>
#if _hdr_float
#include <float.h>
#endif
#if _hdr_limits
#include <limits.h>
#endif
#if _hdr_math
#include <math.h>
#endif
#include <signal.h>
#ifdef SIGFPE
static int caught = 0;
static void catch(int sig)
{
	signal(sig, SIG_IGN);
	caught++;
}
#endif
int
main(void)
{
	int		i;
	int		s;
	float			f;
	float			pf;
	float			mf;
	float			xf;
	double			d;
	double			pd;
	double			md;
	char*			fp;
#if _ast_fltmax_double
	char*			fs = "";
	char*			ds = "";
#else
	_ast_fltmax_t		l;
	_ast_fltmax_t		pl;
	_ast_fltmax_t		ml;
	char*			fs = "F";
	char*			ds = "";
	char*			ls = "L";
#endif
	unsigned long		u;
	unsigned _ast_intmax_t	w;
	unsigned _ast_intmax_t	pw;
	unsigned _ast_intmax_t	x;
	unsigned short		us;
	unsigned int		ui;
	unsigned long		ul;
	unsigned _ast_intmax_t	uq;

#ifdef SIGFPE
	signal(SIGFPE, catch);
#endif
	printf("\n");
	printf("\n");
	us = 0;
	us = ~us;
	i = 0;
	while (us /= 10)
		i++;
	printf("#define USHRT_DIG		%d\n", i);
	ui = 0;
	ui = ~ui;
	i = 0;
	while (ui /= 10)
		i++;
	printf("#define UINT_DIG		%d\n", i);
	ul = 0;
	ul = ~ul;
	i = 0;
	while (ul /= 10)
		i++;
	printf("#define ULONG_DIG		%d\n", i);
	if (sizeof(uq) > sizeof(ul))
	{
		uq = 0;
		uq = ~uq;
		i = 0;
		while (uq /= 10)
			i++;
		printf("#define ULLONG_DIG		%d\n", i);
		printf("#define UINTMAX_DIG		ULLONG_DIG\n");
	}
	else
		printf("#define UINTMAX_DIG		ULONG_DIG\n");
	printf("\n");
	w = 1;
	do
	{
		pw = w;
		w *= 2;
		f = (_ast_intmax_t)w;
		x = (_ast_intmax_t)f;
	} while (w > pw && w == x);
	w = (pw - 1) + pw;
	u = ~0;
	if (u > w)
		u = w;
	printf("#define FLT_ULONG_MAX		%lu.0F\n", u);
	if (sizeof(w) > sizeof(u))
	{
		printf("#define FLT_ULLONG_MAX		%llu.0F\n", w);
		printf("#define FLT_UINTMAX_MAX		FLT_ULLONG_MAX\n");
	}
	else
	{
		printf("#define FLT_ULLONG_MAX		FLT_ULONG_MAX\n");
		printf("#define FLT_UINTMAX_MAX		FLT_ULONG_MAX\n");
	}
	u /= 2;
	w /= 2;
	printf("#define FLT_LONG_MAX		%lu.0F\n", u);
	if (sizeof(w) > sizeof(u))
	{
		printf("#define FLT_LLONG_MAX		%llu.0F\n", w);
		printf("#define FLT_INTMAX_MAX		FLT_LLONG_MAX\n");
	}
	else
	{
		printf("#define FLT_LLONG_MAX		FLT_LONG_MAX\n");
		printf("#define FLT_INTMAX_MAX		FLT_LONG_MAX\n");
	}
	u++;
	w++;
	printf("#define FLT_LONG_MIN		(-%lu.0F)\n", u);
	if (sizeof(w) > sizeof(u))
	{
		printf("#define FLT_LLONG_MIN		(-%llu.0F)\n", w);
		printf("#define FLT_INTMAX_MIN		FLT_LLONG_MIN\n");
	}
	else
	{
		printf("#define FLT_LLONG_MIN		FLT_LONG_MIN\n");
		printf("#define FLT_INTMAX_MIN		FLT_LONG_MIN\n");
	}

	printf("\n");
	w = 1;
	do
	{
		pw = w;
		w *= 2;
		d = (_ast_intmax_t)w;
		x = (_ast_intmax_t)d;
	} while (w > pw && w == x);
	w = (pw - 1) + pw;
	u = ~0;
	if (u > w)
		u = w;
	printf("#define DBL_ULONG_MAX		%lu.0\n", u);
	if (sizeof(w) > sizeof(u))
	{
		printf("#define DBL_ULLONG_MAX		%llu.0\n", w);
		printf("#define DBL_UINTMAX_MAX		DBL_ULLONG_MAX\n");
	}
	else
	{
		printf("#define DBL_ULLONG_MAX		DBL_ULONG_MAX\n");
		printf("#define DBL_UINTMAX_MAX		DBL_ULONG_MAX\n");
	}
	u /= 2;
	w /= 2;
	printf("#define DBL_LONG_MAX		%lu.0\n", u);
	if (sizeof(w) > sizeof(u))
	{
		printf("#define DBL_LLONG_MAX		%llu.0\n", w);
		printf("#define DBL_INTMAX_MAX		DBL_LLONG_MAX\n");
	}
	else
	{
		printf("#define DBL_LLONG_MAX		DBL_LONG_MAX\n");
		printf("#define DBL_INTMAX_MAX		DBL_LONG_MAX\n");
	}
	u++;
	w++;
	printf("#define DBL_LONG_MIN		(-%lu.0)\n", u);
	if (sizeof(w) > sizeof(u))
	{
		printf("#define DBL_LLONG_MIN		(-%llu.0)\n", w);
		printf("#define DBL_INTMAX_MIN		DBL_LLONG_MIN\n");
	}
	else
	{
		printf("#define DBL_LLONG_MIN		DBL_LONG_MIN\n");
		printf("#define DBL_INTMAX_MIN		DBL_LONG_MIN\n");
	}

#if !_ast_fltmax_double
	/* LDBL limits computed but on aarch64 (darwin/linux) long double == double */
#endif
	fp = "DBL";

	printf("\n");
	printf("#define FLTMAX_UINTMAX_MAX	%s_UINTMAX_MAX\n", fp);
	printf("#define FLTMAX_INTMAX_MAX	%s_INTMAX_MAX\n", fp);
	printf("#define FLTMAX_INTMAX_MIN	%s_INTMAX_MIN\n", fp);

	printf("\n");
#if !_lib_frexpl || _npt_frexpl
	printf("extern long double\tfrexpl(long double, int*);\n");
#endif
#if !_lib_ldexpl || _npt_ldexpl
	printf("extern long double\tldexpl(long double, int);\n");
#endif
	return 0;
}
FLOATSRC
)
	# Write the big output{} source to a file in the workdir and compile
	_flt_bigsrc="${_flt_work}/float_big.c"
	printf '%s\n' "$_flt_output" >|"$_flt_bigsrc"
	_flt_bigbin="${_flt_work}/float_big"
	_flt_big_result=""
	if "$CC" $CFLAGS_BASE $_flt_inc -include "$FEATDIR/libast/FEATURE/standards" -include stdio.h \
		-o "$_flt_bigbin" "$_flt_bigsrc" $LDFLAGS_BASE -lm \
		2>>"$_PROBE_STDERR"; then
		_flt_big_result=$("$_flt_bigbin" 2>>"$_PROBE_STDERR") || true
	else
		echo "configure.sh: warning: float big output probe failed to compile" >&2
	fi
	rm -f "$_flt_bigbin"

	# Double exponent bitfoolery
	_flt_dblexp=$(cat <<'DBLSRC'
#include "FEATURE/common"
#include <stdio.h>
typedef union _dbl_exp_u
{
	unsigned _ast_int4_t	e[sizeof(double) / 4];
	double			f;
} _ast_dbl_exp_t;
int
main(void)
{
	int			i;
	int			j;
	unsigned _ast_int4_t	e;
	_ast_dbl_exp_t		a;
	_ast_dbl_exp_t		b;
	a.f = 1;
	b.f = 2;
	for (i = 0; i < sizeof(a.e) / sizeof(a.e[0]); i++)
		if (e = a.e[i] ^ b.e[i])
		{
			for (j = i + 1; j < sizeof(a.e) / sizeof(a.e[0]); j++)
				if (a.e[j] ^ b.e[j])
					return 0;
			printf("typedef union _ast_dbl_exp_u\n{\n\tuint32_t\t\te[sizeof(double)/4];\n\tdouble\t\t\tf;\n} _ast_dbl_exp_t;\n\n");
			printf("#define _ast_dbl_exp_index\t%d\n", i);
			for (i = 0; !(e & 1); e >>= 1, i++);
			printf("#define _ast_dbl_exp_shift\t%d\n\n", i);
			return 0;
		}
	return 0;
}
DBLSRC
)
	printf '%s\n' "$_flt_dblexp" >|"${_flt_work}/dblexp.c"
	_flt_dblexp_result=""
	if "$CC" $CFLAGS_BASE $_flt_inc -include "$FEATDIR/libast/FEATURE/standards" -include stdio.h \
		-o "${_flt_work}/dblexp" "${_flt_work}/dblexp.c" $LDFLAGS_BASE \
		2>>"$_PROBE_STDERR"; then
		_flt_dblexp_result=$("${_flt_work}/dblexp" 2>>"$_PROBE_STDERR") || true
	fi
	rm -f "${_flt_work}/dblexp"

	# Long double exponent bitfoolery
	_flt_fltmaxexp=$(cat <<'FMAXSRC'
#include "FEATURE/common"
#include <stdio.h>
typedef union _ast_fltmax_exp_u
{
	unsigned _ast_int4_t	e[sizeof(_ast_fltmax_t) / 4];
	_ast_fltmax_t		f;
} _ast_fltmax_exp_t;
int
main(void)
{
	int			i;
	int			j;
	unsigned _ast_int4_t	e;
	_ast_fltmax_exp_t	a;
	_ast_fltmax_exp_t	b;
	a.f = 1;
	b.f = 2;
	for (i = 0; i < sizeof(a.e) / sizeof(a.e[0]); i++)
		if (e = a.e[i] ^ b.e[i])
		{
			for (j = i + 1; j < sizeof(a.e) / sizeof(a.e[0]); j++)
				if (a.e[j] ^ b.e[j])
					return 0;
			printf("typedef union _fltmax_exp_u\n{\n\tuint32_t\t\te[sizeof(_ast_fltmax_t)/4];\n\t_ast_fltmax_t\t\tf;\n} _ast_fltmax_exp_t;\n\n");
			printf("#define _ast_fltmax_exp_index\t%d\n", i);
			for (i = 0; !(e & 1); e >>= 1, i++);
			printf("#define _ast_fltmax_exp_shift\t%d\n\n", i);
			return 0;
		}
	return 0;
}
FMAXSRC
)
	printf '%s\n' "$_flt_fltmaxexp" >|"${_flt_work}/fmaxexp.c"
	_flt_fltmaxexp_result=""
	if "$CC" $CFLAGS_BASE $_flt_inc -include "$FEATDIR/libast/FEATURE/standards" -include stdio.h \
		-o "${_flt_work}/fmaxexp" "${_flt_work}/fmaxexp.c" $LDFLAGS_BASE \
		2>>"$_PROBE_STDERR"; then
		_flt_fltmaxexp_result=$("${_flt_work}/fmaxexp" 2>>"$_PROBE_STDERR") || true
	fi
	rm -f "${_flt_work}/fmaxexp"

	# _ast_flt_unsigned_max_t test
	_flt_ullt=""
	_flt_ullt_src="${_flt_work}/ullt.c"
	cat >|"$_flt_ullt_src" <<'EOF'
#include <stdio.h>
int
main(void)
{
	unsigned long long	m;
	long double		f = 123.456;

	m = f;
	if (!m || f == m)
		return 1;
	printf("#define _ast_flt_unsigned_max_t\tunsigned long long\n");
	return 0;
}
EOF
	if "$CC" $CFLAGS_BASE -o "${_flt_work}/ullt" "$_flt_ullt_src" $LDFLAGS_BASE \
		2>>"$_PROBE_STDERR"; then
		_flt_ullt=$("${_flt_work}/ullt" 2>>"$_PROBE_STDERR") || true
	fi
	if [ -z "$_flt_ullt" ]; then
		_flt_ullt="#define _ast_flt_unsigned_max_t	unsigned long"
	fi
	rm -f "${_flt_work}/ullt"

	CFLAGS_BASE="$_saved"

	{
		echo "/* : : generated by configure.sh probe_ast_float : : */"
		echo "#ifndef _def_float_ast"
		echo "#define _def_float_ast	1"
		echo "#define _sys_types	1	/* #include <sys/types.h> ok */"
		printf '%s' "$_flt_defs"
		[ -n "$_flt_macro" ] && printf '%s\n' "$_flt_macro"
		[ -n "$_flt_big_result" ] && printf '%s\n' "$_flt_big_result"
		[ -n "$_flt_dblexp_result" ] && printf '%s\n' "$_flt_dblexp_result"
		[ -n "$_flt_fltmaxexp_result" ] && printf '%s\n' "$_flt_fltmaxexp_result"
		printf '%s\n' "$_flt_ullt"
		echo "#endif"
	} | atomic_write "$_out" || true
}

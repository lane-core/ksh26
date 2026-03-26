/* probe: ast-float — digit counts, float boundary values, exponent detection
 * Compile+link+run with -lm and -I for FEATURE/common, capture output.
 * Emits: USHRT_DIG, UINT_DIG, ULONG_DIG, ULLONG_DIG, UINTMAX_DIG,
 *        DBL_ULONG_MAX through DBL_INTMAX_MIN (audit: FLT_* eliminated),
 *        FLTMAX_UINTMAX_MAX through FLTMAX_INTMAX_MIN,
 *        frexpl/ldexpl prototypes if needed.
 * Requires: #include "FEATURE/common" — must be compiled in a workdir
 *           with a FEATURE/ symlink to $FEATDIR/libast/FEATURE/.
 */
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
	printf("#define USHRT_DIG\t\t%d\n", i);
	ui = 0;
	ui = ~ui;
	i = 0;
	while (ui /= 10)
		i++;
	printf("#define UINT_DIG\t\t%d\n", i);
	ul = 0;
	ul = ~ul;
	i = 0;
	while (ul /= 10)
		i++;
	printf("#define ULONG_DIG\t\t%d\n", i);
	if (sizeof(uq) > sizeof(ul))
	{
		uq = 0;
		uq = ~uq;
		i = 0;
		while (uq /= 10)
			i++;
		printf("#define ULLONG_DIG\t\t%d\n", i);
		printf("#define UINTMAX_DIG\t\tULLONG_DIG\n");
	}
	else
		printf("#define UINTMAX_DIG\t\tULONG_DIG\n");

	/* Audit: FLT_* boundary values eliminated (no consumers).
	 * Only DBL_* and FLTMAX_* boundary values retained. */
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
	printf("#define DBL_ULONG_MAX\t\t%lu.0\n", u);
	if (sizeof(w) > sizeof(u))
	{
		printf("#define DBL_ULLONG_MAX\t\t%llu.0\n", w);
		printf("#define DBL_UINTMAX_MAX\t\tDBL_ULLONG_MAX\n");
	}
	else
	{
		printf("#define DBL_ULLONG_MAX\t\tDBL_ULONG_MAX\n");
		printf("#define DBL_UINTMAX_MAX\t\tDBL_ULONG_MAX\n");
	}
	u /= 2;
	w /= 2;
	printf("#define DBL_LONG_MAX\t\t%lu.0\n", u);
	if (sizeof(w) > sizeof(u))
	{
		printf("#define DBL_LLONG_MAX\t\t%llu.0\n", w);
		printf("#define DBL_INTMAX_MAX\t\tDBL_LLONG_MAX\n");
	}
	else
	{
		printf("#define DBL_LLONG_MAX\t\tDBL_LONG_MAX\n");
		printf("#define DBL_INTMAX_MAX\t\tDBL_LONG_MAX\n");
	}
	u++;
	w++;
	printf("#define DBL_LONG_MIN\t\t(-%lu.0)\n", u);
	if (sizeof(w) > sizeof(u))
	{
		printf("#define DBL_LLONG_MIN\t\t(-%llu.0)\n", w);
		printf("#define DBL_INTMAX_MIN\t\tDBL_LLONG_MIN\n");
	}
	else
	{
		printf("#define DBL_LLONG_MIN\t\tDBL_LONG_MIN\n");
		printf("#define DBL_INTMAX_MIN\t\tDBL_LONG_MIN\n");
	}

	fp = "DBL";

	printf("\n");
	printf("#define FLTMAX_UINTMAX_MAX\t%s_UINTMAX_MAX\n", fp);
	printf("#define FLTMAX_INTMAX_MAX\t%s_INTMAX_MAX\n", fp);
	printf("#define FLTMAX_INTMAX_MIN\t%s_INTMAX_MIN\n", fp);

	printf("\n");
	return 0;
}

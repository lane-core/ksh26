/* probe: ast-float — extract FLT, DBL, LDBL limits from system headers
 * Compile+link+run with -lm, capture output.
 * Emits: #ifndef FLT_DIG / #define FLT_DIG N / #endif blocks for
 *        all standard float/double/long-double limits.
 */
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

/* probe: ast-float — fltmax (long double) exponent bit position detection
 * Compile+link+run, capture output.
 * Emits: _ast_fltmax_exp_t typedef, _ast_fltmax_exp_index, _ast_fltmax_exp_shift
 * Requires: #include "FEATURE/common" (workdir with FEATURE/ symlink)
 */
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

/* probe: ast-float — double exponent bit position detection
 * Compile+link+run, capture output.
 * Emits: _ast_dbl_exp_t typedef, _ast_dbl_exp_index, _ast_dbl_exp_shift
 * Requires: #include "FEATURE/common" (workdir with FEATURE/ symlink)
 */
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

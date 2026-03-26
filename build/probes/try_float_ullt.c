/* probe: ast-float — unsigned long long ↔ long double conversion test
 * Compile+link+run, capture output.
 * Emits: _ast_flt_unsigned_max_t (unsigned long long or unsigned long)
 */
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

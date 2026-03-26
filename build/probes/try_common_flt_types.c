/* probe: ast-common — float type sizing
 * Compile+link+run, capture output.
 * Emits: _ast_flt{4,8}_t, _ast_fltmax_t, _ast_fltmax_double
 */
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

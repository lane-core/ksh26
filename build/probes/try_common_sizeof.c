/* probe: ast-common — sizeof types
 * Compile+link+run, capture output.
 * Emits: _ast_sizeof_{short,int,long,size_t,pointer,float,double,long_double}
 * Audit: only _ast_sizeof_long and _ast_sizeof_pointer have consumers.
 * All emitted for completeness (harmless, no compile cost).
 */
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#define elementsof(x) (sizeof(x)/sizeof(x[0]))
static struct { char* name; int size; } types[] = {
	"short", sizeof(short),
	"int", sizeof(int),
	"long", sizeof(long),
	"size_t", sizeof(size_t),
	"pointer", sizeof(void*),
	"float", sizeof(float),
	"double", sizeof(double),
	"long_double", sizeof(long double),
};
int main(void) {
	int t;
	for (t = 0; t < elementsof(types); t++)
		printf("#define _ast_sizeof_%s%s\t%d\t/* sizeof(%s) */\n",
			types[t].name,
			strlen(types[t].name) < 4 ? "\t" : "",
			types[t].size, types[t].name);
	printf("\n");
	return 0;
}

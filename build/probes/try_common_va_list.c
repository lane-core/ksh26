/* probe: ast-common — va_list representation
 * Compile+link+run, capture output.
 * Emits: va_listref, va_listval, va_listarg macros
 * On C23 compilers, the first variant (direct *ap++ dereference) succeeds.
 */
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

/* probe: ast-sfio — pointer width in bits (compile+link+run, capture output) */
#include <stdio.h>
int main(void)
{
	printf("#define _ptr_bits\t%d\n", (int)(sizeof(char*) * 8));
	return 0;
}

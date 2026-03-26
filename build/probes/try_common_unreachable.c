/* probe: ast-common — __builtin_unreachable() and UNREACHABLE() macro
 * Compile+link+run, capture output.
 * On release builds: UNREACHABLE() → __builtin_unreachable()
 * On debug builds: UNREACHABLE() → abort()
 * Requires: -D_AST_release=0 or -D_AST_release=1 via probe_defs.h
 */
#include <stdio.h>
#include <stdlib.h>
void testfn(int n)
{
	switch (n) {
	case 0: __builtin_unreachable();
	default:
#if _AST_release
		printf("#define UNREACHABLE()\t__builtin_unreachable()\n");
#else
		printf("#define UNREACHABLE()\tabort()\n");
#endif
	}
}
int main(int argc, char *argv[]) { testfn(argc); return 0; }

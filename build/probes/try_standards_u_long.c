/* probe: ast-standards — u_long type availability (compile-only) */
#include <sys/types.h>
static u_long _i;
int n = sizeof(_i);

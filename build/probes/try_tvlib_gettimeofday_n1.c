/* probe: ast-tvlib — gettimeofday variant 1: two-arg with timezone struct visible */
#include <stdio.h>
#include <sys/types.h>
#include <sys/time.h>
int main(void)
{
	struct timeval	tv;
	struct timezone	tz;
	if (gettimeofday(&tv, NULL) < 0)
		return 1;
	printf("#define tmgettimeofday(p)\tgettimeofday(p,NULL)\n");
#if _lib_settimeofday
	printf("#define tmsettimeofday(p)\tsettimeofday(p,NULL)\n");
#endif
	return 0;
}

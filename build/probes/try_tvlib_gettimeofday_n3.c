/* probe: ast-tvlib — gettimeofday variant 3: one-arg (legacy) */
#include <stdio.h>
#include <sys/types.h>
#include <sys/time.h>
int main(void)
{
	struct timeval	tv;
	if (gettimeofday(&tv) < 0)
		return 1;
	printf("#define tmgettimeofday(p)\tgettimeofday(p)\n");
#if _lib_settimeofday
	printf("#define tmsettimeofday(p)\tsettimeofday(p)\n");
#endif
	return 0;
}

/* probe: ast-tvlib — clock_gettime runtime test (compile+link+run) */
#include <time.h>
int main(void)
{
	struct timespec	tv;
	return clock_gettime(CLOCK_REALTIME, &tv) != 0;
}

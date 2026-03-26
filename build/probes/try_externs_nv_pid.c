#include <sys/types.h>
#include <stdint.h>
#include <stdio.h>
int main(void) {
	if (sizeof(pid_t) == sizeof(int16_t))
		printf("#define NV_PID\t(NV_INTEGER|NV_SHORT)\n");
	else if (sizeof(pid_t) == sizeof(int32_t))
		printf("#define NV_PID\t(NV_INTEGER)\n");
	else if (sizeof(pid_t) == 8)
		printf("#define NV_PID\t(NV_INTEGER|NV_LONG)\n");
	return 0;
}

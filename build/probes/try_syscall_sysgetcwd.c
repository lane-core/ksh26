/* probe: ast-syscall — SYS_getcwd syscall (compile+link) */
#include <sys/syscall.h>
#include <unistd.h>
int main(void)
{
	char	buf[256];
	return syscall(SYS_getcwd, buf, sizeof(buf)) < 0;
}

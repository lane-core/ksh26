/* probe: libcmd-symlink — lchmod runtime errno test (compile+link+run) */
#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>
int main(void)
{
	lchmod("No-FiLe", 0);
	return errno != ENOENT;
}

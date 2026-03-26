/* probe: libcmd-symlink — lchown runtime errno test (compile+link+run) */
#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>
int main(void)
{
	lchown("No-FiLe", 0, 0);
	return errno != ENOENT;
}

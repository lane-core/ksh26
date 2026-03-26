/* probe: ast-tvlib — utimensat with UTIME_NOW/UTIME_OMIT (compile+link) */
#include <fcntl.h>
#include <sys/stat.h>
static struct timespec	ts[2];
int main(void)
{
	ts[0].tv_nsec = UTIME_NOW;
	ts[1].tv_nsec = UTIME_OMIT;
	return utimensat(AT_FDCWD, ".", ts, AT_SYMLINK_NOFOLLOW) != 0;
}

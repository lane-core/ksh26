/* probe: ast-asometh — fcntl file locking (compile+link) */
#include <sys/types.h>
#include <unistd.h>
#include <fcntl.h>
int main(void)
{
	struct flock	lock;
	lock.l_type = F_WRLCK;
	lock.l_whence = SEEK_SET;
	lock.l_start = 0;
	lock.l_len = 1;
	return fcntl(1, F_SETLKW, &lock) < 0;
}

/* probe: ast-lib — poll() POSIX compliance test (compile+link+run) */
#include <poll.h>
#include <unistd.h>
extern int pipe(int*);
int main(void) {
	int rw[2];
	struct pollfd fd;
	if (pipe(rw) < 0) return 1;
	fd.fd = rw[0]; fd.events = POLLIN; fd.revents = 0;
	if (poll(&fd, 1, 0) < 0 || fd.revents != 0) return 1;
	if (write(rw[1], "x", 1) != 1) return 1;
	if (poll(&fd, 1, 0) < 0 || fd.revents == 0) return 1;
	return 0;
}

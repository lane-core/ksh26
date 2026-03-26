#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/socket.h>
int main(void) {
	int n, sfd[2];
	close(0);
	open("/dev/null", O_RDONLY);
	if ((n = open("/dev/fd/0", O_RDONLY)) < 0) return 1;
	close(n);
	if (socketpair(AF_UNIX, SOCK_STREAM, 0, sfd) < 0 ||
	    shutdown(sfd[0], 1) < 0 || shutdown(sfd[1], 0) < 0) return 1;
	close(0);
	dup(sfd[0]);
	close(sfd[0]);
	if ((n = open("/dev/fd/0", O_RDONLY)) < 0) return 1;
	return 0;
}

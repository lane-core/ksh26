/* probe: ast-lib — recv(MSG_PEEK) on socketpair (compile+link+run) */
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
int main(void) {
	int i, fds[2];
	char buf[128];
	static char msg[] = "abcd";
	if (socketpair(AF_UNIX, SOCK_STREAM, 0, fds)) return 1;
	if (write(fds[1], msg, sizeof(msg)) != sizeof(msg)) return 1;
	if (recv(fds[0], buf, sizeof(buf), MSG_PEEK) != sizeof(msg)) return 1;
	for (i = 0; i < sizeof(msg); i++) if (buf[i] != msg[i]) return 1;
	if (read(fds[0], buf, sizeof(msg)) != sizeof(msg)) return 1;
	for (i = 0; i < sizeof(msg); i++) if (buf[i] != msg[i]) return 1;
	return 0;
}

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/wait.h>
#ifndef SHUT_RD
#define SHUT_RD		0
#endif
#ifndef SHUT_WR
#define SHUT_WR		1
#endif
static void handler(int sig) { _exit(0); }
int main(void) {
	int sfd[2];
	char buf[256];
	pid_t pid;
	static char msg[] = "hello world\n";
	if (socketpair(AF_UNIX, SOCK_STREAM, 0, sfd) < 0 ||
	    shutdown(sfd[1], SHUT_RD) < 0 ||
	    shutdown(sfd[0], SHUT_WR) < 0)
		return 1;
	if ((pid = fork()) < 0)
		return 1;
	if (pid) {
		int n;
		close(sfd[1]);
		wait(&n);
		if (recv(sfd[0], buf, sizeof(buf), MSG_PEEK) < 0)
			return 1;
		close(sfd[0]);
		signal(SIGPIPE, handler);
		if (socketpair(AF_UNIX, SOCK_STREAM, 0, sfd) < 0 ||
		    shutdown(sfd[1], SHUT_RD) < 0 ||
		    shutdown(sfd[0], SHUT_WR) < 0)
			return 1;
		close(sfd[0]);
		write(sfd[1], msg, sizeof(msg) - 1);
		return 1;
	} else {
		close(sfd[0]);
		write(sfd[1], msg, sizeof(msg) - 1);
		return 0;
	}
}

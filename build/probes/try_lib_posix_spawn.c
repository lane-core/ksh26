/* probe: ast-lib — posix_spawn() correctness test (compile+link+run)
 * Exit code IS the define value: 0=absent, 1=works, 2=works+ENOEXEC
 * Overrides fork() to ensure posix_spawn doesn't fall back to fork.
 * Compile with -Dfork=______fork to suppress the override collision. */
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <spawn.h>
#include <signal.h>
#include <fcntl.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#define NOTE(x)
#undef fork
pid_t fork(void) { NOTE("uses fork()"); return -1; }
pid_t _fork(void) { NOTE("uses _fork()"); return -1; }
pid_t __fork(void) { NOTE("uses __fork()"); return -1; }
int main(int argc, char **argv) {
	char *s;
	pid_t pid;
	posix_spawnattr_t attr;
	int n, status;
	char *cmd[3];
	char tmp[1024];
	if (argv[1]) _exit(signal(SIGHUP, SIG_DFL) != SIG_IGN);
	signal(SIGHUP, SIG_IGN);
	if (posix_spawnattr_init(&attr)) _exit(0);
	if (posix_spawnattr_setpgroup(&attr, 0)) _exit(0);
	if (posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP)) _exit(0);
	cmd[0] = argv[0]; cmd[1] = "test"; cmd[2] = 0;
	if (posix_spawn(&pid, cmd[0], 0, &attr, cmd, 0)) _exit(0);
	status = 1;
	if (wait(&status) < 0) _exit(0);
	if (status != 0) _exit(0);
	n = strlen(cmd[0]);
	if (n >= (sizeof(tmp) - 3)) _exit(0);
	strcpy(tmp, cmd[0]);
	tmp[n] = '.'; tmp[n+1] = 's'; tmp[n+2] = 'h'; tmp[n+3] = 0;
	if ((n = open(tmp, O_CREAT|O_WRONLY, S_IRWXU|S_IRWXG|S_IRWXO)) < 0 ||
	    chmod(tmp, S_IRWXU|S_IRWXG|S_IRWXO) < 0 ||
	    write(n, "exit 99\n", 8) != 8 || close(n) < 0) _exit(0);
	cmd[0] = tmp;
	n = 0;
	pid = -1;
	if (posix_spawn(&pid, cmd[0], 0, &attr, cmd, 0)) {
		n = 2;
	} else if (pid == -1) {
		;
	} else if (wait(&status) != pid) {
		;
	} else if (!WIFEXITED(status)) {
		;
	} else {
		status = WEXITSTATUS(status);
		if (status == 127) n = 1;
	}
	unlink(tmp);
	_exit(n);
}

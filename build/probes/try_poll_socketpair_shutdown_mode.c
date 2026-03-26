#include <sys/types.h>
#include <sys/stat.h>
#include <sys/socket.h>
int main(void) {
	int sfd[2];
	struct stat st0, st1;
	if (socketpair(AF_UNIX, SOCK_STREAM, 0, sfd) < 0 ||
	    shutdown(sfd[0], 1) < 0 || shutdown(sfd[1], 0) < 0) return 1;
	if (fstat(sfd[0], &st0) < 0 || fstat(sfd[1], &st1) < 0) return 1;
	if ((st0.st_mode & (S_IRUSR|S_IWUSR)) == S_IRUSR &&
	    (st1.st_mode & (S_IRUSR|S_IWUSR)) == S_IWUSR) return 1;
	if (fchmod(sfd[0], S_IRUSR) < 0 || fstat(sfd[0], &st0) < 0 ||
	    (st0.st_mode & (S_IRUSR|S_IWUSR)) != S_IRUSR) return 1;
	if (fchmod(sfd[1], S_IWUSR) < 0 || fstat(sfd[1], &st1) < 0 ||
	    (st1.st_mode & (S_IRUSR|S_IWUSR)) != S_IWUSR) return 1;
	return 0;
}

/* probe: ast-lib — select() standard 5-arg interface (compile+link) */
#include <sys/types.h>
#include <sys/time.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <string.h>
int main(void) {
	struct timeval tmb;
	fd_set rd;
	FD_ZERO(&rd); FD_SET(0,&rd);
	tmb.tv_sec = 0; tmb.tv_usec = 0;
	select(1,&rd,NULL,NULL,&tmb);
	return 0;
}

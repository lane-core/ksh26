/* probe: pty — detect ptmx clone device and first legacy pty path
 * Compile+link+run, capture output.
 * Emits: _pty_clone "/dev/ptmx" and _pty_first "/dev/ptyp0" (or variants)
 */
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <stdio.h>
int main(void)
{
	int		i;
	struct stat	statb;
	static char*	pty[] = { "/dev/ptyp0000", "/dev/ptym/ptyp0", "/dev/ptyp0" };
	int		fd;
	static char*	ptc[] = { "/dev/ptmx", "/dev/ptc", "/dev/ptmx_bsd" };
	for (i = 0; i < sizeof(ptc) / sizeof(ptc[0]); i++)
		if((fd = open(ptc[i], 2))>=0)
		{
			if (ptsname(fd))
			{
				printf("#define _pty_clone\t\"%s\"\n", ptc[i]);
				close(fd);
				break;
			}
			close(fd);
		}
	for (i = 0;; i++)
		if(i >= (sizeof(pty) / sizeof(pty[0]) - 1) || stat(pty[i], &statb)>=0)
		{
			printf("#define _pty_first\t\"%s\"\n", pty[i]);
			break;
		}
	return 0;
}

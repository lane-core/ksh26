/*
 * standalone entry point for the pty command
 */

#include <shcmd.h>

extern int b_pty(int, char **, Shbltin_t *);

int
main(int argc, char **argv)
{
	return b_pty(argc, argv, 0);
}

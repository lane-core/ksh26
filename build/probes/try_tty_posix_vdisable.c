/* probe: ast-tty — _POSIX_VDISABLE macro presence (compile-only) */
#include <termios.h>
#ifndef _POSIX_VDISABLE
#error _POSIX_VDISABLE not defined
#endif
int x = _POSIX_VDISABLE;

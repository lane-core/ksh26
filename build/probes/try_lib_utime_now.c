/* probe: ast-lib — utime() with NULL time vector (compile+link+run) */
#include <sys/types.h>
extern int utime(const char*, void*);
int main(void) { return utime(".", (void*)0) == -1; }

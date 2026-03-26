	_execvedir_defs=$(probe_output <<'EOF'
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
extern char **environ;
int main(int argc, char *argv[])
{
	char	dirname[64];
	int	e;
	sprintf(dirname,".dir.%u",(unsigned int)getpid());
	mkdir(dirname,0777);
	execve(dirname,argv,environ);
	e = errno;
	rmdir(dirname);
	return !(e == ENOEXEC);
}
EOF

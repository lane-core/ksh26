	_execve_defs=$(probe_output <<'EOF'
#include <string.h>
#include <unistd.h>
#include <stdio.h>
extern char **environ;
int main(int argc, char *argv[])
{
	char *orig0 = argv[0], *newenv[2], b[64];
	int i;
	sprintf(b,"_KSH_EXECVE_TEST_%d=y",(int)getpid());
	newenv[0] = b;
	newenv[1] = NULL;
	for (i = 0; environ[i]; i++)
		if (strcmp(environ[i],newenv[0])==0)
			return !(strcmp(argv[0],"TEST_OK")!=0);
	argv[0] = "TEST_OK";
	execve(orig0,argv,newenv);
	return 128;
}
EOF

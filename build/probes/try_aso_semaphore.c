/* probe: ast-asometh — SysV semaphores (compile+link) */
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/ipc.h>
#include <sys/sem.h>
int main(void)
{
	int		id;
	struct sembuf	sem;
	if ((id = semget(IPC_PRIVATE, 16, IPC_CREAT|IPC_EXCL|S_IRUSR|S_IWUSR)) < 0)
		return 1;
	sem.sem_num = 0;
	sem.sem_op = 1;
	sem.sem_flg = 0;
	if (semop(id, &sem, 1) < 0)
		return 1;
	if (semctl(id, 0, IPC_RMID) < 0)
		return 1;
	return 0;
}

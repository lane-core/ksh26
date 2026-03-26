#include <stdio.h>
#ifndef FILENAME_MAX
#ifndef NAME_MAX
#ifndef _POSIX_NAME_MAX
#define _POSIX_NAME_MAX	14
#endif
#define NAME_MAX	_POSIX_NAME_MAX
#endif
#define FILENAME_MAX	NAME_MAX
#endif
#ifndef FOPEN_MAX
#ifdef STREAM_MAX
#define FOPEN_MAX	STREAM_MAX
#else
#ifndef OPEN_MAX
#ifndef _POSIX_OPEN_MAX
#define _POSIX_OPEN_MAX	20
#endif
#define OPEN_MAX	_POSIX_OPEN_MAX
#endif
#define FOPEN_MAX	OPEN_MAX
#endif
#endif
#ifndef TMP_MAX
#define TMP_MAX		33520641
#endif
int
main(void)
{
	printf("#ifndef FILENAME_MAX\n");
	printf("#define FILENAME_MAX	%d\n", FILENAME_MAX);
	printf("#endif\n");
	printf("#ifndef FOPEN_MAX\n");
	printf("#define FOPEN_MAX	%d\n", FOPEN_MAX);
	printf("#endif\n");
	printf("#ifndef TMP_MAX\n");
	printf("#define TMP_MAX		%d\n", TMP_MAX);
	printf("#endif\n");
	printf("\n");
	printf("#define _doprnt		_ast_doprnt\n");
	printf("#define _doscan		_ast_doscan\n");
	printf("#define asprintf	_ast_asprintf\n");
	printf("#define clearerr	_ast_clearerr\n");
	printf("#define fclose		_ast_fclose\n");
	printf("#define fdopen		_ast_fdopen\n");
	printf("#define fflush		_ast_fflush\n");
	printf("#define fgetc		_ast_fgetc\n");
	printf("#define fgetpos		_ast_fgetpos\n");
	printf("#define fgets		_ast_fgets\n");
	printf("#define fopen		_ast_fopen\n");
	printf("#define fprintf		_ast_fprintf\n");
	printf("#define fpurge		_ast_fpurge\n");
	printf("#define fputs		_ast_fputs\n");
	printf("#define fread		_ast_fread\n");
	printf("#define freopen		_ast_freopen\n");
	printf("#define fscanf		_ast_fscanf\n");
	printf("#define fseek		_ast_fseek\n");
	printf("#define fseeko		_ast_fseeko\n");
	printf("#define fsetpos		_ast_fsetpos\n");
	printf("#define ftell		_ast_ftell\n");
	printf("#define ftello		_ast_ftello\n");
	printf("#define fwrite		_ast_fwrite\n");
	printf("#define gets		_ast_gets\n");
	printf("#define getw		_ast_getw\n");
	printf("#define pclose		_ast_pclose\n");
	printf("#define popen		_ast_popen\n");
	printf("#define printf		_ast_printf\n");
	printf("#define puts		_ast_puts\n");
	printf("#define putw		_ast_putw\n");
	printf("#define rewind		_ast_rewind\n");
	printf("#define scanf		_ast_scanf\n");
	printf("#define setbuf		_ast_setbuf\n");
	printf("#undef	setbuffer\n");
	printf("#define setbuffer	_ast_setbuffer\n");
	printf("#define setlinebuf	_ast_setlinebuf\n");
	printf("#define setvbuf		_ast_setvbuf\n");
	printf("#define snprintf	_ast_snprintf\n");
	printf("#define sprintf		_ast_sprintf\n");
	printf("#define sscanf		_ast_sscanf\n");
	printf("#define tmpfile		_ast_tmpfile\n");
	printf("#define ungetc		_ast_ungetc\n");
	printf("#define vasprintf	_ast_vasprintf\n");
	printf("#define vfprintf	_ast_vfprintf\n");
	printf("#define vfscanf		_ast_vfscanf\n");
	printf("#define vprintf		_ast_vprintf\n");
	printf("#define vscanf		_ast_vscanf\n");
	printf("#define vsnprintf	_ast_vsnprintf\n");
	printf("#define vsprintf	_ast_vsprintf\n");
	printf("#define vsscanf		_ast_vsscanf\n");

	printf("#define fcloseall	_ast_fcloseall\n");
	printf("#define _filbuf		_ast__filbuf\n");
	printf("#define fmemopen	_ast_fmemopen\n");
	printf("#define __getdelim	_ast___getdelim\n");
	printf("#define getdelim	_ast_getdelim\n");
	printf("#define getline		_ast_getline\n");

	printf("#define clearerr_unlocked _ast_clearerr_unlocked\n");
	printf("#define feof_unlocked	_ast_feof_unlocked\n");
	printf("#define ferror_unlocked	_ast_ferror_unlocked\n");
	printf("#define fflush_unlocked	_ast_fflush_unlocked\n");
	printf("#define fgetc_unlocked	_ast_fgetc_unlocked\n");
	printf("#define fgets_unlocked	_ast_fgets_unlocked\n");
	printf("#define fileno_unlocked	_ast_fileno_unlocked\n");
	printf("#define fputc_unlocked	_ast_fputc_unlocked\n");
	printf("#define fputs_unlocked	_ast_fputs_unlocked\n");
	printf("#define fread_unlocked	_ast_fread_unlocked\n");
	printf("#define fwrite_unlocked	_ast_fwrite_unlocked\n");
	printf("#define getc_unlocked	_ast_getc_unlocked\n");
	printf("#define getchar_unlocked _ast_getchar_unlocked\n");
	printf("#define putc_unlocked	_ast_putc_unlocked\n");
	printf("#define putchar_unlocked _ast_putchar_unlocked\n");

	printf("\n");
	return 0;
}

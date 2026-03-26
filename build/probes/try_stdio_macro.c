/* probe: ast-stdio — P_tmpdir, L_ctermid, L_tmpnam extraction
 * Compile+link+run, capture output.
 */
#include <stdio.h>
int
main(void)
{
#ifndef P_tmpdir
#define P_tmpdir "/var/tmp/"
#endif
	printf("#ifndef P_tmpdir\n");
	printf("#define P_tmpdir %s /*NOCATLITERAL*/\n", P_tmpdir);
	printf("#endif\n");
	printf("#ifndef L_ctermid\n");
#ifndef L_ctermid
#define L_ctermid 9
#endif
	printf("#define L_ctermid %d\n", L_ctermid);
	printf("#endif\n");
	printf("#ifndef L_tmpnam\n");
#ifndef L_tmpnam
#define L_tmpnam (sizeof(P_tmpdir)+15)
#endif
	printf("#define L_tmpnam %d\n", L_tmpnam);
	printf("#endif\n");
	return 0;
}

/* probe: ast-iconv — TSTEOF type/macro definitions
 * Compile+link+run, capture output.
 * Requires: -D_hdr_iconv=0|1 -D_lib_iconv_open=0|1
 *           -I for FEATURE/ (workdir with symlink)
 * Audit: _nxt_iconv eliminated — native iconv.h include path removed
 */
#include <stdio.h>
#include <string.h>
#if _hdr_iconv
#include <sys/types.h>
#include <iconv.h>
#endif

int
main(void)
{
	char*	lib;

	printf("#include <ast_common.h>\n");
	printf("#include <ccode.h>\n");
	printf("\n");
	printf("#define ICONV_VERSION\t\t20110111L\n");
	printf("\n");
	printf("#define ICONV_FATAL\t\t0x02\n");
	printf("#define ICONV_OMIT\t\t0x04\n");
	printf("\n");
	printf("#define CC_ICONV\t\t(-1)\n");
	printf("#define CC_UCS\t\t\t(-2)\n");
	printf("#define CC_SCU\t\t\t(-3)\n");
	printf("#define CC_UTF\t\t\t(-4)\n");
	printf("#define CC_UME\t\t\t(-5)\n");
	printf("\n");
#if _lib_iconv_open
	lib = "_ast_";
	printf("#ifndef _ICONV_LIST_PRIVATE_\n");
	printf("#undef\ticonv_t\n");
	printf("#define\ticonv_t\t\t%siconv_t\n", lib);
	printf("#undef\ticonv_f\n");
	printf("#define\ticonv_f\t\t%siconv_f\n", lib);
	printf("#undef\ticonv_list_t\n");
	printf("#define\ticonv_list_t\t%siconv_list_t\n", lib);
	printf("#undef\ticonv_open\n");
	printf("#define iconv_open\t%siconv_open\n", lib);
	printf("#undef\ticonv\n");
	printf("#define\ticonv\t\t%siconv\n", lib);
	printf("#undef\ticonv_close\n");
	printf("#define iconv_close\t%siconv_close\n", lib);
	printf("#undef\ticonv_list\n");
	printf("#define iconv_list\t%siconv_list\n", lib);
	printf("#undef\ticonv_move\n");
	printf("#define iconv_move\t%siconv_move\n", lib);
	printf("#undef\ticonv_name\n");
	printf("#define iconv_name\t%siconv_name\n", lib);
	printf("#undef\ticonv_write\n");
	printf("#define iconv_write\t%siconv_write\n", lib);
	printf("#endif\n");
#else
	lib = "";
#endif
	printf("\n");
	printf("typedef int (*Iconv_error_f)(void*, void*, int, ...);\n");
	printf("\n");
	printf("typedef struct Iconv_disc_s\n");
	printf("{\n");
	printf("\tuint32_t\t\tversion;\n");
	printf("\tIconv_error_f\t\terrorf;\n");
	printf("\tsize_t\t\t\terrors;\n");
	printf("\tuint32_t\t\tflags;\n");
	printf("\tint\t\t\tfill;\n");
	printf("} Iconv_disc_t;\n");
	printf("\n");
	printf("typedef Ccmap_t %siconv_list_t;\n", lib);
	printf("typedef void* %siconv_t;\n", lib);
	printf("typedef size_t (*%siconv_f)(%siconv_t, char**, size_t*, char**, size_t*);\n", lib, lib);
	printf("\n");
	printf("#define iconv_init(d,e)\t\t(memset(d,0,sizeof(*(d))),(d)->version=ICONV_VERSION,(d)->errorf=(Iconv_error_f)(e),(d)->fill=(-1))\n");
	printf("\n");
	printf("extern %siconv_t\t%siconv_open(const char*, const char*);\n", lib, lib);
	printf("extern size_t\t\t%siconv(%siconv_t, char**, size_t*, char**, size_t*);\n", lib, lib);
	printf("extern int\t\t%siconv_close(%siconv_t);\n", lib, lib);
	printf("extern %siconv_list_t*\t%siconv_list(%siconv_list_t*);\n", lib, lib, lib);
	printf("extern int\t\t%siconv_name(const char*, char*, size_t);\n", lib);
	printf("#if _SFIO_H\n");
	printf("extern ssize_t\t\t%siconv_move(%siconv_t, Sfio_t*, Sfio_t*, size_t, Iconv_disc_t*);\n", lib, lib);
	printf("extern ssize_t\t\t%siconv_write(%siconv_t, Sfio_t*, char**, size_t*, Iconv_disc_t*);\n", lib, lib);
	printf("#else\n");
	printf("#if _SFSTDIO_H\n");
	printf("extern ssize_t\t\t%siconv_move(%siconv_t, FILE*, FILE*, size_t, Iconv_disc_t*);\n", lib, lib);
	printf("extern ssize_t\t\t%siconv_write(%siconv_t, FILE*, char**, size_t*, Iconv_disc_t*);\n", lib, lib);
	printf("#endif\n");
	printf("#endif\n");
	printf("\n");
	return 0;
}

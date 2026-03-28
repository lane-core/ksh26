# probe: ast-iconv — iconv detection
# Tier 6. Source: src/lib/libast/features/iconv — iffe script.
# Probes: hdr iconv, lib iconv_open/iconv_close/iconv, nxt iconv,
# then compiles and runs a tst output{} C program.

probe_ast_iconv()
{
	_out="$1"

	if [ "$opt_force" = 0 ] && [ -f "$_out" ] \
	   && [ "$_out" -nt "$LIBAST_SRC/features/iconv" ]; then
		return 0
	fi

	_saved="$CFLAGS_BASE"
	CFLAGS_BASE="$CFLAGS_BASE -I$FEATDIR/libast -I$LIBAST_SRC -I$LIBAST_SRC/comp -I$LIBAST_SRC/include $ICONV_CFLAGS"

	_ic_defs=""
	_ic_hdr=0
	_ic_lib_open=0

	# hdr iconv
	if _mc_hdr "iconv.h"; then
		_ic_defs="${_ic_defs}#define _hdr_iconv	1	/* #include <iconv.h> ok */
"
		_ic_hdr=1
	fi

	# lib iconv_open, iconv_close, iconv (try with -liconv)
	for _fn in iconv_open iconv_close iconv; do
		if _mc_lib "$_fn" "$ICONV_LIB"; then
			_ic_defs="${_ic_defs}#define _lib_${_fn}	1	/* ${_fn}() in default lib(s) */
"
			[ "$_fn" = "iconv_open" ] && _ic_lib_open=1
		fi
	done

	# _LIB_iconv — detect if -liconv is needed (separate library)
	if [ -n "$ICONV_LIB" ]; then
		_ic_defs="${_ic_defs}#define _LIB_iconv	1	/* -liconv is a library */
"
	fi

	# nxt iconv
	_nxt_iconv=$(_mc_nxt "iconv")
	if [ -n "$_nxt_iconv" ]; then
		_ic_defs="${_ic_defs}#define _nxt_iconv <${_nxt_iconv}>	/* include path for the native <iconv.h> */
#define _nxt_iconv_str \"${_nxt_iconv}\"	/* include string for the native <iconv.h> */
"
	fi

	CFLAGS_BASE="$_saved"

	# tst output{}: compile and run the C program that generates the rest
	_ic_work="$FEATDIR/libast/_work_iconv"
	mkdir -p "$_ic_work"

	# Build defines header for the tst output{} program
	_ic_defsfile="$_ic_work/iconv_defs.h"
	{
		[ "$_ic_hdr" = 1 ] && echo "#define _hdr_iconv 1"
		[ "$_ic_lib_open" = 1 ] && echo "#define _lib_iconv_open 1"
		[ -n "$_nxt_iconv" ] && echo "#define _nxt_iconv_str \"${_nxt_iconv}\""
	} >|"$_ic_defsfile"

	# The tst output{} C program
	cat >|"$_ic_work/iconv_tst.c" <<'TSTEOF'
#include "iconv_defs.h"
#include <stdio.h>
#include <string.h>

#if !_lib_iconv_open
#define _undef_hdr_iconv	1
#undef	_hdr_iconv
#endif
#if !_hdr_iconv
#define _undef_lib_iconv_open	1
#undef	_lib_iconv_open
#endif
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
#if _undef_hdr_iconv
	printf("#undef\t_hdr_iconv\n");
#endif
#if _undef_lib_iconv_open
	printf("#undef\t_lib_iconv_open\n");
#endif
#if _hdr_iconv && defined(_nxt_iconv_str)
	printf("#include <%s>\t/* the native iconv.h */\n", _nxt_iconv_str);
#endif
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
TSTEOF

	_ic_tst_inc="-I$_ic_work $ICONV_CFLAGS"
	_ic_tst_bin="$_ic_work/iconv_tst"
	_ic_tst_output=""
	if probe_run "$CC" $CFLAGS_BASE $_ic_tst_inc -o "$_ic_tst_bin" "$_ic_work/iconv_tst.c" \
		$LDFLAGS_BASE; then
		_ic_tst_output=$(probe_run "$_ic_tst_bin") || true
	else
		echo "configure.sh: warning: iconv tst output{} probe failed to compile" >&2
	fi
	rm -f "$_ic_tst_bin"

	{
		echo "/* : : generated by configure.sh probe_ast_iconv : : */"
		echo "#ifndef _def_iconv_ast"
		echo "#define _def_iconv_ast	1"
		echo "#define _sys_types	1	/* #include <sys/types.h> ok */"
		printf '%s' "$_ic_defs"
		printf '%s\n' "$_ic_tst_output"
		echo "#endif"
	} | atomic_write "$_out" || true
}

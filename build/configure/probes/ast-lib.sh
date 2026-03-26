# probe: ast-lib — library function/header/member detection (largest batch probe)
# Tier 1. Tests ~35 lib functions, headers, struct members, execution tests
# for poll, select, posix_spawn, socket_peek, utime, universe.
#
# Lifted from monolith probe_ast_lib with API translations:
# - probe_hdr → _mc_hdr, probe_sys → _mc_sys, probe_lib → _mc_lib
# - probe_mem → _mc_mem, probe_dat → _mc_dat
# - probe_compile → _mc_compile, probe_link → _mc_link
# - probe_execute → _mc_execute, probe_output → _mc_output
# - $_probe_out_file → $_probe_tmpdir/mc
# - Temporarily augments CFLAGS_BASE with libast include paths

probe_ast_lib()
{
	_out="$1"

	# Cache check
	if [ "$opt_force" = 0 ] && [ -f "$_out" ] \
	   && [ "$_out" -nt "$LIBAST_SRC/features/lib" ]; then
		return 0
	fi

	_inc_dir="$FEATDIR/libast"

	# Match iffe's include context: -I paths for libast comp/include
	# so AST-shadowed headers (fnmatch.h etc.) fail the same way.
	_saved_CFLAGS_BASE="$CFLAGS_BASE"
	CFLAGS_BASE="$CFLAGS_BASE -I$FEATDIR/libast -I$LIBAST_SRC -I$LIBAST_SRC/comp -I$LIBAST_SRC/include"

	# Accumulate all defines in _defs, matching iffe's emission order exactly.
	_defs=""

	# ── sys mman ──
	if _mc_sys mman; then
		_defs="${_defs}#define _sys_mman	1	/* #include <sys/mman.h> ok */
"
	fi

	# ── hdr fcntl,dirent,...,utime ──
	for _h in fcntl dirent direntry filio fmtmsg fnmatch jioctl libgen limits \
		  locale ndir nl_types process spawn utime; do
		if _mc_hdr "${_h}.h"; then
			_defs="${_defs}#define _hdr_${_h}	1	/* #include <${_h}.h> ok */
"
		fi
	done
	# linux headers (won't exist on macOS)
	for _lh in "linux/fs" "linux/msdos_fs"; do
		_lh_name=$(echo "$_lh" | tr '/' '_')
		if _mc_compile <<EOF
${_PROBE_STD_INC}
#include <${_lh}.h>
int x;
EOF
		then
			_defs="${_defs}#define _hdr_${_lh_name}	1	/* #include <${_lh}.h> ok */
"
		fi
	done

	# ── hdr wctype ──
	_hdr_wctype=0
	if _mc_hdr "wctype.h"; then
		_hdr_wctype=1
		_defs="${_defs}#define _hdr_wctype	1	/* #include <wctype.h> ok */
"
	fi

	# ── hdr wchar (execute test) ──
	if _mc_execute <<EOF
${_PROBE_STD_INC}
#include <wchar.h>
$([ "$_hdr_wctype" = 1 ] && echo '#include <wctype.h>')
int main(void) { wchar_t w = 'a'; return iswalnum(w) == 0; }
EOF
	then
		_defs="${_defs}#define _hdr_wchar	1	/* <wchar.h> and isw*() really work */
"
	fi

	# ── dat _tzname,tzname ──
	for _d in _tzname tzname; do
		if _mc_dat "$_d"; then
			_defs="${_defs}#define _dat_${_d}	1	/* ${_d} in default lib(s) */
"
		fi
	done

	# ── lib probes ──
	for _fn in BSDsetpgrp _cleanup \
		   bcopy bzero confstr dirread \
		   fchmod fcntl fmtmsg fnmatch fork fsync \
		   getconf getdents getdirentries getdtablesize \
		   gethostname getpagesize getrlimit getuniverse \
		   glob iswblank iswctype killpg link localeconv madvise \
		   mbtowc mbrtowc memalign memdup \
		   mktemp mktime \
		   opendir openat pathconf pipe2 posix_close dup3 ppoll mkostemp \
		   rand_r \
		   rewinddir setlocale \
		   setpgrp setpgrp2 setreuid setuid \
		   socketpair \
		   clone spawn spawnve \
		   strlcat strlcpy \
		   strmode strftime symlink sysconf sysinfo \
		   telldir tmpnam tzset universe unlink utime wctype \
		   ftruncate truncate; do
		if _mc_lib "$_fn"; then
			_defs="${_defs}#define _lib_${_fn}	1	/* ${_fn}() in default lib(s) */
"
		fi
	done

	# ── lib,npt strtod,...,strtoull stdlib.h ──
	if _mc_hdr "stdlib.h"; then
		_defs="${_defs}#define _hdr_stdlib	1	/* #include <stdlib.h> ok */
"
	fi
	for _fn in strtod strtold strtol strtoll strtoul strtoull; do
		if _mc_lib "$_fn"; then
			_defs="${_defs}#define _lib_${_fn}	1	/* ${_fn}() in default lib(s) */
"
		fi
		# npt: check if function needs a prototype (not declared in stdlib.h)
		if ! _mc_compile <<EOF
${_PROBE_STD_INC}
#include <stdlib.h>
static int _test_(void) { return (int)${_fn}; }
EOF
		then
			_defs="${_defs}#define _npt_${_fn}	1	/* ${_fn}() needs a prototype */
"
		fi
	done

	# ── lib,npt sigflag signal.h ──
	if _mc_hdr "signal.h"; then
		_defs="${_defs}#define _hdr_signal	1	/* #include <signal.h> ok */
"
	fi
	if ! _mc_compile <<EOF
${_PROBE_STD_INC}
#include <signal.h>
static int _test_(void) { return (int)sigflag; }
EOF
	then
		_defs="${_defs}#define _npt_sigflag	1	/* sigflag() needs a prototype */
"
	fi

	# ── mem direct.d_reclen sys/types.h sys/dir.h ──
	if _mc_sys dir; then
		_defs="${_defs}#define _sys_dir	1	/* #include <sys/dir.h> ok */
"
	fi
	if _mc_mem direct d_reclen sys/types.h sys/dir.h; then
		_defs="${_defs}#define _mem_d_reclen_direct	1	/* d_reclen is a member of struct direct */
"
	fi

	# ── mem dirent.* sys/types.h dirent.h ──
	for _dm in d_fileno d_ino d_namlen d_off d_reclen d_type; do
		if _mc_mem dirent "$_dm" sys/types.h dirent.h; then
			_defs="${_defs}#define _mem_${_dm}_dirent	1	/* ${_dm} is a member of struct dirent */
"
		fi
	done

	# ── mem DIR sys/types.h - dirent.h - sys/dir.h ──
	_mem_DIR=0
	if _mc_compile <<EOF
${_PROBE_STD_INC}
#include <sys/types.h>
#include <dirent.h>
static DIR _i;
int n = sizeof(_i);
EOF
	then
		_mem_DIR=1
	elif _mc_compile <<EOF
${_PROBE_STD_INC}
#include <sys/types.h>
#include <sys/dir.h>
static DIR _i;
int n = sizeof(_i);
EOF
	then
		_mem_DIR=1
	fi
	[ "$_mem_DIR" = 1 ] && _defs="${_defs}#define _mem_DIR	1	/* DIR is a non-opaque struct */
"

	# ── mem DIR.dd_fd ──
	_mem_DIR_dd_fd=0
	if _mc_compile <<EOF
${_PROBE_STD_INC}
#include <sys/types.h>
#include <dirent.h>
static DIR _i;
int n = sizeof(_i.dd_fd);
EOF
	then
		_mem_DIR_dd_fd=1
	elif _mc_compile <<EOF
${_PROBE_STD_INC}
#include <sys/types.h>
#include <sys/dir.h>
static DIR _i;
int n = sizeof(_i.dd_fd);
EOF
	then
		_mem_DIR_dd_fd=1
	fi
	[ "$_mem_DIR_dd_fd" = 1 ] && _defs="${_defs}#define _mem_dd_fd_DIR	1	/* dd_fd is a member of DIR */
"

	# ── mem inheritance.pgroup spawn.h ──
	if _mc_mem inheritance pgroup spawn.h; then
		_defs="${_defs}#define _mem_pgroup_inheritance	1	/* pgroup is a member of struct inheritance */
"
	fi

	# ── mem tm.tm_zone time.h ──
	if _mc_hdr "time.h"; then
		_defs="${_defs}#define _hdr_time	1	/* #include <time.h> ok */
"
	fi
	if _mc_mem tm tm_zone time.h; then
		_defs="${_defs}#define _mem_tm_zone_tm	1	/* tm_zone is a member of struct tm */
"
	fi

	# ── sys dir,filio,ioctl,... ──
	for _s in filio ioctl jioctl localedef ptem resource \
		  socket stream systeminfo universe; do
		if _mc_sys "$_s"; then
			_defs="${_defs}#define _sys_${_s}	1	/* #include <sys/${_s}.h> ok */
"
		fi
	done

	# ── tst lib_poll ──
	if _mc_execute <<EOF
${_PROBE_STD_INC}
#include <poll.h>
#include <unistd.h>
extern int pipe(int*);
int main(void) {
	int rw[2];
	struct pollfd fd;
	if (pipe(rw) < 0) return 1;
	fd.fd = rw[0]; fd.events = POLLIN; fd.revents = 0;
	if (poll(&fd, 1, 0) < 0 || fd.revents != 0) return 1;
	if (write(rw[1], "x", 1) != 1) return 1;
	if (poll(&fd, 1, 0) < 0 || fd.revents == 0) return 1;
	return 0;
}
EOF
	then
		_defs="${_defs}#define _lib_poll	1	/* poll() args comply with the POSIX standard */
"
	fi

	# ── tst lib_select sys/select.h ──
	if _mc_link <<EOF
${_PROBE_STD_INC}
#include <sys/types.h>
#include <sys/time.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <string.h>
int main(void) {
	struct timeval tmb;
	fd_set rd;
	FD_ZERO(&rd); FD_SET(0,&rd);
	tmb.tv_sec = 0; tmb.tv_usec = 0;
	select(1,&rd,NULL,NULL,&tmb);
	return 0;
}
EOF
	then
		_defs="${_defs}#define _sys_select	1	/* #include <sys/select.h> ok */
#define _lib_select	1	/* select() has standard 5 arg interface */
"
	fi

	# ── tst sys_select (standalone, without socket.h) ──
	case $_defs in
	*_sys_select*) ;;
	*)
		if _mc_link <<EOF
${_PROBE_STD_INC}
#include <stddef.h>
#include <sys/select.h>
int main(void) {
	struct timeval tmb;
	fd_set rd;
	FD_ZERO(&rd); FD_SET(0,&rd);
	tmb.tv_sec = 0; tmb.tv_usec = 0;
	select(1,&rd,NULL,NULL,&tmb);
	return 0;
}
EOF
		then
			_defs="${_defs}#define _sys_select	1	/* select() requires <sys/select.h> */
"
		fi
		;;
	esac

	# ── tst lib_posix_spawn ──
	if _mc_hdr "unistd.h"; then
		_defs="${_defs}#define _hdr_unistd	1	/* #include <unistd.h> ok */
"
	fi
	_ps_val=""
	_ps_src="${_probe_tmpdir}/mc.c"
	cat >|"$_ps_src" <<'EOF'
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <spawn.h>
#include <signal.h>
#include <fcntl.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#define NOTE(x)
#undef fork
pid_t fork(void) { NOTE("uses fork()"); return -1; }
pid_t _fork(void) { NOTE("uses _fork()"); return -1; }
pid_t __fork(void) { NOTE("uses __fork()"); return -1; }
int main(int argc, char **argv) {
	char *s;
	pid_t pid;
	posix_spawnattr_t attr;
	int n, status;
	char *cmd[3];
	char tmp[1024];
	if (argv[1]) _exit(signal(SIGHUP, SIG_DFL) != SIG_IGN);
	signal(SIGHUP, SIG_IGN);
	if (posix_spawnattr_init(&attr)) _exit(0);
	if (posix_spawnattr_setpgroup(&attr, 0)) _exit(0);
	if (posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP)) _exit(0);
	cmd[0] = argv[0]; cmd[1] = "test"; cmd[2] = 0;
	if (posix_spawn(&pid, cmd[0], 0, &attr, cmd, 0)) _exit(0);
	status = 1;
	if (wait(&status) < 0) _exit(0);
	if (status != 0) _exit(0);
	n = strlen(cmd[0]);
	if (n >= (sizeof(tmp) - 3)) _exit(0);
	strcpy(tmp, cmd[0]);
	tmp[n] = '.'; tmp[n+1] = 's'; tmp[n+2] = 'h'; tmp[n+3] = 0;
	if ((n = open(tmp, O_CREAT|O_WRONLY, S_IRWXU|S_IRWXG|S_IRWXO)) < 0 ||
	    chmod(tmp, S_IRWXU|S_IRWXG|S_IRWXO) < 0 ||
	    write(n, "exit 99\n", 8) != 8 || close(n) < 0) _exit(0);
	cmd[0] = tmp;
	n = 0;
	pid = -1;
	if (posix_spawn(&pid, cmd[0], 0, &attr, cmd, 0)) {
		n = 2;
	} else if (pid == -1) {
		;
	} else if (wait(&status) != pid) {
		;
	} else if (!WIFEXITED(status)) {
		;
	} else {
		status = WEXITSTATUS(status);
		if (status == 127) n = 1;
	}
	unlink(tmp);
	_exit(n);
}
EOF
	if "$CC" $CFLAGS_BASE -Dfork=______fork -o "${_probe_tmpdir}/mc" "$_ps_src" \
		$LDFLAGS_BASE 2>/dev/null; then
		"${_probe_tmpdir}/mc" 2>/dev/null && _ps_val=0 || _ps_val=$?
		if [ "$_ps_val" -gt 0 ] 2>/dev/null; then
			_defs="${_defs}#define _lib_posix_spawn	${_ps_val}	/* posix_spawn exists, it works and it's worth using */
"
		fi
	fi
	rm -f "${_probe_tmpdir}/mc" "${_probe_tmpdir}/mc.sh"

	# ── tst socket_peek ──
	if _mc_execute <<EOF
${_PROBE_STD_INC}
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
int main(void) {
	int i, fds[2];
	char buf[128];
	static char msg[] = "abcd";
	if (socketpair(AF_UNIX, SOCK_STREAM, 0, fds)) return 1;
	if (write(fds[1], msg, sizeof(msg)) != sizeof(msg)) return 1;
	if (recv(fds[0], buf, sizeof(buf), MSG_PEEK) != sizeof(msg)) return 1;
	for (i = 0; i < sizeof(msg); i++) if (buf[i] != msg[i]) return 1;
	if (read(fds[0], buf, sizeof(msg)) != sizeof(msg)) return 1;
	for (i = 0; i < sizeof(msg); i++) if (buf[i] != msg[i]) return 1;
	return 0;
}
EOF
	then
		_defs="${_defs}#define _socket_peek	1	/* recv(MSG_PEEK) works on socketpair() */
"
	fi

	# ── tst lib_utime_now ──
	if _mc_execute <<EOF
${_PROBE_STD_INC}
#include <sys/types.h>
extern int utime(const char*, void*);
int main(void) { return utime(".", (void*)0) == -1; }
EOF
	then
		_defs="${_defs}#define _lib_utime_now	1	/* utime works with 0 time vector */
"
	fi

	# ── cross{} universe detection ──
	_univ="ucb"
	if env cat -s /dev/null/foo >/dev/null 2>&1; then
		case $(env echo '\t') in
		'\t')	;;
		*)	_univ="att" ;;
		esac
	fi
	_defs="${_defs}#define _UNIV_DEFAULT	\"${_univ}\"	/* default universe name */
"

	# ── std cleanup (noexecute) ──
	if ! _mc_execute <<EOF
${_PROBE_STD_INC}
#include <stdio.h>
extern void exit(int);
extern void _exit(int);
extern void _cleanup(void);
void _cleanup(void) { _exit(0); }
int main(void) { printf("cleanup\n"); exit(1); }
EOF
	then
		_defs="${_defs}#define _std_cleanup	1	/* stuck with standard _cleanup */
"
	fi

	# ── tst macos_strxfrm_bug ──
	if _mc_execute <<'EOF'
#include <string.h>
#include <locale.h>
int main(void)
{
	if (!setlocale(LC_ALL,"en_GB.UTF-8"))
		return 1;
	return !(strxfrm(NULL,"\xC2\xA7",0) == 0);
}
EOF
	then
		_defs="${_defs}#define _macos_strxfrm_bug	1	/* macOS strxfrm(3) bug */
"
	fi

	# ── spawnveg output block ──
	_spv_result=$(_mc_output <<EOF
#include <stdio.h>
int main(void) {
#if ${_ps_val:-0} || 0 || 0
	printf("#if !_AST_no_spawnveg\n");
	printf("#define _use_spawnveg\t1\n");
	printf("#endif\n");
	printf("\n");
#endif
	return 0;
}
EOF
)
	[ -n "$_spv_result" ] && _defs="${_defs}${_spv_result}
"

	# Restore CFLAGS
	CFLAGS_BASE="$_saved_CFLAGS_BASE"

	# ── Emit the header ──
	{
		echo "/* : : generated by configure.sh probe_ast_lib : : */"
		echo "#ifndef _def_lib_ast"
		echo "#define _def_lib_ast	1"
		echo "#define _sys_types	1	/* #include <sys/types.h> ok */"
		printf '%s' "$_defs"
		echo ""
		echo "#endif"
	} | atomic_write "$_out" || true
}

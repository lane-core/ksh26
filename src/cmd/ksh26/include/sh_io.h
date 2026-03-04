/***********************************************************************
*                                                                      *
*               This software is part of the ksh26 project             *
*          Copyright (c) 2026 Contributors to ksh 93u+m                *
*                      and is licensed under the                       *
*                 Eclipse Public License, Version 2.0                  *
*                                                                      *
*                A copy of the License is available at                 *
*      https://www.eclipse.org/org/documents/epl-2.0/EPL-2.0.html      *
*         (with md5 checksum 84283fa8859daf213bdda5a9f8d1be1d)         *
*                                                                      *
***********************************************************************/
#ifndef _sh_io_h_defined
#define _sh_io_h_defined 1

/*
 * sh_io.h — I/O type abstraction for ksh26
 *
 * Decouples ksh26 from sfio at the type level, enabling future
 * migration to stdio + custom implementations.
 *
 * KSH_IO_SFIO=1 (default): passthrough to sfio types
 * KSH_IO_SFIO=0 (future):  stdio + sh_strbuf + sh_disc
 *
 * Function names (sf*) are NOT abstracted here — they stay as-is
 * in all call sites.  When the stdio backend is written, sf* names
 * become macros wrapping stdio equivalents (with argument reordering
 * where needed), giving zero diff on ~1000 call sites.
 */

#ifndef KSH_IO_SFIO
#define KSH_IO_SFIO 1
#endif

#if KSH_IO_SFIO

/*
 * ===== sfio backend (current) =====
 */

#include <sfio.h>

/* Stream types — direct aliases */
typedef Sfio_t sh_stream_t;
typedef Sfdisc_t sh_disc_t;
#define sh_off_t Sfoff_t

/* Discipline callback types */
typedef Sfread_f sh_read_f;
typedef Sfwrite_f sh_write_f;
typedef Sfseek_f sh_seek_f;
typedef Sfexcept_f sh_except_f;

/* Formatted I/O types */
typedef Sffmt_t sh_fmt_t;
typedef Sffmtext_f sh_fmtext_f;
typedef Sffmtevent_f sh_fmtevent_f;

/* Stream flags — ksh26 names mapping to SFIO_ constants */
#define SH_IO_READ SFIO_READ
#define SH_IO_WRITE SFIO_WRITE
#define SH_IO_STRING SFIO_STRING
#define SH_IO_APPENDWR SFIO_APPENDWR
#define SH_IO_MALLOC SFIO_MALLOC
#define SH_IO_LINE SFIO_LINE
#define SH_IO_SHARE SFIO_SHARE
#define SH_IO_EOF SFIO_EOF
#define SH_IO_ERROR SFIO_ERROR
#define SH_IO_STATIC SFIO_STATIC
#define SH_IO_IOCHECK SFIO_IOCHECK
#define SH_IO_PUBLIC SFIO_PUBLIC
#define SH_IO_WHOLE SFIO_WHOLE
#define SH_IO_IOINTR SFIO_IOINTR
#define SH_IO_WCWIDTH SFIO_WCWIDTH

#define SH_IO_BUFSIZE SFIO_BUFSIZE

/* Exception events */
#define SH_IO_CLOSING SFIO_CLOSING
#define SH_IO_DPUSH SFIO_DPUSH
#define SH_IO_DPOP SFIO_DPOP
#define SH_IO_DBUFFER SFIO_DBUFFER
#define SH_IO_SYNC SFIO_SYNC
#define SH_IO_PURGE SFIO_PURGE
#define SH_IO_FINAL SFIO_FINAL
#define SH_IO_READY SFIO_READY
#define SH_IO_NEW SFIO_NEW
#define SH_IO_SETFD SFIO_SETFD

/* For sfreserve */
#define SH_IO_LOCKR SFIO_LOCKR
#define SH_IO_LASTR SFIO_LASTR

/* Discipline stack sentinels */
#define SH_IO_POPSTACK SFIO_POPSTACK
#define SH_IO_POPDISC SFIO_POPDISC

/* Standard streams */
#define sh_stdin sfstdin
#define sh_stdout sfstdout
#define sh_stderr sfstderr

#else /* !KSH_IO_SFIO */

/*
 * ===== stdio backend =====
 *
 * sh_stream_t wraps FILE* with metadata needed for sfio-compatible
 * behavior (sfswap, sfvalue, disciplines, stream stacking).
 *
 * sf* function names become macros or inline functions here,
 * routing to stdio equivalents with argument reordering as needed.
 * Complex operations (sfopen, sfdisc, sfreserve, etc.) are implemented
 * in sh_io_stdio.c.
 */

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <unistd.h>
#include <sys/types.h>

/* ── offset type ────────────────────────────────────────────── */

#define sh_off_t off_t

/* ── discipline types (forward declarations) ────────────────── */

struct sh_stream_s;
struct sh_disc_s;

typedef ssize_t (*sh_read_f)(struct sh_stream_s *, void *, size_t, struct sh_disc_s *);
typedef ssize_t (*sh_write_f)(struct sh_stream_s *, const void *, size_t, struct sh_disc_s *);
typedef off_t (*sh_seek_f)(struct sh_stream_s *, off_t, int, struct sh_disc_s *);
typedef int (*sh_except_f)(struct sh_stream_s *, int, void *, struct sh_disc_s *);

typedef struct sh_disc_s
{
	sh_read_f readf;
	sh_write_f writef;
	sh_seek_f seekf;
	sh_except_f exceptf;
	struct sh_disc_s *disc; /* next in chain */
} sh_disc_t;

/* ── formatted I/O types ─────────────────────────────────────── */

struct sh_fmt_s;
typedef int (*sh_fmtext_f)(struct sh_stream_s *, void *, struct sh_fmt_s *);
typedef int (*sh_fmtevent_f)(struct sh_stream_s *, int, void *, struct sh_fmt_s *);
typedef int (*sh_fmtreload_f)(int, char, void *, struct sh_fmt_s *);

typedef struct sh_fmt_s
{
	long version;
	sh_fmtext_f extf;
	sh_fmtevent_f eventf;
	sh_fmtreload_f reloadf;
	char *form;
	va_list args;
	int fmt;
	ssize_t size;
	int flags;
	int width;
	int precis;
	int base;
	char *t_str;
	ssize_t n_str;
	void *mbs;
} sh_fmt_t;

/* ── stream wrapper struct ──────────────────────────────────── */

typedef struct sh_stream_s
{
	FILE *fp;                  /* underlying stdio handle */
	int fd;                    /* backing fd (-1 for memory) */
	int flags;                 /* SH_IO_* flags */
	ssize_t val;               /* sfvalue() result */
	unsigned char *data;       /* buffer base (sfio compat, set for string streams) */
	char *buf;                 /* reserve buffer (sfreserve) */
	size_t bufsz;              /* reserve buffer capacity */
	char *getr_buf;            /* sfgetr line buffer */
	size_t getr_bufsz;         /* sfgetr buffer capacity */
	sh_disc_t *disc;           /* discipline chain */
	struct sh_stream_s *stack; /* sfstack linked list */
} sh_stream_t;

/* ── stream flags ───────────────────────────────────────────── */
/* Same octal values as sfio for debugging convenience */

#define SH_IO_READ 0000001
#define SH_IO_WRITE 0000002
#define SH_IO_STRING 0000004
#define SH_IO_APPENDWR 0000010
#define SH_IO_MALLOC 0000020
#define SH_IO_LINE 0000040
#define SH_IO_SHARE 0000100
#define SH_IO_EOF 0000200
#define SH_IO_ERROR 0000400
#define SH_IO_STATIC 0001000
#define SH_IO_IOCHECK 0002000
#define SH_IO_PUBLIC 0004000
#define SH_IO_WHOLE 0020000
#define SH_IO_IOINTR 0040000
#define SH_IO_WCWIDTH 0100000

#define SH_IO_BUFSIZE 8192

/* internal flags — not part of the sfio ABI */
#define _SH_IO_RSVLCK 0200000 /* sfreserve buffer is locked */

/* Exception events */
#define SH_IO_CLOSING 4
#define SH_IO_DPUSH 5
#define SH_IO_DPOP 6
#define SH_IO_DBUFFER 8
#define SH_IO_SYNC 9
#define SH_IO_PURGE 10
#define SH_IO_FINAL 11
#define SH_IO_READY 12
#define SH_IO_NEW 0
#define SH_IO_SETFD (-1)

/* For sfreserve */
#define SH_IO_LOCKR 0000010
#define SH_IO_LASTR 0000020

/* Discipline stack sentinels */
#define SH_IO_POPSTACK nullptr
#define SH_IO_POPDISC nullptr

/* ── standard streams ───────────────────────────────────────── */

extern sh_stream_t _sh_stdin, _sh_stdout, _sh_stderr;
#define sh_stdin (&_sh_stdin)
#define sh_stdout (&_sh_stdout)
#define sh_stderr (&_sh_stderr)

/*
 * sfstdin/sfstdout/sfstderr are real pointer variables (not macros)
 * because subshell.c reassigns them during command substitution.
 * Initialized to &_sh_stdin etc. in sh_io_stdio.c.
 *
 * Linker names are prefixed _ksh_ to avoid collision with libast's
 * sfextern.c, which defines the real sfio globals of the same name.
 * The macros below redirect all ksh26 code transparently.
 */
extern sh_stream_t *_ksh_sfstdin, *_ksh_sfstdout, *_ksh_sfstderr;
#define sfstdin _ksh_sfstdin
#define sfstdout _ksh_sfstdout
#define sfstderr _ksh_sfstderr

/* ── trivial macros ─────────────────────────────────────────── */

#define sfprintf(f, ...) fprintf((f)->fp, __VA_ARGS__)
#define sfputc(f, c) fputc((c), (f)->fp)
#define sfwrite(f, p, n) ((ssize_t)fwrite((p), 1, (n), (f)->fp))
#define sftell(f) ftello((f)->fp)
#define sffileno(f) ((f)->fd)
#define sfeof(f) feof((f)->fp)
#define sferror(f) ferror((f)->fp)
#define sfclrerr(f) clearerr((f)->fp)
/*
 * sfgetc: consume from sfreserve buffer first, fall through to fgetc.
 * Matches sfio's shared-buffer model where sfgetc and sfreserve
 * operate on the same internal buffer.
 */
static inline int
_sh_io_getc(sh_stream_t *f)
{
	if(f->val > 0 && f->data)
	{
		f->val--;
		return (unsigned char)*f->data++;
	}
	return fgetc(f->fp);
}
#define sfgetc(f) _sh_io_getc(f)
#define sfvalue(f) ((f)->val)
#define sfungetc(f, c) ungetc((c), (f)->fp)
#define sfsprintf(b, n, ...) snprintf((b), (n), __VA_ARGS__)

/* ── inline helper functions ────────────────────────────────── */

/*
 * sfread: manages interaction with sfreserve's buffer.
 * - n==0: release sfreserve lock (data stays in buffer)
 * - n>0 with buffered data: consume from sfreserve buffer
 * - n>0 without buffered data: read from FILE*
 */
static inline ssize_t
_sh_io_read(sh_stream_t *f, void *p, size_t n)
{
	if(n == 0)
	{
		f->flags &= ~_SH_IO_RSVLCK;
		return 0;
	}
	/* consume from sfreserve buffer if data is available */
	if(f->val > 0 && f->data)
	{
		size_t avail = (size_t)f->val;
		size_t take = n < avail ? n : avail;
		memmove(p, f->data, take);
		f->data += take;
		f->val -= (ssize_t)take;
		return (ssize_t)take;
	}
	return (ssize_t)fread(p, 1, n, f->fp);
}
#define sfread(f, p, n) _sh_io_read((f), (p), (n))

static inline int
_sh_io_sync(sh_stream_t *f)
{
	return f ? fflush(f->fp) : fflush(nullptr);
}
#define sfsync(f) _sh_io_sync(f)

static inline off_t
_sh_io_seek(sh_stream_t *f, off_t offset, int whence)
{
	/* flush pending writes before seeking — POSIX fseeko
	 * should handle this, but be defensive across impls */
	if(f->flags & SH_IO_WRITE)
		fflush(f->fp);
	if(fseeko(f->fp, offset, whence) < 0)
		return (off_t)-1;
	return ftello(f->fp);
}
#define sfseek(f, o, w) _sh_io_seek((f), (o), (w))

static inline ssize_t
_sh_io_putr(sh_stream_t *f, const char *s, int delim)
{
	ssize_t n;
	if(fputs(s, f->fp) == EOF)
		return -1;
	n = strlen(s);
	if(delim >= 0)
	{
		if(fputc(delim, f->fp) == EOF)
			return -1;
		n++;
	}
	return n;
}
#define sfputr(f, s, d) _sh_io_putr((f), (s), (d))

static inline ssize_t
_sh_io_nputc(sh_stream_t *f, int c, size_t n)
{
	size_t i;
	for(i = 0; i < n; i++)
		if(fputc(c, f->fp) == EOF)
			return -1;
	return (ssize_t)n;
}
#define sfnputc(f, c, n) _sh_io_nputc((f), (c), (n))

/* ── functions implemented in sh_io_stdio.c ─────────────────── */

extern void sh_stream_init(void);
extern sh_stream_t *sh_stream_new(FILE *, int, int);
extern int sh_stream_close(sh_stream_t *);
extern int sh_stream_set(sh_stream_t *, int, int);
extern char *sh_stream_prints(const char *, ...);

#define sfclose(f) sh_stream_close(f)
#define sfset(f, fl, on) sh_stream_set((f), (fl), (on))
#define sfprints(...) sh_stream_prints(__VA_ARGS__)

/* ── stubs for complex operations (Sessions B–D) ────────────── */
/* These abort() when called — replaced with real implementations
 * as each session fills them in. */

extern sh_stream_t *sfopen(sh_stream_t *, const char *, const char *);
extern sh_stream_t *sfnew(sh_stream_t *, void *, size_t, int, int);
extern sh_stream_t *sfswap(sh_stream_t *, sh_stream_t *);
extern int sfsetfd(sh_stream_t *, int);
extern int sfsetfd_cloexec(sh_stream_t *, int);
extern sh_disc_t *sfdisc(sh_stream_t *, sh_disc_t *);
extern void *sfreserve(sh_stream_t *, ssize_t, int);
extern sh_stream_t *sfstack(sh_stream_t *, sh_stream_t *);
extern sh_stream_t *sfpool(sh_stream_t *, sh_stream_t *, int);
extern sh_stream_t *sftmp(size_t);
extern char *sfgetr(sh_stream_t *, int, int);
extern off_t sfmove(sh_stream_t *, sh_stream_t *, off_t, int);
extern void *sfsetbuf(sh_stream_t *, void *, size_t);
extern int sfpurge(sh_stream_t *);
extern int sfnotify(void (*)(sh_stream_t *, int, void *));
extern ssize_t sfpkrd(int, void *, size_t, int, long, int);
extern ssize_t sfrd(sh_stream_t *, void *, size_t, sh_disc_t *);
extern int sfclrlock(sh_stream_t *);
extern int sfpoll(sh_stream_t **, int, int);
extern int sfraise(sh_stream_t *, int, void *);
extern int sfstacked(sh_stream_t *);
extern off_t sfsize(sh_stream_t *);
extern ssize_t sfgetl(sh_stream_t *);
extern ssize_t sfgetu(sh_stream_t *);
extern int sfputl(sh_stream_t *, ssize_t);
extern int sfputu(sh_stream_t *, size_t);

/* sfkeyprintf is in sfdisc.h under sfio — declare here for stdio */
struct Sf_key_lookup_s;
struct Sf_key_convert_s;
extern int sfkeyprintf(sh_stream_t *, void *, const char *,
                       int (*)(void *, sh_stream_t *, off_t, const char *, int, sh_disc_t *, int),
                       int (*)(void *, sh_stream_t *, const char *));

/* ── string stream macros (route to sh_strbuf) ──────────────── */
/* Actual implementations in sh_strbuf.h and sh_io_stdio.c */

#include "sh_strbuf.h"

#define sfstropen() ((sh_stream_t *)sh_strbuf_open())
#define sfstrclose(s) sh_strbuf_close((sh_strbuf_t *)(s))
#define sfstruse(s) sh_strbuf_use((sh_strbuf_t *)(s))
#define sfstrseek(s, p, m) sh_strbuf_seek((sh_strbuf_t *)(s), (p), (m))
#define sfstrtell(s) sh_strbuf_tell((sh_strbuf_t *)(s))
#define sfstrbase(s) sh_strbuf_base((sh_strbuf_t *)(s))
#define sfstrsize(s) sh_strbuf_size((sh_strbuf_t *)(s))

#endif /* KSH_IO_SFIO */

#endif /* !_sh_io_h_defined */

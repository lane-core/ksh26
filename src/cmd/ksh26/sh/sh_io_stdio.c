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

/*
 * sh_io_stdio.c — stdio backend implementation for sh_io.h
 *
 * Only compiled when KSH_IO_SFIO=0. Provides:
 * - Standard stream globals (_sh_stdin, _sh_stdout, _sh_stderr)
 * - Stream lifecycle (sh_stream_new, sh_stream_close)
 * - sh_stream_set (sfset), sh_stream_prints (sfprints)
 * - sh_strbuf_* (open_memstream-backed string buffers)
 * - Stubs for complex operations (filled in by Sessions B–D)
 */

#include	"sh_io.h"

#if !KSH_IO_SFIO

#include	<assert.h>
#include	<stdarg.h>
#include	<errno.h>
#include	<fcntl.h>
#include	<poll.h>
#include	<stdint.h>
#include	<sys/socket.h>
#include	<sys/stat.h>

/* ── standard streams ───────────────────────────────────────── */

sh_stream_t _sh_stdin  = { NULL, 0, SH_IO_READ  | SH_IO_STATIC, 0, NULL, NULL, 0, NULL, 0, NULL, NULL };
sh_stream_t _sh_stdout = { NULL, 1, SH_IO_WRITE | SH_IO_STATIC, 0, NULL, NULL, 0, NULL, 0, NULL, NULL };
sh_stream_t _sh_stderr = { NULL, 2, SH_IO_WRITE | SH_IO_STATIC, 0, NULL, NULL, 0, NULL, 0, NULL, NULL };

/* assignable stream pointers — subshell.c redirects these
 * Prefixed _ksh_ to avoid collision with libast's sfextern.c;
 * sh_io.h macros redirect sfstdin → _ksh_sfstdin etc. */
sh_stream_t *_ksh_sfstdin  = &_sh_stdin;
sh_stream_t *_ksh_sfstdout = &_sh_stdout;
sh_stream_t *_ksh_sfstderr = &_sh_stderr;

/*
 * Initialize standard stream wrappers. Call once at startup
 * before any I/O. Sets the FILE* pointers to the real stdio streams.
 */
void
sh_stream_init(void)
{
	_sh_stdin.fp  = stdin;
	_sh_stdout.fp = stdout;
	_sh_stderr.fp = stderr;
}

/* ── stream lifecycle ───────────────────────────────────────── */

sh_stream_t *
sh_stream_new(FILE *fp, int fd, int flags)
{
	sh_stream_t *s;
	s = calloc(1, sizeof(*s));
	if(!s)
		return NULL;
	s->fp = fp;
	s->fd = fd;
	s->flags = flags;
	return s;
}

int
sh_stream_close(sh_stream_t *f)
{
	int r;
	if(!f)
		return -1;
	r = 0;
	if(f->fp)
		r = fclose(f->fp);
	/* free auxiliary buffers */
	free(f->buf);
	free(f->getr_buf);
	/* don't free static streams */
	if(!(f->flags & SH_IO_STATIC))
		free(f);
	else
	{
		f->fp = NULL;
		f->fd = -1;
	}
	return r;
}

/* ── sfset — set/clear stream flags ─────────────────────────── */

int
sh_stream_set(sh_stream_t *f, int flags, int on)
{
	int old;
	if(!f)
		return 0;
	old = f->flags;
	if(on)
		f->flags |= flags;
	else
		f->flags &= ~flags;
	/* apply line buffering to the underlying FILE */
	if((flags & SH_IO_LINE) && f->fp)
	{
		if(on)
			setvbuf(f->fp, NULL, _IOLBF, 0);
		else
			setvbuf(f->fp, NULL, _IOFBF, SH_IO_BUFSIZE);
	}
	return old;
}

/* ── sfprints — format to static buffer ─────────────────────── */

char *
sh_stream_prints(const char *fmt, ...)
{
	static char buf[8192];
	va_list ap;
	va_start(ap, fmt);
	vsnprintf(buf, sizeof(buf), fmt, ap);
	va_end(ap);
	return buf;
}

/* ── sh_strbuf — string buffers via open_memstream ──────────── */

sh_strbuf_t *
sh_strbuf_open(void)
{
	sh_strbuf_t *s;
	s = calloc(1, sizeof(*s));
	if(!s)
		return NULL;
	s->stream.fp = open_memstream(&s->buf, &s->len);
	if(!s->stream.fp)
	{
		free(s);
		return NULL;
	}
	s->stream.fd = -1;
	s->stream.flags = SH_IO_WRITE | SH_IO_STRING | SH_IO_MALLOC;
	return s;
}

char *
sh_strbuf_use(sh_strbuf_t *s)
{
	if(!s || !s->stream.fp)
		return NULL;
	fflush(s->stream.fp);
	/* keep data pointer in sync for sfio compat (out->_data access) */
	s->stream.data = (unsigned char*)s->buf;
	/* rewind for reuse — next write starts at beginning */
	rewind(s->stream.fp);
	return s->buf;
}

int
sh_strbuf_close(sh_strbuf_t *s)
{
	if(!s)
		return -1;
	if(s->stream.fp)
		fclose(s->stream.fp);
	free(s->buf);
	free(s);
	return 0;
}

off_t
sh_strbuf_seek(sh_strbuf_t *s, off_t offset, int whence)
{
	if(!s || !s->stream.fp)
		return (off_t)-1;
	/*
	 * open_memstream requires a flush before seeking to ensure
	 * the buffer pointer and length are up to date.
	 */
	fflush(s->stream.fp);
	if(fseeko(s->stream.fp, offset, whence) < 0)
		return (off_t)-1;
	return ftello(s->stream.fp);
}

off_t
sh_strbuf_tell(sh_strbuf_t *s)
{
	if(!s || !s->stream.fp)
		return (off_t)-1;
	return ftello(s->stream.fp);
}

char *
sh_strbuf_base(sh_strbuf_t *s)
{
	if(!s || !s->stream.fp)
		return NULL;
	fflush(s->stream.fp);
	s->stream.data = (unsigned char*)s->buf;
	return s->buf;
}

size_t
sh_strbuf_size(sh_strbuf_t *s)
{
	if(!s || !s->stream.fp)
		return 0;
	fflush(s->stream.fp);
	return s->len;
}

/* ── helpers ────────────────────────────────────────────────── */

static void (*_sh_notify_fn)(sh_stream_t*, int, void*);

/*
 * Map SH_IO flags to an fdopen mode string.
 * fdopen doesn't truncate, so "w" is safe for existing fds.
 */
static const char *
_sh_fdmode(int flags)
{
	if((flags & SH_IO_READ) && (flags & SH_IO_WRITE))
		return "r+";
	if(flags & SH_IO_READ)
		return "r";
	return "w";
}

/*
 * Ensure a stream has a FILE* open for its fd.
 * For fds 0/1/2 uses the process stdio handles;
 * for others uses fdopen.
 */
static void
_sh_ensure_fp(sh_stream_t *f)
{
	if(f->fp || f->fd < 0)
		return;
	switch(f->fd)
	{
	case 0: f->fp = stdin; break;
	case 1: f->fp = stdout; break;
	case 2: f->fp = stderr; break;
	default:
		f->fp = fdopen(f->fd, _sh_fdmode(f->flags));
		break;
	}
}

/* ── sfnotify — register stream event callback ─────────────── */

int
sfnotify(void(*func)(sh_stream_t*, int, void*))
{
	_sh_notify_fn = func;
	return 0;
}

/* ── sfsetbuf — set stream buffer ──────────────────────────── */

void *
sfsetbuf(sh_stream_t *f, void *buf, size_t size)
{
	if(!f)
		return NULL;
	/*
	 * sfsetbuf(f, f, 0): sfio idiom to query current buffer.
	 * Sets sfvalue(f) to the buffer size and returns the base.
	 */
	if(buf == (void*)f)
	{
		if(f->flags & SH_IO_STRING)
		{
			sh_strbuf_t *sb = (sh_strbuf_t*)f;
			fflush(f->fp);
			f->val = (ssize_t)sb->len;
			f->data = (unsigned char*)sb->buf;
			return sb->buf;
		}
		f->val = (ssize_t)f->bufsz;
		return f->buf;
	}
	/* string streams: buffer managed by open_memstream */
	if(f->flags & SH_IO_STRING)
		return NULL;
	_sh_ensure_fp(f);
	if(!f->fp)
		return NULL;
	/*
	 * setvbuf sets the underlying FILE*'s buffer;
	 * f->buf/bufsz are reserved for sfreserve's read buffer.
	 */
	if(buf && size > 0)
		setvbuf(f->fp, buf, _IOFBF, size);
	else if(size > 0)
		setvbuf(f->fp, NULL, _IOFBF, size);
	return NULL;
}

/* ── sfnew — create or reinitialize a stream around an fd ──── */

sh_stream_t *
sfnew(sh_stream_t *f, void *buf, size_t size, int fd, int flags)
{
	if(f)
	{
		/* reinitialize existing stream wrapper */
		if(f->fp && !(f->flags & SH_IO_STATIC))
			fclose(f->fp);
		f->fp = NULL;
		f->fd = fd;
		f->flags = flags;
		f->val = 0;
	}
	else
	{
		f = sh_stream_new(NULL, fd, flags);
		if(!f)
			return NULL;
	}
	if(flags & SH_IO_STRING)
	{
		/*
		 * String stream: buf is the data, size is its length.
		 * Use fmemopen to create a readable FILE* over the buffer.
		 */
		const char *mode;
		if((flags & SH_IO_READ) && (flags & SH_IO_WRITE))
			mode = "r+";
		else if(flags & SH_IO_READ)
			mode = "r";
		else
			mode = "w";
		if(buf && size > 0)
			f->fp = fmemopen(buf, size, mode);
		f->data = (unsigned char*)buf;
		f->fd = -1;
	}
	else
	{
		assert(fd >= 0 || (flags & SH_IO_STRING));
		_sh_ensure_fp(f);
		if(buf && size > 0 && f->fp)
			setvbuf(f->fp, buf, _IOFBF, size);
	}
	if(_sh_notify_fn)
		_sh_notify_fn(f, SH_IO_NEW, NULL);
	return f;
}

/* ── sfopen — open a stream by path or mode ────────────────── */

sh_stream_t *
sfopen(sh_stream_t *f, const char *s, const char *mode)
{
	FILE *fp;
	int flags = 0;
	const char *m;
	/* parse sfio mode string */
	for(m = mode; *m; m++)
	{
		switch(*m)
		{
		case 'r': flags |= SH_IO_READ; break;
		case 'w': flags |= SH_IO_WRITE; break;
		case '+': flags |= SH_IO_READ | SH_IO_WRITE; break;
		case 's': flags |= SH_IO_STRING; break;
		}
	}
	/* string mode with no path: create string stream */
	if((flags & SH_IO_STRING) && !s)
		return (sh_stream_t*)sh_strbuf_open();
	if(!s)
		return NULL;
	fp = fopen(s, _sh_fdmode(flags));
	if(!fp)
		return NULL;
	if(f)
	{
		if(f->fp)
			fclose(f->fp);
		f->fp = fp;
		f->fd = fileno(fp);
		f->flags = flags;
	}
	else
	{
		f = sh_stream_new(fp, fileno(fp), flags);
		if(!f)
		{
			fclose(fp);
			return NULL;
		}
	}
	if(_sh_notify_fn)
		_sh_notify_fn(f, SH_IO_NEW, NULL);
	return f;
}

/* ── sfswap — exchange contents of two stream wrappers ──────── */

/*
 * sfswap: exchange contents of two stream wrappers.
 *
 * sfswap(f1, f2): swap contents, return f2
 * sfswap(f1, NULL): allocate new stream, move f1 into it, clear f1
 *
 * The NULL case is critical for command substitution: subshell.c does
 * saveout = sfswap(sfstdout, NULL) to detach stdout into a saved copy.
 */
sh_stream_t *
sfswap(sh_stream_t *f1, sh_stream_t *f2)
{
	sh_stream_t tmp;
	if(!f1)
		return NULL;
	if(!f2)
	{
		/* allocate a new stream and move f1's content into it */
		f2 = malloc(sizeof(*f2));
		if(!f2)
			return NULL;
		memcpy(f2, f1, sizeof(*f1));
		/*
		 * The copy is heap-allocated, not a static global —
		 * clear SFIO_STATIC so it can be freed later.
		 */
		f2->flags &= ~SH_IO_STATIC;
		/* clear f1 (now "available") */
		memset(f1, 0, sizeof(*f1));
		f1->fd = -1;
		return f2;
	}
	/*
	 * Two-arg swap: exchange contents but preserve SFIO_STATIC
	 * based on struct identity (which address is a static global),
	 * not the swapped content.
	 */
	{
		int f1static = f1->flags & SH_IO_STATIC;
		int f2static = f2->flags & SH_IO_STATIC;
		tmp = *f1;
		*f1 = *f2;
		*f2 = tmp;
		if(f1static)
			f1->flags |= SH_IO_STATIC;
		else
			f1->flags &= ~SH_IO_STATIC;
		if(f2static)
			f2->flags |= SH_IO_STATIC;
		else
			f2->flags &= ~SH_IO_STATIC;
	}
	return f2;
}

/* ── sfsetfd — change the backing fd of a stream ───────────── */

int
sfsetfd(sh_stream_t *f, int fd)
{
	int old;
	if(!f)
		return -1;
	old = f->fd;
	if(fd == old)
		return old;
	f->fd = fd;
	/*
	 * Reopen the FILE* for the new fd. For static streams
	 * (stdin/stdout/stderr), the old FILE* is shared with the
	 * C library, so we don't fclose it.
	 */
	if(f->fp && !(f->flags & SH_IO_STATIC))
	{
		fclose(f->fp);
		f->fp = NULL;
	}
	else
		f->fp = NULL;
	if(fd >= 0)
		_sh_ensure_fp(f);
	if(_sh_notify_fn)
		_sh_notify_fn(f, SH_IO_SETFD, (void*)(intptr_t)fd);
	return old;
}

int
sfsetfd_cloexec(sh_stream_t *f, int fd)
{
	int r = sfsetfd(f, fd);
	if(fd >= 0)
		fcntl(fd, F_SETFD, FD_CLOEXEC);
	return r;
}

/* ── sfdisc — push/pop discipline on a stream ──────────────── */

sh_disc_t *
sfdisc(sh_stream_t *f, sh_disc_t *d)
{
	sh_disc_t *old;
	if(!f)
		return NULL;
	if(!d)
	{
		/* pop top discipline */
		old = f->disc;
		if(old)
			f->disc = old->disc;
		return old;
	}
	/* push discipline onto chain */
	old = f->disc;
	d->disc = old;
	f->disc = d;
	return d;
}

/* ── sfpool — stream pool management ───────────────────────── */
/*
 * sfio pools synchronize flushing across grouped streams.
 * Under stdio, each FILE* manages its own buffer, so pooling
 * is a no-op. The outpool identifier stream still gets created
 * (via sfopen "sw") but doesn't participate in buffer sharing.
 */

sh_stream_t *
sfpool(sh_stream_t *f1, sh_stream_t *f2, int action)
{
	(void)f2;
	(void)action;
	return f1;
}

/* ── sfpurge — discard buffered data ───────────────────────── */

int
sfpurge(sh_stream_t *f)
{
	if(!f || !f->fp)
		return -1;
	return fflush(f->fp);
}

/* ── sfraise — raise exception through discipline chain ────── */

int
sfraise(sh_stream_t *f, int type, void *data)
{
	sh_disc_t *d;
	if(!f)
		return -1;
	for(d = f->disc; d; d = d->disc)
	{
		if(d->exceptf)
		{
			int r = d->exceptf(f, type, data, d);
			if(r != 0)
				return r;
		}
	}
	return 0;
}

/* ── sfstacked — check if stream has a stack ────────────────── */

int
sfstacked(sh_stream_t *f)
{
	return f && f->stack != NULL;
}

/* ── sfclrlock — clear stream lock ─────────────────────────── */

int
sfclrlock(sh_stream_t *f)
{
	(void)f;
	return 0;
}

/* ── sfsize — return stream size ───────────────────────────── */

off_t
sfsize(sh_stream_t *f)
{
	struct stat st;
	if(!f || f->fd < 0)
		return (off_t)-1;
	if(fstat(f->fd, &st) < 0)
		return (off_t)-1;
	return st.st_size;
}

/* ── sfreserve — reserve buffer space for reading ──────────── */
/*
 * sfio semantics:
 *   size > 0: reserve exactly size bytes
 *   size == 0: peek — check if data is available
 *   size < 0 (SFIO_UNBOUND): read whatever is available
 *   type & SH_IO_LOCKR: lock buffer (caller must sfread(f,buf,0) to release)
 *   type < 0: peek without consuming
 * Returns pointer to data, sets sfvalue(f) to amount available.
 */

void *
sfreserve(sh_stream_t *f, ssize_t size, int type)
{
	size_t want, got;
	if(!f || !f->fp)
		return NULL;
	/*
	 * Buffer consumption discipline — sfio has two modes:
	 *
	 *   LOCKR: caller reads from buffer directly, then calls
	 *          sfread(f,buf,0) to release. Buffer stays valid
	 *          across multiple sfreserve calls until consumed.
	 *
	 *   Non-LOCKR: data is consumed on return. The next
	 *          sfreserve must read fresh from the FILE*.
	 *
	 * Both modes return cached data if present. The difference
	 * is on exit: LOCKR keeps f->data valid; non-LOCKR clears
	 * it so the next call reads fresh. This prevents the
	 * infinite loop in macro.c where non-LOCKR callers would
	 * see the same stale buffer forever.
	 */
	if(f->val > 0 && f->data)
	{
		void *ret = f->data;
		if(type & SH_IO_LOCKR)
			f->flags |= _SH_IO_RSVLCK;
		else
		{
			/* consumed: next sfreserve reads fresh */
			f->data = NULL;
			f->flags &= ~_SH_IO_RSVLCK;
		}
		return ret;
	}
	/* no cached data — clear stale state */
	f->val = 0;
	f->data = NULL;
	f->flags &= ~_SH_IO_RSVLCK;
	/* size 0: peek — check if data is available */
	if(size == 0)
	{
		int c = fgetc(f->fp);
		if(c == EOF)
		{
			f->val = 0;
			return NULL;
		}
		ungetc(c, f->fp);
		if(!f->buf)
		{
			f->buf = malloc(SH_IO_BUFSIZE);
			if(!f->buf)
			{
				f->val = 0;
				return NULL;
			}
			f->bufsz = SH_IO_BUFSIZE;
		}
		/*
		 * Peek just checks availability — the byte was
		 * pushed back via ungetc. Don't set f->data so
		 * the next sfreserve reads fresh from FILE*.
		 */
		f->val = 1;
		return f->buf;
	}
	if(size < 0)
		want = SH_IO_BUFSIZE;
	else
		want = (size_t)size;
	/* ensure buffer is large enough */
	if(!f->buf || want > f->bufsz)
	{
		size_t newsz = want > SH_IO_BUFSIZE ? want : SH_IO_BUFSIZE;
		char *nb = realloc(f->buf, newsz);
		if(!nb)
		{
			f->val = 0;
			return NULL;
		}
		f->buf = nb;
		f->bufsz = newsz;
	}
	got = fread(f->buf, 1, want, f->fp);
	if(got == 0)
	{
		f->val = 0;
		return NULL;
	}
	f->val = (ssize_t)got;
	f->data = (unsigned char*)f->buf;
	if(type & SH_IO_LOCKR)
		f->flags |= _SH_IO_RSVLCK;
	else
		f->data = NULL;	/* non-LOCKR: consumed on return */
	return f->buf;
}

/*
 * sfstack — push/pop stream stacking.
 * sfstack(f, NULL): pop top of f's stack, return it
 * sfstack(f, s):    push s onto f's stack, return f
 */
sh_stream_t *
sfstack(sh_stream_t *f1, sh_stream_t *f2)
{
	assert(f1 != f2 || f2 == NULL);	/* no self-stacking */
	if(!f1)
		return NULL;
	if(!f2)
	{
		/* pop: remove and return the top of f1's stack */
		sh_stream_t *top = f1->stack;
		if(top)
		{
			f1->stack = top->stack;
			top->stack = NULL;
		}
		return top;
	}
	/* push: put f2 on top of f1's stack */
	f2->stack = f1->stack;
	f1->stack = f2;
	return f1;
}

/*
 * sftmp: create a temporary read/write stream.
 *
 * sfio semantics: if size > 0, start as in-memory buffer and spill
 * to tmpfile when data exceeds size. We skip the memory optimization
 * and always use tmpfile() — ksh's tmp streams are small (PIPE_BUF)
 * and short-lived. If profiling shows a hot path, add the in-memory
 * optimization later.
 */
sh_stream_t *
sftmp(size_t size)
{
	FILE *fp;
	sh_stream_t *f;
	(void)size;
	fp = tmpfile();
	if(!fp)
		return NULL;
	f = sh_stream_new(fp, -1, SH_IO_READ | SH_IO_WRITE);
	if(!f)
	{
		fclose(fp);
		return NULL;
	}
	if(_sh_notify_fn)
		_sh_notify_fn(f, SH_IO_NEW, NULL);
	return f;
}

/*
 * sfgetr: read until delimiter, return NUL-terminated string.
 *
 * type == 0: return string including delimiter
 * type == 1 (SF_STRING): return NUL-terminated, delimiter stripped
 * type == -1 (SF_LASTR): return last incomplete line (no delimiter found)
 *
 * Returns pointer to f->getr_buf (reused across calls).
 * Sets sfvalue(f) to the length of the returned string.
 */
char *
sfgetr(sh_stream_t *f, int delim, int type)
{
	size_t len, cap;
	char *p;
	int c;
	if(!f || !f->fp)
		return NULL;
	/*
	 * type == -1 (SF_LASTR): return previously buffered incomplete
	 * line from a prior sfgetr call that hit EOF before the delimiter.
	 */
	if(type < 0)
	{
		if(f->getr_buf && f->val > 0)
			return f->getr_buf;
		return NULL;
	}
	/* accumulate into getr_buf */
	len = 0;
	cap = f->getr_bufsz;
	p = f->getr_buf;
	if(!p)
	{
		cap = 256;
		p = malloc(cap);
		if(!p)
			return NULL;
	}
	/* consume from sfreserve buffer first */
	while(f->val > 0 && f->data)
	{
		c = (unsigned char)*f->data++;
		f->val--;
		if(len + 2 >= cap)
		{
			cap = cap * 2;
			char *np = realloc(p, cap);
			if(!np)
			{
				f->getr_buf = p;
				f->getr_bufsz = cap / 2;
				return NULL;
			}
			p = np;
		}
		p[len++] = (char)c;
		if(c == delim)
			goto done;
	}
	/* read from FILE* one character at a time */
	while((c = fgetc(f->fp)) != EOF)
	{
		if(len + 2 >= cap)
		{
			cap = cap * 2;
			char *np = realloc(p, cap);
			if(!np)
			{
				f->getr_buf = p;
				f->getr_bufsz = cap / 2;
				return NULL;
			}
			p = np;
		}
		p[len++] = (char)c;
		if(c == delim)
			goto done;
	}
	/* EOF before delimiter — save for SF_LASTR retrieval */
	if(len == 0)
	{
		f->getr_buf = p;
		f->getr_bufsz = cap;
		f->val = 0;
		return NULL;
	}
	p[len] = '\0';
	f->getr_buf = p;
	f->getr_bufsz = cap;
	f->val = (ssize_t)len;
	return NULL;	/* no delimiter found — caller must use sfgetr(f,d,-1) */

done:
	/* type==1 (SF_STRING): strip delimiter, NUL-terminate */
	if(type == 1)
	{
		len--;	/* remove delimiter */
		p[len] = '\0';
	}
	else
	{
		/* type==0: keep delimiter, NUL-terminate after it */
		p[len] = '\0';
	}
	f->getr_buf = p;
	f->getr_bufsz = cap;
	f->val = (ssize_t)len;
	return p;
}

/*
 * sfmove: copy data between streams.
 *
 * delim < 0: n is byte count (bulk copy)
 * delim >= 0: n is record count (copy n delimited records)
 * n < 0 (SFIO_UNBOUND): copy until EOF
 * fw == NULL: discard (consume without writing)
 *
 * Returns number of items (bytes or records) moved.
 */
off_t
sfmove(sh_stream_t *fr, sh_stream_t *fw, off_t n, int delim)
{
	off_t moved;
	if(!fr)
		return -1;
	if(delim < 0)
	{
		/* byte mode: bulk copy */
		char buf[8192];
		moved = 0;
		for(;;)
		{
			size_t want, got;
			if(n >= 0)
			{
				want = (size_t)(n - moved);
				if(want > sizeof(buf))
					want = sizeof(buf);
				if(want == 0)
					break;
			}
			else
				want = sizeof(buf);
			/* consume from sfreserve buffer first */
			if(fr->val > 0 && fr->data)
			{
				got = (size_t)fr->val;
				if(got > want)
					got = want;
				if(fw)
					sfwrite(fw, fr->data, got);
				fr->data += got;
				fr->val -= (ssize_t)got;
				moved += (off_t)got;
				continue;
			}
			if(!fr->fp)
				break;
			got = fread(buf, 1, want, fr->fp);
			if(got == 0)
				break;
			if(fw)
				sfwrite(fw, buf, got);
			moved += (off_t)got;
		}
		return moved;
	}
	else
	{
		/* record mode: copy n delimited records */
		char *line;
		moved = 0;
		while(n < 0 || moved < n)
		{
			line = sfgetr(fr, delim, 0);
			if(!line)
			{
				/* try incomplete last line */
				line = sfgetr(fr, delim, -1);
				if(!line)
					break;
			}
			if(fw)
				sfwrite(fw, line, (size_t)sfvalue(fr));
			moved++;
			if(!line)
				break;
		}
		return moved;
	}
}

/*
 * sfpkrd: peek/read on a raw fd with timeout and record delimiter.
 *
 * fd:     file descriptor
 * buf:    read buffer
 * n:      buffer size
 * rc:     record delimiter (negative = no delimiter)
 * tm:     timeout in milliseconds (negative = block indefinitely)
 * action: >0 peek only, <=0 read, ==2 always use poll
 *
 * Returns bytes read/peeked, or -1 on error/timeout.
 */
ssize_t
sfpkrd(int fd, void *buf, size_t n, int rc, long tm, int action)
{
	ssize_t r;
	char *cbuf = (char*)buf;
	/* fast path: no delimiter, no timeout, no peeking */
	if(rc < 0 && tm < 0 && action <= 0)
		return read(fd, buf, n);
	/* use poll for timeout or availability check */
	if(tm >= 0 || action > 0)
	{
		struct pollfd pfd;
		int pr;
		pfd.fd = fd;
		pfd.events = POLLIN;
		pr = poll(&pfd, 1, (tm >= 0) ? (int)tm : -1);
		if(pr < 0)
			return -1;
		if(pr == 0)
			return -1;	/* timeout */
		if(!(pfd.revents & (POLLIN | POLLHUP)))
			return -1;
	}
	/* try socket peek if we need to look for a delimiter */
	if(action > 0 || (action == 0 && rc >= 0))
	{
		r = recv(fd, buf, n, MSG_PEEK);
		if(r < 0)
		{
			/* not a socket — fall through to read */
			if(errno == ENOTSOCK)
				goto do_read;
			return -1;
		}
		if(r == 0)
		{
			/* EOF — try read past it */
			if(action <= 0)
				return read(fd, buf, 1);
			return 0;
		}
		/* scan for record delimiter in peeked data */
		if(rc >= 0)
		{
			char *sp;
			int t = (action == 0) ? 1 : (action < 0) ? -action : action;
			for(sp = cbuf; sp < cbuf + r; sp++)
			{
				if(*sp == rc && --t == 0)
				{
					r = (sp - cbuf) + 1;
					break;
				}
			}
		}
		/* if peeking only, return peeked count */
		if(action > 0)
			return r;
		/* consume the peeked data */
		return read(fd, buf, (size_t)r);
	}
do_read:
	/* rc >= 0 but can't peek — read one byte at a time for delimiter */
	if(rc >= 0)
	{
		int nrec = action ? -action : 1;
		r = 0;
		while(nrec > 0)
		{
			ssize_t t = read(fd, cbuf + r, 1);
			if(t <= 0)
				break;
			if(cbuf[r] == rc)
				nrec--;
			r += t;
			if((size_t)r >= n)
				break;
		}
		return r > 0 ? r : -1;
	}
	return read(fd, buf, n);
}

/*
 * sfrd: read through discipline chain.
 * If the discipline has a readf, call it. Otherwise fall through
 * to raw read on the stream's fd.
 */
ssize_t
sfrd(sh_stream_t *f, void *buf, size_t n, sh_disc_t *disc)
{
	sh_disc_t *d;
	if(!f)
		return -1;
	/* walk discipline chain for a readf */
	for(d = disc ? disc : f->disc; d; d = d->disc)
	{
		if(d->readf)
			return d->readf(f, buf, n, d);
	}
	/* no discipline — raw read */
	if(f->fd >= 0)
		return read(f->fd, buf, n);
	if(f->fp)
		return (ssize_t)fread(buf, 1, n, f->fp);
	return -1;
}

/*
 * sfpoll: poll multiple streams for readiness.
 * Only 1 call site (mkservice.c, optional feature). Not implemented.
 */
int
sfpoll(sh_stream_t **fds, int n, int tm)
{
	(void)fds; (void)n; (void)tm;
	return -1;
}

/*
 * Variable-length integer encoding (sfio portable format).
 *
 * Unsigned: 7 data bits per byte, MSB=1 means more bytes follow.
 * Signed: terminal byte has 6 data bits + sign in bit 6;
 *         negative values stored as -(v+1) to avoid MIN_INT issues.
 *
 * Constants match sfio.h: SFIO_UBITS=7, SFIO_SBITS=6,
 * SFIO_MORE=0x80, SFIO_SIGN=0x40.
 */
#define _SFIO_UBITS	7
#define _SFIO_SBITS	6
#define _SFIO_MORE	0x80
#define _SFIO_SIGN	0x40
#define _SFIO_UVALUE(v)	((unsigned long)(v) & (_SFIO_MORE - 1))
#define _SFIO_SVALUE(v)	((long)(v) & (_SFIO_SIGN - 1))

int
sfputu(sh_stream_t *f, size_t v)
{
	unsigned char c[2 * sizeof(size_t)];
	unsigned char *s, *ps;
	int n;
	if(!f)
		return -1;
	s = ps = &c[sizeof(c) - 1];
	*s = (unsigned char)_SFIO_UVALUE(v);
	while((v >>= _SFIO_UBITS))
		*--s = (unsigned char)(_SFIO_UVALUE(v) | _SFIO_MORE);
	n = (int)(ps - s) + 1;
	if(sfwrite(f, s, (size_t)n) != (ssize_t)n)
		return -1;
	return n;
}

int
sfputl(sh_stream_t *f, ssize_t v)
{
	unsigned char c[2 * sizeof(ssize_t)];
	unsigned char *s, *ps;
	int n;
	size_t uv;
	if(!f)
		return -1;
	s = ps = &c[sizeof(c) - 1];
	if(v < 0)
	{
		v = -(v + 1);
		*s = (unsigned char)(_SFIO_SVALUE(v) | _SFIO_SIGN);
	}
	else
		*s = (unsigned char)_SFIO_SVALUE(v);
	uv = (size_t)v >> _SFIO_SBITS;
	while(uv > 0)
	{
		*--s = (unsigned char)(_SFIO_UVALUE(uv) | _SFIO_MORE);
		uv >>= _SFIO_UBITS;
	}
	n = (int)(ps - s) + 1;
	if(sfwrite(f, s, (size_t)n) != (ssize_t)n)
		return -1;
	return n;
}

ssize_t
sfgetu(sh_stream_t *f)
{
	size_t v;
	int c;
	if(!f)
		return (ssize_t)-1;
	v = 0;
	for(;;)
	{
		c = sfgetc(f);
		if(c == EOF)
		{
			f->flags |= SH_IO_ERROR;
			return (ssize_t)-1;
		}
		v = (v << _SFIO_UBITS) | _SFIO_UVALUE(c);
		if(!(c & _SFIO_MORE))
			return (ssize_t)v;
	}
}

ssize_t
sfgetl(sh_stream_t *f)
{
	ssize_t v;
	int c;
	if(!f)
		return (ssize_t)-1;
	v = 0;
	for(;;)
	{
		c = sfgetc(f);
		if(c == EOF)
		{
			f->flags |= SH_IO_ERROR;
			return (ssize_t)-1;
		}
		if(c & _SFIO_MORE)
			v = ((size_t)v << _SFIO_UBITS) | _SFIO_UVALUE(c);
		else
		{
			v = ((size_t)v << _SFIO_SBITS) | _SFIO_SVALUE(c);
			return (c & _SFIO_SIGN) ? -v - 1 : v;
		}
	}
}

/*
 * sfkeyprintf: formatted I/O with key lookup.
 * 0 call sites in ksh26. Not implemented.
 */
int
sfkeyprintf(sh_stream_t *f, void *handle, const char *fmt,
	int(*lookup)(void*,sh_stream_t*,off_t,const char*,int,sh_disc_t*,int),
	int(*convert)(void*,sh_stream_t*,const char*))
{
	(void)f; (void)handle; (void)fmt; (void)lookup; (void)convert;
	return -1;
}

#endif /* !KSH_IO_SFIO */

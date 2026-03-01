/***********************************************************************
*                                                                      *
*               This software is part of the ast package               *
*          Copyright (c) 1985-2012 AT&T Intellectual Property          *
*          Copyright (c) 2020-2026 Contributors to ksh 93u+m           *
*                      and is licensed under the                       *
*                 Eclipse Public License, Version 2.0                  *
*                                                                      *
*                A copy of the License is available at                 *
*      https://www.eclipse.org/org/documents/epl-2.0/EPL-2.0.html      *
*         (with md5 checksum 84283fa8859daf213bdda5a9f8d1be1d)         *
*                                                                      *
*                 Glenn Fowler <gsf@research.att.com>                  *
*                  David Korn <dgk@research.att.com>                   *
*                   Phong Vo <kpv@research.att.com>                    *
*                  Martijn Dekker <martijn@inlv.org>                   *
*            Johnothan King <johnothanking@protonmail.com>             *
*                                                                      *
***********************************************************************/
/*
 *   Routines to implement a stack-like storage library
 *
 *   A stack consists of a linked list of variable size frames.
 *   The beginning of each frame is initialized with a frame structure
 *   that contains a pointer to the previous frame and a pointer to the
 *   end of the current frame.
 *
 *   David Korn
 *   AT&T Research
 *   dgk@research.att.com
 *
 */

#include	<ast.h>
#include	<align.h>
#include	<stk.h>
#include	<string.h>
#include	<stdarg.h>
#include	<stdio.h>

/* ast_stdio.h remaps vsnprintf to _ast_vsnprintf (nonexistent); undo */
#undef vsnprintf
extern int vsnprintf(char *restrict, size_t, const char *restrict, va_list);

/*
 *  A stack is a header and a linked list of frames.
 *  The first frame has structure:
 *	Stk_t
 *	struct stk
 *  Subsequent frames have structure:
 *	struct frame
 *	data
 */

#define STK_ALIGN	ALIGN_BOUND
constexpr size_t STK_FSIZE = 1024 * sizeof(char*);
#define STK_HDRSIZE	(sizeof(Stk_t))

typedef void* (*_stk_overflow_)(size_t);
typedef char* (*_old_stk_overflow_)(size_t);	/* for stkinstall */

/* zero-initialized BSS */
Stk_t _Stak_data;

struct frame
{
	char	*prev;		/* address of previous frame */
	char	*end;		/* address of end this frame */
	char	**aliases;	/* address aliases */
	int	nalias;		/* number of aliases */
};

struct stk
{
	_stk_overflow_	stkoverflow;	/* called when malloc fails */
	unsigned int	stkref;		/* reference count */
	short		stkflags;	/* stack attributes */
	char		*stkbase;	/* beginning of current stack frame */
	char		*stkend;	/* end of current stack frame */
};

static size_t		init;		/* 1 when initialized */
static struct stk	*stkcur;	/* pointer to current stk */
[[nodiscard]] static char *stkgrow(Stk_t*, size_t);

#define stream2stk(stream)	((stream)==stkstd? stkcur:\
				 ((struct stk*)(((char*)(stream))+STK_HDRSIZE)))
#define stkleft(stream)		((stream)->_endb-(stream)->_data)

/* NUL sentinel: maintain *_next == 0 after every write */
#define STK_SENTINEL(sp)	do { if((sp)->_next && (sp)->_next < (sp)->_endb) *(sp)->_next = 0; } while(0)

static const char Omsg[] = "out of memory while growing stack\n";

/*
 * default overflow exception
 */
static noreturn void *overflow(size_t n)
{
	NoP(n);
	write(2,Omsg, sizeof(Omsg)-1);
	exit(128);
	UNREACHABLE();
}

/*
 * initialize stkstd
 */
static void stkinit(size_t size)
{
	Stk_t *sp;
	init = size;
	sp = stkopen(0);
	init = 1;
	stkinstall(sp,(_old_stk_overflow_)overflow);
}

/*
 * create a stack
 */
Stk_t *stkopen(int flags)
{
	size_t bsize;
	Stk_t *stream;
	struct stk *sp;
	struct frame *fp;
	char *cp;
	if(!(stream=calloc(1, sizeof(*stream) + sizeof(*sp))))
		return nullptr;
	sp = (struct stk*)(stream+1);
	sp->stkref = 1;
	sp->stkflags = flags;
	if(flags&STK_NULL) sp->stkoverflow = nullptr;
	else sp->stkoverflow = stkcur?stkcur->stkoverflow:overflow;
	bsize = init+sizeof(struct frame);
	if(flags&STK_SMALL)
		bsize = roundof(bsize,STK_FSIZE/16);
	else
		bsize = roundof(bsize,STK_FSIZE);
	bsize -= sizeof(struct frame);
	if(!(fp=calloc(1, sizeof(struct frame)+bsize)))
	{
		free(stream);
		return nullptr;
	}
	cp = (char*)(fp+1);
	sp->stkbase = (char*)fp;
	fp->prev = nullptr;
	fp->nalias = 0;
	fp->aliases = nullptr;
	fp->end = sp->stkend = cp+bsize;
	stream->_data = stream->_next = (unsigned char*)cp;
	stream->_endb = (unsigned char*)(cp+bsize);
	STK_SENTINEL(stream);
	return stream;
}

/*
 * return a pointer to the current stack
 * if <stream> is not null, it becomes the new current stack
 * <oflow> becomes the new overflow function
 */
Stk_t *stkinstall(Stk_t *stream, _old_stk_overflow_ oflow)
{
	Stk_t *old;
	struct stk *sp;
	if(!init)
	{
		stkinit(1);
		if(oflow)
			stkcur->stkoverflow = (_stk_overflow_)oflow;
		return nullptr;
	}
	old = stkcur? (Stk_t*)(((char*)stkcur)-STK_HDRSIZE) : nullptr;
	if(stream)
	{
		/* save outgoing stream's state back from stkstd */
		if(old && old != stkstd)
		{
			old->_data = stkstd->_data;
			old->_next = stkstd->_next;
			old->_endb = stkstd->_endb;
		}
		sp = stream2stk(stream);
		stkcur = sp;
		/* load incoming stream's state into stkstd */
		if(stream != stkstd)
		{
			stkstd->_data = stream->_data;
			stkstd->_next = stream->_next;
			stkstd->_endb = stream->_endb;
		}
	}
	else
		sp = stkcur;
	if(oflow)
		sp->stkoverflow = (_stk_overflow_)oflow;
	return old;
}

/*
 * set or unset the overflow function
 */
void stkoverflow(Stk_t *stream, _stk_overflow_ oflow)
{
	struct stk *sp;
	if(!init)
		stkinit(1);
	sp = stream2stk(stream);
	sp->stkoverflow = oflow ? oflow : (sp->stkflags & STK_NULL ? nullptr : overflow);
}

/*
 * increase the reference count on the given <stack>
 */
unsigned int stklink(Stk_t* stream)
{
	struct stk *sp = stream2stk(stream);
	return sp->stkref++;
}

/*
 * terminate a stack and free up the space
 * >0 returned if reference decremented but still > 0
 *  0 returned on last close
 * <0 returned on error
 */
int stkclose(Stk_t* stream)
{
	struct stk *sp = stream2stk(stream);
	char *cp;
	struct frame *fp;
	if(sp->stkref>1)
	{
		sp->stkref--;
		return 1;
	}
	if(stream==stkstd)
	{
		stkset(stream,nullptr,0);
	}
	else
	{
		cp = sp->stkbase;
		while(1)
		{
			fp = (struct frame*)cp;
			if(fp->prev)
			{
				cp = fp->prev;
				free(fp);
			}
			else
			{
				free(fp);
				break;
			}
		}
		free(stream);
	}
	return 0;
}

/*
 * reset the bottom of the current stack back to <address>
 * if <address> is null, then the stack is reset to the beginning
 * if <address> is not in this stack, the program dumps core
 * otherwise, the top of the stack is set to stkbot+<offset>
 */
void *stkset(Stk_t *stream, void *address, size_t offset)
{
	struct stk *sp = stream2stk(stream);
	char *cp, *loc = (char*)address;
	struct frame *fp;
	int frames = 0;
	int n;
	if(!init)
		stkinit(offset+1);
	while(1)
	{
		fp = (struct frame*)sp->stkbase;
		cp = sp->stkbase + roundof(sizeof(struct frame), STK_ALIGN);
		n = fp->nalias;
		while(n-->0)
		{
			if(loc==fp->aliases[n])
			{
				loc = cp;
				break;
			}
		}
		/* see whether <loc> is in current stack frame */
		if(loc>=cp && loc<=sp->stkend)
		{
			stream->_data = (unsigned char*)(cp + roundof(loc-cp,STK_ALIGN));
			stream->_next = (unsigned char*)loc+offset;
			if(frames)
				stream->_endb = (unsigned char*)sp->stkend;
			STK_SENTINEL(stream);
			goto found;
		}
		if(fp->prev)
		{
			sp->stkbase = fp->prev;
			sp->stkend = ((struct frame*)(fp->prev))->end;
			free(fp);
		}
		else
			break;
		frames++;
	}
	/* not found: produce a useful stack trace now instead of a useless one later */
	if(loc)
		abort();
	/* set stack back to the beginning */
	cp = (char*)(fp+1);
	stream->_data = stream->_next = (unsigned char*)cp;
	if(frames)
		stream->_endb = (unsigned char*)sp->stkend;
	STK_SENTINEL(stream);
found:
	return stream->_data;
}

/*
 * allocate <n> bytes on the current stack
 */
void *stkalloc(Stk_t *stream, size_t n)
{
	unsigned char *old;
	if(!init)
		stkinit(n);
	n = roundof(n,STK_ALIGN);
	if(stkleft(stream) <= n && !stkgrow(stream,n))
		return nullptr;
	old = stream->_data;
	stream->_data = stream->_next = old+n;
	STK_SENTINEL(stream);
	return old;
}

/*
 * begin a new stack word of at least <n> bytes
 */
void *_stkseek(Stk_t *stream, ssize_t n)
{
	if(n < 0)
		n = 0;
	if(!init)
		stkinit(n);
	if(stkleft(stream) <= n && !stkgrow(stream,n))
		return nullptr;
	stream->_next = stream->_data+n;
	/* no sentinel here: seek is a positioning op, not a write.
	 * code uses seek-back-and-read (e.g., sig_number in trap.c)
	 * where data above _next must be preserved. */
	return stream->_data;
}

/*
 * advance the stack to the current top
 * if extra is non-zero, first add extra bytes and zero the first
 */
void	*stkfreeze(Stk_t *stream, size_t extra)
{
	unsigned char *old, *top;
	if(!init)
		stkinit(extra);
	old = stream->_data;
	top = stream->_next;
	if(extra)
	{
		if(extra > (size_t)(stream->_endb-stream->_next))
		{
			if (!(top = (unsigned char*)stkgrow(stream,extra)))
				return nullptr;
			old = stream->_data;
		}
		*top = 0;
		top += extra;
	}
	stream->_next = stream->_data += roundof(top-old,STK_ALIGN);
	return (char*)old;
}

/*
 * copy string <str> onto the stack as a new stack word
 */
char	*stkcopy(Stk_t *stream, const char* str)
{
	unsigned char *cp = (unsigned char*)str;
	size_t n;
	size_t off=stktell(stream);
	char buff[40], *tp=buff;
	if(off)
	{
		if(off > sizeof(buff))
		{
			if(!(tp = malloc(off)))
			{
				struct stk *sp = stream2stk(stream);
				if(!sp->stkoverflow || !(tp = (*sp->stkoverflow)(off)))
					return nullptr;
			}
		}
		memcpy(tp, stream->_data, off);
	}
	while(*cp++);
	n = roundof(cp-(unsigned char*)str,STK_ALIGN);
	if(!init)
		stkinit(n);
	if(stkleft(stream) <= n && !stkgrow(stream,n))
		cp = 0;
	else
	{
		strcpy((char*)(cp=stream->_data),str);
		stream->_data = stream->_next = cp+n;
		if(off)
		{
			_stkseek(stream,off);
			memcpy(stream->_data, tp, off);
		}
	}
	if(tp!=buff)
		free(tp);
	return (char*)cp;
}

/*
 * add a new stack frame of size >= <n> to the current stack.
 * if <n> > 0, copy the bytes from stkbot to stktop to the new stack
 * if <n> is zero, then copy the remainder of the stack frame from stkbot
 * to the end is copied into the new stack frame
 */

[[nodiscard]]
static char *stkgrow(Stk_t *stream, size_t size)
{
	size_t n = size;
	struct stk *sp = stream2stk(stream);
	struct frame *fp= (struct frame*)sp->stkbase;
	char *cp, *dp=nullptr;
	size_t m = stktell(stream);
	size_t endoff;
	char *end=nullptr, *oldbase=nullptr;
	int nn=0,add=1;
	/* checked arithmetic: n = size + m + sizeof(struct frame) + 1 */
	if(ckd_add(&n, n, m) || ckd_add(&n, n, sizeof(struct frame)) || ckd_add(&n, n, 1))
		return nullptr;
	if(sp->stkflags&STK_SMALL)
		n = roundof_safe(n,STK_FSIZE/16);
	else
		n = roundof_safe(n,STK_FSIZE);
	if(n == (size_t)-1)
		return nullptr;
	/* see whether current frame can be extended */
	if(stkptr(stream,0)==sp->stkbase+sizeof(struct frame))
	{
		nn = fp->nalias+1;
		dp=sp->stkbase;
		sp->stkbase = ((struct frame*)dp)->prev;
		end = fp->end;
		oldbase = dp;
	}
	endoff = end - dp;
	{
		/* checked: total = n + nn*sizeof(char*) */
		size_t aliasz, total;
		if(ckd_mul(&aliasz, (size_t)nn, sizeof(char*)) || ckd_add(&total, n, aliasz))
			return nullptr;
		cp = realloc(dp, total);
		if(!cp)
		{
			if(!dp)
				cp = calloc(1, total);
			if(!cp && (!sp->stkoverflow || !(cp = (*sp->stkoverflow)(total))))
				return nullptr;
		}
	}
	if(dp==cp)
	{
		nn--;
		add = 0;
	}
	else if(dp)
	{
		dp = cp;
		end = dp + endoff;
	}
	fp = (struct frame*)cp;
	fp->prev = sp->stkbase;
	sp->stkbase = cp;
	sp->stkend = fp->end = cp+n;
	cp = (char*)(fp+1);
	cp = sp->stkbase + roundof((cp-sp->stkbase),STK_ALIGN);
	if((fp->nalias=nn))
	{
		fp->aliases = (char**)fp->end;
		if(end && nn>add)
			memmove(fp->aliases,end,(nn-add)*sizeof(char*));
		if(add)
			fp->aliases[nn-1] = oldbase + roundof(sizeof(struct frame),STK_ALIGN);
	}
	if(m && !dp)
		memcpy(cp,(char*)stream->_data,m);
	stream->_data = (unsigned char*)cp;
	stream->_next = (unsigned char*)(cp + m);
	stream->_endb = (unsigned char*)sp->stkend;
	STK_SENTINEL(stream);
	return (char*)stream->_next;
}

/*
 * Write functions — direct buffer operations with NUL sentinel.
 *
 * Invariant: after every write, if _next is non-NULL and _next < _endb,
 * then *_next == 0.  This replicates the implicit NUL-copy behavior of
 * sfputr (sfputr.c:102-104) that ~20 call sites depend on for valid
 * C strings from stkptr().
 */

int stkputc(Stk_t *sp, int c)
{
	if(!init)
		stkinit(1);
	if(sp->_next >= sp->_endb && !stkgrow(sp, 1))
		return -1;
	*sp->_next++ = (unsigned char)c;
	STK_SENTINEL(sp);
	return c;
}

ssize_t stkputs(Stk_t *sp, const char *s, int delim)
{
	size_t len = strlen(s);
	size_t need = (delim >= 0) ? len + 1 : len;
	if(!init)
		stkinit(need);
	/* request need+1 for sentinel room */
	if((size_t)(sp->_endb - sp->_next) <= need && !stkgrow(sp, need + 1))
		return -1;
	memcpy(sp->_next, s, len);
	sp->_next += len;
	if(delim >= 0)
		*sp->_next++ = (unsigned char)delim;
	STK_SENTINEL(sp);
	return (ssize_t)need;
}

ssize_t stkwrite(Stk_t *sp, const void *buf, size_t n)
{
	if(!init)
		stkinit(n);
	/* request n+1 for sentinel room */
	if((size_t)(sp->_endb - sp->_next) <= n && !stkgrow(sp, n + 1))
		return -1;
	memcpy(sp->_next, buf, n);
	sp->_next += n;
	STK_SENTINEL(sp);
	return (ssize_t)n;
}

ssize_t stknputc(Stk_t *sp, int c, size_t n)
{
	if(!init)
		stkinit(n);
	if((size_t)(sp->_endb - sp->_next) <= n && !stkgrow(sp, n + 1))
		return -1;
	memset(sp->_next, c, n);
	sp->_next += n;
	STK_SENTINEL(sp);
	return (ssize_t)n;
}

int stkvprintf(Stk_t *sp, const char *fmt, va_list ap)
{
	int n;
	size_t avail;
	va_list ap2;
	if(!init)
		stkinit(1);
	avail = sp->_endb - sp->_next;
	va_copy(ap2, ap);
	n = vsnprintf((char*)sp->_next, avail, fmt, ap2);
	va_end(ap2);
	if(n < 0)
		return -1;
	if((size_t)n >= avail)
	{
		/* retry with enough room: n+1 for vsnprintf NUL + 1 for sentinel */
		if(!stkgrow(sp, (size_t)n + 2))
			return -1;
		avail = sp->_endb - sp->_next;
		n = vsnprintf((char*)sp->_next, avail, fmt, ap);
		if(n < 0 || (size_t)n >= avail)
			return -1;
	}
	sp->_next += n;
	/* vsnprintf already wrote NUL at _next, satisfying sentinel */
	return n;
}

int stkprintf(Stk_t *sp, const char *fmt, ...)
{
	va_list ap;
	int n;
	va_start(ap, fmt);
	n = stkvprintf(sp, fmt, ap);
	va_end(ap);
	return n;
}

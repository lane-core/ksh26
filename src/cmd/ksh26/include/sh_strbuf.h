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
#ifndef _sh_strbuf_h_defined
#define _sh_strbuf_h_defined 1

/*
 * sh_strbuf.h — Dynamic string buffer for ksh26
 *
 * Abstracts sfio string streams (sfstropen/sfstruse/sfstrclose)
 * behind a backend-independent interface.
 *
 * KSH_IO_SFIO=1: thin wrappers around sfio string stream macros
 * KSH_IO_SFIO=0: wraps open_memstream (POSIX 2008)
 */

#include "sh_io.h"

#if KSH_IO_SFIO

/*
 * Under sfio, a string buffer IS a stream — sfstropen() returns
 * an Sfio_t* configured for in-memory I/O.  sh_strbuf_t aliases
 * sh_stream_t so existing code that passes string buffers to sf*
 * functions works unchanged.
 */
typedef sh_stream_t sh_strbuf_t;

/* lifecycle */
#define sh_strbuf_open() sfstropen()
#define sh_strbuf_close(s) sfstrclose(s)

/*
 * Finalize the buffer: append NUL, reset write position to start,
 * return pointer to the NUL-terminated string.  NULL on failure.
 */
#define sh_strbuf_use(s) sfstruse(s)

/* positioning */
#define sh_strbuf_seek(s, p, m) sfstrseek((s), (p), (m))
#define sh_strbuf_tell(s) sfstrtell(s)

/* raw access */
#define sh_strbuf_base(s) sfstrbase(s)
#define sh_strbuf_size(s) sfstrsize(s)

#else /* !KSH_IO_SFIO */

/*
 * open_memstream-backed string buffer.
 *
 * sh_stream_t is the first member (IS-A), so sh_strbuf_t* can be
 * cast to sh_stream_t* for use with sf* macros that operate on
 * the embedded ->fp.  The buf/len fields are managed by
 * open_memstream and updated on fflush/fclose.
 *
 * Portability (all ksh26 Tier 1 targets):
 *   glibc:   since 2.x
 *   musl:    since 1.0
 *   macOS:   since 11.0 (Big Sur, 2020)
 *   FreeBSD: since 9.0 (2012)
 *   OpenBSD: since 5.4 (2013)
 *   illumos: available
 */

typedef struct
{
	sh_stream_t stream; /* first member — IS-A sh_stream_t */
	char *buf;          /* open_memstream buffer */
	size_t len;         /* open_memstream length */
} sh_strbuf_t;

/* lifecycle — implemented in sh_io_stdio.c */
extern sh_strbuf_t *sh_strbuf_open(void);
extern char *sh_strbuf_use(sh_strbuf_t *);
extern int sh_strbuf_close(sh_strbuf_t *);

/* positioning */
extern off_t sh_strbuf_seek(sh_strbuf_t *, off_t, int);
extern off_t sh_strbuf_tell(sh_strbuf_t *);

/* raw access */
extern char *sh_strbuf_base(sh_strbuf_t *);
extern size_t sh_strbuf_size(sh_strbuf_t *);

#endif /* KSH_IO_SFIO */

#endif /* !_sh_strbuf_h_defined */

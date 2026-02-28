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
#define _sh_strbuf_h_defined	1

/*
 * sh_strbuf.h — Dynamic string buffer for ksh26
 *
 * Abstracts sfio string streams (sfstropen/sfstruse/sfstrclose)
 * behind a backend-independent interface.
 *
 * KSH_IO_SFIO=1: thin wrappers around sfio string stream macros
 * KSH_IO_SFIO=0 (future): wraps open_memstream (POSIX 2008)
 */

#include	"sh_io.h"

#if KSH_IO_SFIO

/*
 * Under sfio, a string buffer IS a stream — sfstropen() returns
 * an Sfio_t* configured for in-memory I/O.  sh_strbuf_t aliases
 * sh_stream_t so existing code that passes string buffers to sf*
 * functions works unchanged.
 */
typedef sh_stream_t	sh_strbuf_t;

/* lifecycle */
#define sh_strbuf_open()	sfstropen()
#define sh_strbuf_close(s)	sfstrclose(s)

/*
 * Finalize the buffer: append NUL, reset write position to start,
 * return pointer to the NUL-terminated string.  NULL on failure.
 */
#define sh_strbuf_use(s)	sfstruse(s)

/* positioning */
#define sh_strbuf_seek(s,p,m)	sfstrseek((s),(p),(m))
#define sh_strbuf_tell(s)	sfstrtell(s)

/* raw access */
#define sh_strbuf_base(s)	sfstrbase(s)
#define sh_strbuf_size(s)	sfstrsize(s)

#else /* !KSH_IO_SFIO */

/*
 * Future: open_memstream() based implementation.
 *
 * typedef struct {
 *     char   *buf;   allocated buffer (owned by memstream)
 *     size_t  len;   current length
 *     FILE   *fp;    from open_memstream(&buf, &len)
 * } sh_strbuf_t;
 *
 * sh_strbuf_open():  open_memstream + init struct
 * sh_strbuf_use():   fflush, NUL-terminate, return buf, reset pos
 * sh_strbuf_close(): fclose + free buf
 *
 * open_memstream portability (all ksh26 Tier 1 targets):
 *   glibc:   since 2.x
 *   musl:    since 1.0
 *   macOS:   since 11.0 (Big Sur, 2020)
 *   FreeBSD: since 9.0 (2012)
 *   OpenBSD: since 5.4 (2013)
 *   illumos: available
 */
#error "stdio strbuf backend not yet implemented — see REDESIGN.md Direction 12"

#endif /* KSH_IO_SFIO */

#endif /* !_sh_strbuf_h_defined */

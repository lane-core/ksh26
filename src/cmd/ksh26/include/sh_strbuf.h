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
 * Wraps sfio string streams (sfstropen/sfstruse/sfstrclose)
 * behind a ksh26-specific interface.
 *
 * Under sfio, a string buffer IS a stream — sfstropen() returns
 * an Sfio_t* configured for in-memory I/O. sh_strbuf_t aliases
 * sh_stream_t so existing code that passes string buffers to sf*
 * functions works unchanged.
 */

#include "sh_io.h"

typedef sh_stream_t sh_strbuf_t;

/* lifecycle */
#define sh_strbuf_open() sfstropen()
#define sh_strbuf_close(s) sfstrclose(s)

/*
 * Finalize the buffer: append NUL, reset write position to start,
 * return pointer to the NUL-terminated string.  nullptr on failure.
 */
#define sh_strbuf_use(s) sfstruse(s)

/* positioning */
#define sh_strbuf_seek(s, p, m) sfstrseek((s), (p), (m))
#define sh_strbuf_tell(s) sfstrtell(s)

/* raw access */
#define sh_strbuf_base(s) sfstrbase(s)
#define sh_strbuf_size(s) sfstrsize(s)

#endif /* !_sh_strbuf_h_defined */

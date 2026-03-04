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
***********************************************************************/

/*
 * ast_wbuf — Writer monad for string construction
 *
 * Backed by open_memstream(3). Makes the monadic lifecycle explicit:
 * open (unit) → write ops (tell) → use (extract) → close (finalize).
 *
 * Buffer ownership: open_memstream owns the buffer while the stream is
 * open. After ast_wbuf_use() (which calls fflush) the buffer pointer
 * is valid until the next write operation or ast_wbuf_close().
 * ast_wbuf_detach() transfers ownership to the caller.
 *
 * Design influences documented in notes/CITATIONS.md:
 * - Error return convention from antirez/sds (BSD-2-Clause)
 * - Static initializer and detach pattern from git strbuf (GPL-2.0,
 *   no code taken — general API design only)
 */

#ifndef _AST_WBUF_H
#define _AST_WBUF_H

#include <stdio.h>
#include <stdarg.h>
#include <stddef.h>

typedef struct ast_wbuf_s
{
	char *buf;  /* accumulated output (owned by open_memstream) */
	size_t len; /* length after last flush */
	FILE *fp;   /* backing stream */
} ast_wbuf_t;

/* stack/static initializer — enables lazy open via (w.fp != NULL) check */
#define AST_WBUF_INIT {NULL, 0, NULL}

/* lifecycle */
int ast_wbuf_open(ast_wbuf_t *);     /* unit: create write context */
char *ast_wbuf_use(ast_wbuf_t *);    /* extract: flush, rewind, return buf */
char *ast_wbuf_detach(ast_wbuf_t *); /* extract + close: caller must free */
void ast_wbuf_close(ast_wbuf_t *);   /* finalize: fclose + free buf */

/* tell operations (append to accumulated output) */
int ast_wbuf_printf(ast_wbuf_t *, const char *, ...);
int ast_wbuf_putc(ast_wbuf_t *, int);
int ast_wbuf_puts(ast_wbuf_t *, const char *);
size_t ast_wbuf_write(ast_wbuf_t *, const void *, size_t);

/* listen operations (query without side effects) */
size_t ast_wbuf_tell(ast_wbuf_t *); /* current write position */
char *ast_wbuf_base(ast_wbuf_t *);  /* base pointer (flushes first) */

/* censor operations (reshape accumulated output) */
int ast_wbuf_seek(ast_wbuf_t *, long, int);

#endif /* _AST_WBUF_H */

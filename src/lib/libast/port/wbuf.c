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
 * ast_wbuf — writer monad backed by open_memstream(3)
 *
 * See notes/CITATIONS.md for design influences.
 */

#include <ast_wbuf.h>
#include <assert.h>
#include <stdlib.h>
#include <string.h>

/*
 * unit: create a new write context
 */
int
ast_wbuf_open(ast_wbuf_t *w)
{
	assert(w != NULL);
	w->buf = NULL;
	w->len = 0;
	w->fp = open_memstream(&w->buf, &w->len);
	return w->fp ? 0 : -1;
}

/*
 * extract (&mut self → &str): flush buffer, rewind, return accumulated string.
 *
 * The returned pointer is valid until the next write operation (which may
 * cause open_memstream to realloc). The stream remains open for reuse.
 * Always rewinds, even on flush failure — fseek is zero-cost and avoids
 * compounding indeterminate stdio state from a failed fflush.
 *
 * open_memstream NUL-terminates at the high water mark, not the current
 * position. After rewind+shorter-write cycles, old data leaks without
 * an explicit NUL at the current position. We write one before flushing.
 */
char *
ast_wbuf_use(ast_wbuf_t *w)
{
	long end;
	assert(w != NULL && w->fp != NULL);
	end = ftell(w->fp);
	fputc('\0', w->fp);
	if (fflush(w->fp) < 0)
	{
		fseek(w->fp, 0, SEEK_SET);
		return NULL;
	}
	w->len = end;
	fseek(w->fp, 0, SEEK_SET);
	return w->buf;
}

/*
 * detach (self → String): flush, close stream, return caller-owned buffer.
 *
 * Consuming operation — the wbuf is reset to AST_WBUF_INIT (moved-from
 * state). The caller owns the returned buffer and must free() it.
 * Cleanup is unconditional: the stream is closed and the struct zeroed
 * regardless of whether the flush succeeded, like Rust's Drop.
 */
char *
ast_wbuf_detach(ast_wbuf_t *w)
{
	char *result;
	int ok;
	assert(w != NULL && w->fp != NULL);
	ok = fflush(w->fp) == 0;
	/* fclose does not free the buffer (open_memstream contract) */
	fclose(w->fp);
	result = ok ? w->buf : NULL;
	if (!ok)
		free(w->buf);
	/* moved-from state: assertions catch use-after-detach */
	w->buf = NULL;
	w->len = 0;
	w->fp = NULL;
	return result;
}

/*
 * finalize: close stream and free buffer
 */
void
ast_wbuf_close(ast_wbuf_t *w)
{
	assert(w != NULL);
	if (w->fp)
	{
		fclose(w->fp);
		free(w->buf);
	}
	w->buf = NULL;
	w->len = 0;
	w->fp = NULL;
}

/* --- tell operations (append) --- */

int
ast_wbuf_printf(ast_wbuf_t *w, const char *fmt, ...)
{
	va_list ap;
	int r;
	assert(w != NULL && w->fp != NULL);
	va_start(ap, fmt);
	r = vfprintf(w->fp, fmt, ap);
	va_end(ap);
	return r;
}

int
ast_wbuf_putc(ast_wbuf_t *w, int c)
{
	assert(w != NULL && w->fp != NULL);
	return fputc(c, w->fp);
}

int
ast_wbuf_puts(ast_wbuf_t *w, const char *s)
{
	assert(w != NULL && w->fp != NULL);
	return fputs(s, w->fp);
}

size_t
ast_wbuf_write(ast_wbuf_t *w, const void *buf, size_t n)
{
	assert(w != NULL && w->fp != NULL);
	return fwrite(buf, 1, n, w->fp);
}

/* --- listen operations (query) --- */

size_t
ast_wbuf_tell(ast_wbuf_t *w)
{
	long pos;
	assert(w != NULL && w->fp != NULL);
	pos = ftell(w->fp);
	return pos >= 0 ? (size_t)pos : 0;
}

char *
ast_wbuf_base(ast_wbuf_t *w)
{
	assert(w != NULL && w->fp != NULL);
	fflush(w->fp);
	return w->buf;
}

/* --- censor operations (reshape) --- */

int
ast_wbuf_seek(ast_wbuf_t *w, long pos, int whence)
{
	assert(w != NULL && w->fp != NULL);
	return fseek(w->fp, pos, whence);
}

/***********************************************************************
*                                                                      *
*               This software is part of the ast package               *
*          Copyright (c) 1985-2011 AT&T Intellectual Property          *
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
 * Glenn Fowler
 * AT&T Research
 *
 * error and message formatter
 *
 *	level is the error level
 *	level >= error_info.core!=0 dumps core
 *	level >= ERROR_FATAL calls error_info.exit
 *	level < 0 is for debug tracing
 *
 * NOTE: id && ERROR_NOID && !ERROR_USAGE implies format=id for errmsg()
 */

#include "lclib.h"

#include <ctype.h>
#include <ccode.h>
#include <namval.h>
#include <sig.h>
#include <stk.h>
#include <times.h>
#include <regex.h>

/*
 * 2007-03-19 move error_info from _error_info_ to (*_error_infop_)
 *	      to allow future Error_info_t growth
 */

static Error_info_t _error_info_ =
    {
        2, exit, write,
        0, 0, 0, 0, 0, 0, 0, 0,
        0,                   /* version			*/
        0,                   /* auxiliary			*/
        0, 0, 0, 0, 0, 0, 0, /* top of old context stack	*/
        0, 0, 0, 0, 0, 0, 0, /* old empty context		*/
        0,                   /* time				*/
        translate,
        0 /* catalog			*/
};
Error_info_t *_error_infop_ = &_error_info_;

/*
 * these should probably be in error_info
 */

static struct State_s
{
	char *prefix;
	FILE *tty;
	unsigned long count;
	int breakpoint;
	regex_t *match;
} error_state;

#undef ERROR_CATALOG
#define ERROR_CATALOG (ERROR_LIBRARY << 1)

#define OPT_BREAK 1
#define OPT_CATALOG 2
#define OPT_CORE 3
#define OPT_COUNT 4
#define OPT_FD 5
#define OPT_LIBRARY 6
#define OPT_MASK 7
#define OPT_MATCH 8
#define OPT_PREFIX 9
#define OPT_SYSTEM 10
#define OPT_TIME 11
#define OPT_TRACE 12

static const Namval_t options[] =
    {
        "break", OPT_BREAK,
        "catalog", OPT_CATALOG,
        "core", OPT_CORE,
        "count", OPT_COUNT,
        "debug", OPT_TRACE,
        "fd", OPT_FD,
        "library", OPT_LIBRARY,
        "mask", OPT_MASK,
        "match", OPT_MATCH,
        "prefix", OPT_PREFIX,
        "system", OPT_SYSTEM,
        "time", OPT_TIME,
        "trace", OPT_TRACE,
        0, 0};

/*
 * called by stropt() to set options
 */

static int
setopt(void *a, const void *p, int n, const char *v)
{
	NoP(a);
	if(p)
		switch(((Namval_t *)p)->value)
		{
			case OPT_BREAK:
			case OPT_CORE:
				if(n)
					switch(*v)
					{
						case 'e':
						case 'E':
							error_state.breakpoint = ERROR_ERROR;
							break;
						case 'f':
						case 'F':
							error_state.breakpoint = ERROR_FATAL;
							break;
						case 'p':
						case 'P':
							error_state.breakpoint = ERROR_PANIC;
							break;
						default:
							error_state.breakpoint = strtol(v, NULL, 0);
							break;
					}
				else
					error_state.breakpoint = 0;
				if(((Namval_t *)p)->value == OPT_CORE)
					error_info.core = error_state.breakpoint;
				break;
			case OPT_CATALOG:
				if(n)
					error_info.set |= ERROR_CATALOG;
				else
					error_info.clear |= ERROR_CATALOG;
				break;
			case OPT_COUNT:
				if(n)
					error_state.count = strtol(v, NULL, 0);
				else
					error_state.count = 0;
				break;
			case OPT_FD:
				error_info.fd = n ? strtol(v, NULL, 0) : -1;
				break;
			case OPT_LIBRARY:
				if(n)
					error_info.set |= ERROR_LIBRARY;
				else
					error_info.clear |= ERROR_LIBRARY;
				break;
			case OPT_MASK:
				if(n)
					error_info.mask = strtol(v, NULL, 0);
				else
					error_info.mask = 0;
				break;
			case OPT_MATCH:
				if(error_state.match)
					regfree(error_state.match);
				if(n)
				{
					if((error_state.match || (error_state.match = newof(0, regex_t, 1, 0))) && regcomp(error_state.match, v, REG_EXTENDED | REG_LENIENT))
					{
						free(error_state.match);
						error_state.match = 0;
					}
				}
				else if(error_state.match)
				{
					free(error_state.match);
					error_state.match = 0;
				}
				break;
			case OPT_PREFIX:
				if(n)
					error_state.prefix = strdup(v);
				else if(error_state.prefix)
				{
					free(error_state.prefix);
					error_state.prefix = 0;
				}
				break;
			case OPT_SYSTEM:
				if(n)
					error_info.set |= ERROR_SYSTEM;
				else
					error_info.clear |= ERROR_SYSTEM;
				break;
			case OPT_TIME:
				error_info.time = n ? 1 : 0;
				break;
			case OPT_TRACE:
				if(n)
					error_info.trace = -strtol(v, NULL, 0);
				else
					error_info.trace = 0;
				break;
		}
	return 0;
}

/*
 * print a name with optional delimiter, converting unprintable chars
 */

static void
print(Stk_t *sp, char *name, char *delim)
{
	if(mbwide())
		stkputs(sp, name, -1);
	else
	{
		/* the following code assumes ASCII */
		int c;

		while(c = *name++)
		{
			if(c & 0200)
			{
				c &= 0177;
				stkputc(sp, '?');
			}
			if(c < ' ')
			{
				c += 'A' - 1;
				stkputc(sp, '^');
			}
			stkputc(sp, c);
		}
	}
	if(delim)
		stkputs(sp, delim, -1);
}

/*
 * print error context FIFO stack
 */

static void
context(Stk_t *sp, Error_context_t *cp)
{
	if(cp->context)
		context(sp, cp->context);
	if(!(cp->flags & ERROR_SILENT))
	{
		if(cp->id)
			print(sp, cp->id, NULL);
		if(cp->line > ((cp->flags & ERROR_INTERACTIVE) != 0))
		{
			if(cp->file)
				stkprintf(sp, ": \"%s\", %s %d", cp->file, ERROR_translate(NULL, NULL, ast.id, "line"), cp->line);
			else
				stkprintf(sp, "[%d]", cp->line);
		}
		stkputs(sp, ": ", -1);
	}
}

/*
 * debugging breakpoint
 */

extern void
error_break(void)
{
	char *s;

	if(error_state.tty || (error_state.tty = fopen("/dev/tty", "r+")))
	{
		fprintf(error_state.tty, "error breakpoint: ");
		char tbuf[256];
		if((s = fgets(tbuf, sizeof(tbuf), error_state.tty)) != NULL)
		{
			/* strip trailing newline (sfgetr did this implicitly) */
			size_t tlen = strlen(s);
			if(tlen > 0 && s[tlen - 1] == '\n')
				s[tlen - 1] = '\0';
			if(streq(s, "q") || streq(s, "quit"))
				exit(0);
			stropt(s, options, sizeof(*options), setopt, NULL);
		}
	}
}

void error(int level, ...)
{
	va_list ap;

	va_start(ap, level);
	errorv(NULL, level, ap);
	va_end(ap);
}

void errorv(const char *id, int level, va_list ap)
{
	int n;
	int fd;
	int flags;
	char *s;
	char *t;
	char *format;
	char *library;
	const char *catalog;

	int line;
	char *file;

	unsigned long d;
	struct tms us;

	if(!error_info.init)
	{
		error_info.init = 1;
		stropt(getenv("ERROR_OPTIONS"), options, sizeof(*options), setopt, NULL);
	}
	if(level > 0)
	{
		flags = level & ~ERROR_LEVEL;
		level &= ERROR_LEVEL;
	}
	else
		flags = 0;
	if((flags & (ERROR_USAGE | ERROR_NOID)) == ERROR_NOID)
	{
		format = (char *)id;
		id = 0;
	}
	else
		format = 0;
	if(id)
	{
		catalog = (char *)id;
		if(!*catalog || *catalog == ':')
		{
			catalog = 0;
			library = 0;
		}
		else if((library = strchr(catalog, ':')) && !*++library)
			library = 0;
	}
	else
	{
		catalog = 0;
		library = 0;
	}
	if(catalog)
		id = 0;
	else
	{
		id = (const char *)error_info.id;
		catalog = error_info.catalog;
	}
	if(level < error_info.trace || (flags & ERROR_LIBRARY) && !(((error_info.set | error_info.flags) ^ error_info.clear) & ERROR_LIBRARY) || level < 0 && error_info.mask && !(error_info.mask & (1 << (-level - 1))))
	{
		if(level >= ERROR_FATAL)
			(*error_info.exit)(level - 1);
		return;
	}
	if(error_info.trace < 0)
		flags |= ERROR_LIBRARY | ERROR_SYSTEM;
	flags |= error_info.set | error_info.flags;
	flags &= ~error_info.clear;
	if(!library)
		flags &= ~ERROR_LIBRARY;
	fd = (flags & ERROR_OUTPUT) ? va_arg(ap, int) : error_info.fd;
	if(error_info.write)
	{
		long off;
		char *bas;

		bas = stkptr(stkstd, 0);
		if(off = stktell(stkstd))
			stkfreeze(stkstd, 0);
		file = error_info.id;
		if(error_state.prefix)
			stkprintf(stkstd, "%s: ", error_state.prefix);
		if(flags & ERROR_USAGE)
		{
			if(flags & ERROR_NOID)
				stkprintf(stkstd, "       ");
			else
				stkprintf(stkstd, "%s: ", ERROR_translate(NULL, NULL, ast.id, "Usage"));
			if(file || opt_info.argv && (file = opt_info.argv[0]))
				print(stkstd, file, " ");
		}
		else
		{
			if(level && !(flags & ERROR_NOID))
			{
				if(error_info.context && level > 0)
					context(stkstd, error_info.context);
				if(file)
					print(stkstd, file, (flags & ERROR_LIBRARY) ? " " : ": ");
				if(flags & (ERROR_CATALOG | ERROR_LIBRARY))
				{
					stkprintf(stkstd, "[");
					if(flags & ERROR_CATALOG)
						stkprintf(stkstd, "%s %s%s",
						          catalog ? catalog : ERROR_translate(NULL, NULL, ast.id, "DEFAULT"),
						          ERROR_translate(NULL, NULL, ast.id, "catalog"),
						          (flags & ERROR_LIBRARY) ? ", " : "");
					if(flags & ERROR_LIBRARY)
						stkprintf(stkstd, "%s %s",
						          library,
						          ERROR_translate(NULL, NULL, ast.id, "library"));
					stkprintf(stkstd, "]: ");
				}
			}
			if(level > 0 && error_info.line > ((flags & ERROR_INTERACTIVE) != 0))
			{
				if(error_info.file && *error_info.file)
					stkprintf(stkstd, "\"%s\", ", error_info.file);
				stkprintf(stkstd, "%s %d: ", ERROR_translate(NULL, NULL, ast.id, "line"), error_info.line);
			}
		}
		if(error_info.time)
		{
			if((d = times(&us)) < error_info.time || error_info.time == 1)
				error_info.time = d;
			stkprintf(stkstd, " %05lu.%05lu.%05lu ", d - error_info.time, (unsigned long)us.tms_utime, (unsigned long)us.tms_stime);
		}
		switch(level)
		{
			case 0:
				flags &= ~ERROR_SYSTEM;
				break;
			case ERROR_WARNING:
				stkprintf(stkstd, "%s: ", ERROR_translate(NULL, NULL, ast.id, "warning"));
				break;
			case ERROR_PANIC:
				stkprintf(stkstd, "%s: ", ERROR_translate(NULL, NULL, ast.id, "panic"));
				break;
			default:
				if(level < 0)
				{
					s = ERROR_translate(NULL, NULL, ast.id, "debug");
					if(error_info.trace < -1)
						stkprintf(stkstd, "%s%d:%s", s, level, level > -10 ? " " : "");
					else
						stkprintf(stkstd, "%s: ", s);
					for(n = 0; n < error_info.indent; n++)
					{
						stkputc(stkstd, ' ');
						stkputc(stkstd, ' ');
					}
				}
				break;
		}
		if(flags & ERROR_SOURCE)
		{
			/*
			 * source ([version], file, line) message
			 */

			file = va_arg(ap, char *);
			line = va_arg(ap, int);
			s = ERROR_translate(NULL, NULL, ast.id, "line");
			if(error_info.version)
				stkprintf(stkstd, "(%s: \"%s\", %s %d) ", error_info.version, file, s, line);
			else
				stkprintf(stkstd, "(\"%s\", %s %d) ", file, s, line);
		}
		if(format || (format = va_arg(ap, char *)))
		{
			if(!(flags & ERROR_USAGE))
				format = ERROR_translate(NULL, id, catalog, format);
			stkvprintf(stkstd, format, ap);
		}
		if(!(flags & ERROR_PROMPT))
		{
			/*
			 * level&ERROR_OUTPUT on return means message
			 * already output
			 */

			if((flags & ERROR_SYSTEM) && errno && errno != error_info.last_errno)
			{
				stkprintf(stkstd, " [%s]", strerror(errno));
				if(error_info.set & ERROR_SYSTEM)
					errno = 0;
				error_info.last_errno = (level >= 0) ? 0 : errno;
			}
			if(error_info.auxiliary && level >= 0)
				level = (*error_info.auxiliary)((void *)stkstd, level, flags);
			stkputc(stkstd, '\n');
		}
		if(level > 0)
		{
			if((level & ~ERROR_OUTPUT) > 1)
				error_info.errors++;
			else
				error_info.warnings++;
		}
		if(level < 0 || !(level & ERROR_OUTPUT))
		{
			n = stktell(stkstd);
			s = stkptr(stkstd, 0);
			if(t = memchr(s, '\f', n))
			{
				n -= ++t - s;
				s = t;
			}
			sfsync(sfstdout);
			sfsync(sfstderr);
			if(fd == sffileno(sfstderr) && error_info.write == write)
			{
				sfwrite(sfstderr, s, n);
				sfsync(sfstderr);
			}
			else
				(*error_info.write)(fd, s, n);
		}
		else
		{
			s = 0;
			level &= ERROR_LEVEL;
		}
		stkset(stkstd, bas, off);
	}
	else
		s = 0;
	if(level >= error_state.breakpoint && error_state.breakpoint && (!error_state.match || !regexec(error_state.match, s ? s : format, 0, NULL, 0)) && (!error_state.count || !--error_state.count))
	{
		if(error_info.core)
		{
#ifndef SIGABRT
#ifdef SIGQUIT
#define SIGABRT SIGQUIT
#else
#ifdef SIGIOT
#define SIGABRT SIGIOT
#endif
#endif
#endif
#ifdef SIGABRT
			signal(SIGABRT, SIG_DFL);
			kill(getpid(), SIGABRT);
			pause();
#else
			abort();
#endif
		}
		else
			error_break();
	}
	if(level >= ERROR_FATAL)
		(*error_info.exit)(level - ERROR_FATAL + 1);
}

/***********************************************************************
*                                                                      *
*               This software is part of the ast package               *
*          Copyright (c) 1985-2011 AT&T Intellectual Property          *
*          Copyright (c) 2020-2023 Contributors to ksh 93u+m           *
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
 * AT&T Research
 *
 * output printf prompt and read response
 * if format==0 then verify that interaction is possible
 *
 * return:
 *
 *	0	[1yY+]
 *	-1	[qQ] or EOF
 *	1	otherwise
 *
 * if (quit&ERROR_PROMPT) then tty forced for IO
 * if quit>=0 then [qQ] or EOF calls exit(quit)
 */

#include <ast.h>
#include <error.h>

int
astquery(int quit, const char* format, ...)
{
	va_list		ap;
	int		n;
	int		c;
	int		r;
	FILE*		ip;
	FILE*		op;

	static FILE*	rfp;
	static FILE*	wfp;

	r = 0;
	va_start(ap, format);
	if (!format)
		goto done;
	r = -1;
	if (!rfp)
	{
		c = errno;
		if (isatty(fileno(stdin)))
			rfp = stdin;
		else if (!(rfp = fopen("/dev/tty", "r")))
			goto done;
		if (isatty(fileno(stderr)))
			wfp = stderr;
		else if (!(wfp = fopen("/dev/tty", "w")))
			goto done;
		errno = c;
	}
	if (quit & ERROR_PROMPT)
	{
		quit &= ~ERROR_PROMPT;
		ip = rfp;
		op = wfp;
	}
	else
	{
		ip = stdin;
		op = stderr;
	}
	fflush(stdout);
	vfprintf(op, format, ap);
	fflush(op);
	for (n = c = fgetc(ip);; c = fgetc(ip))
		switch (c)
		{
		case EOF:
			n = c;
			/* FALLTHROUGH */
		case '\n':
			switch (n)
			{
			case EOF:
			case 'q':
			case 'Q':
				if (quit >= 0)
					exit(quit);
				goto done;
			case '1':
			case 'y':
			case 'Y':
			case '+':
				r = 0;
				goto done;
			}
			return 1;
		}
 done:
	va_end(ap);
	return r;
}

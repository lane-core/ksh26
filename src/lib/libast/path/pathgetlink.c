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
*                                                                      *
***********************************************************************/
/*
* Glenn Fowler
* AT&T Bell Laboratories
*/

#include <ast.h>

/*
 * return external representation for symbolic link text of name in buf
 * the link text string length is returned
 */

int
pathgetlink(const char* name, char* buf, int siz)
{
	int	n;

	if ((n = readlink(name, buf, siz)) < 0) return -1;
	if (n >= siz)
	{
		errno = EINVAL;
		return -1;
	}
	buf[n] = 0;
	return n;
}

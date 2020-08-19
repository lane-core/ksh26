/***********************************************************************
*                                                                      *
*               This software is part of the ast package               *
*          Copyright (c) 1985-2012 AT&T Intellectual Property          *
*                      and is licensed under the                       *
*                 Eclipse Public License, Version 1.0                  *
*                    by AT&T Intellectual Property                     *
*                                                                      *
*                A copy of the License is available at                 *
*          http://www.eclipse.org/org/documents/epl-v10.html           *
*         (with md5 checksum b35adb5213ca9657e911e9befb180842)         *
*                                                                      *
*              Information and Software Systems Research               *
*                            AT&T Research                             *
*                           Florham Park NJ                            *
*                                                                      *
*                 Glenn Fowler <gsf@research.att.com>                  *
*                  David Korn <dgk@research.att.com>                   *
*                   Phong Vo <kpv@research.att.com>                    *
*                                                                      *
***********************************************************************/
#include	"sfhdr.h"

#if !_socket_peek
#if __APPLE__
#error The socket_peek feature is required. (Hey Apple, revert your src__lib__libast__features__lib.diff patch; it caused multiple regressions, and the hanging bug it fixed is now fixed correctly. See <https://github.com/ksh93/ksh/issues/118>.)
#else
#error The socket_peek feature is required.
#endif
#endif

/*	Read/Peek a record from an unseekable device
**
**	Written by Kiem-Phong Vo.
*/

#if __STD_C
ssize_t sfpkrd(int fd, Void_t* argbuf, size_t n, int rc, long tm, int action)
#else
ssize_t sfpkrd(fd, argbuf, n, rc, tm, action)
int	fd;	/* file descriptor */
Void_t*	argbuf;	/* buffer to read data */
size_t	n;	/* buffer size */
int	rc;	/* record character */
long	tm;	/* time-out */
int	action;	/* >0: peeking, if rc>=0, get action records,
		   <0: no peeking, if rc>=0, get -action records,
		   =0: no peeking, if rc>=0, must get a single record
		*/
#endif
{
	reg ssize_t	r;
	reg int		t;
	reg char	*buf = (char*)argbuf, *endbuf;

	if(rc < 0 && tm < 0 && action <= 0)
		return sysreadf(fd,buf,n);

	r = -1;
	t = action > 0 || rc >= 0;	/* socket peek using recv(2)? */
	if(t)
	{	while(t && (r = recv(fd,(char*)buf,n,MSG_PEEK)) < 0)
		{	if(errno == EINTR)
				return -1;
			else if(errno == EAGAIN)
				errno = 0;
			else	t = 0;
		}
		if(r == 0)
		{	/* read past eof */
			if(action <= 0)
				r = sysreadf(fd,buf,1);
			return r;
		}
	}

	if(r < 0)
	{	if(tm >= 0 || action > 0)
			return -1;
		else /* get here means: tm < 0 && action <= 0 && rc >= 0 */
		{	/* number of records read at a time */
			if((action = action ? -action : 1) > (int)n)
				action = n;
			r = 0;
			while((t = sysreadf(fd,buf,action)) > 0)
			{	r += t;
				for(endbuf = buf+t; buf < endbuf;)
					if(*buf++ == rc)
						action -= 1;
				if(action == 0 || (int)(n-r) < action)
					break;
			}
			return r == 0 ? t : r;
		}
	}

	/* successful peek, find the record end */
	if(rc >= 0)
	{	reg char*	sp;	

		t = action == 0 ? 1 : action < 0 ? -action : action;
		for(endbuf = (sp = buf)+r; sp < endbuf; )
			if(*sp++ == rc)
				if((t -= 1) == 0)
					break;
		r = sp - buf;
	}

	/* advance */
	if(action <= 0)
		r = sysreadf(fd,buf,r);

	return r;
}

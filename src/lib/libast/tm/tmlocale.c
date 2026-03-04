/***********************************************************************
*                                                                      *
*               This software is part of the ast package               *
*          Copyright (c) 1985-2011 AT&T Intellectual Property          *
*          Copyright (c) 2020-2024 Contributors to ksh 93u+m           *
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
 * time conversion translation support
 */

#include <ast.h>
#include <ast_wbuf.h>
#include <cdt.h>
#include <iconv.h>
#include <mc.h>
#include <tm.h>
#include <ast_nl_types.h>

#include "lclib.h"

static struct
{
	char *format;
	Lc_info_t *locale;
	char null[1];
} state;

/*
 * this is Unix dadgummit
 */

static int
standardized(Lc_info_t *li, char **b)
{
	if((li->lc->language->flags & (LC_debug | LC_default)) || streq(li->lc->language->code, "en"))
	{
		b[TM_TIME] = "%H:%M:%S";
		b[TM_DATE] = "%m/%d/%y";
		b[TM_DEFAULT] = "%a %b %e %T %Z %Y";
		return 1;
	}
	return 0;
}

/*
 * fix up LC_TIME data after loading
 */

static void
fixup(Lc_info_t *li, char **b)
{
	char **v;
	char **e;
	int n;

	static int must[] =
	    {
	        TM_TIME,
	        TM_DATE,
	        TM_DEFAULT,
	        TM_MERIDIAN,
	        TM_UT,
	        TM_DT,
	        TM_SUFFIXES,
	        TM_PARTS,
	        TM_HOURS,
	        TM_DAYS,
	        TM_LAST,
	        TM_THIS,
	        TM_NEXT,
	        TM_EXACT,
	        TM_NOISE,
	        TM_ORDINAL,
	        TM_CTIME,
	        TM_DATE_1,
	        TM_INTERNATIONAL,
	        TM_RECENT,
	        TM_DISTANT,
	        TM_MERIDIAN_TIME,
	        TM_ORDINALS,
	        TM_FINAL,
	        TM_WORK,
	    };

	standardized(li, b);
	for(v = b, e = b + TM_NFORM; v < e; v++)
		if(!*v)
			*v = state.null;
	for(n = 0; n < elementsof(must); n++)
		if(!*b[must[n]])
			b[must[n]] = tm_data.format[must[n]];
	if(li->lc->flags & LC_default)
		for(n = 0; n < TM_NFORM; n++)
			if(!*b[n])
				b[n] = tm_data.format[n];
	if(strchr(b[TM_UT], '%'))
	{
		tm_info.deformat = b[TM_UT];
		for(n = TM_UT; n < TM_DT; n++)
			b[n] = state.null;
	}
	else
		tm_info.deformat = b[TM_DEFAULT];
	tm_info.format = b;
	if(!(tm_info.deformat = state.format))
		tm_info.deformat = tm_info.format[TM_DEFAULT];
	li->data = b;
}

#if _lib_nl_langinfo && _hdr_langinfo

#if _hdr_nl_types
#include <nl_types.h>
#endif

#include <langinfo.h>

typedef struct Map_s
{
	int native;
	int local;
} Map_t;

static const Map_t map[] =
    {
        AM_STR,
        (TM_MERIDIAN + 0),
        PM_STR,
        (TM_MERIDIAN + 1),
        ABDAY_1,
        (TM_DAY_ABBREV + 0),
        ABDAY_2,
        (TM_DAY_ABBREV + 1),
        ABDAY_3,
        (TM_DAY_ABBREV + 2),
        ABDAY_4,
        (TM_DAY_ABBREV + 3),
        ABDAY_5,
        (TM_DAY_ABBREV + 4),
        ABDAY_6,
        (TM_DAY_ABBREV + 5),
        ABDAY_7,
        (TM_DAY_ABBREV + 6),
        ABMON_1,
        (TM_MONTH_ABBREV + 0),
        ABMON_2,
        (TM_MONTH_ABBREV + 1),
        ABMON_3,
        (TM_MONTH_ABBREV + 2),
        ABMON_4,
        (TM_MONTH_ABBREV + 3),
        ABMON_5,
        (TM_MONTH_ABBREV + 4),
        ABMON_6,
        (TM_MONTH_ABBREV + 5),
        ABMON_7,
        (TM_MONTH_ABBREV + 6),
        ABMON_8,
        (TM_MONTH_ABBREV + 7),
        ABMON_9,
        (TM_MONTH_ABBREV + 8),
        ABMON_10,
        (TM_MONTH_ABBREV + 9),
        ABMON_11,
        (TM_MONTH_ABBREV + 10),
        ABMON_12,
        (TM_MONTH_ABBREV + 11),
        DAY_1,
        (TM_DAY + 0),
        DAY_2,
        (TM_DAY + 1),
        DAY_3,
        (TM_DAY + 2),
        DAY_4,
        (TM_DAY + 3),
        DAY_5,
        (TM_DAY + 4),
        DAY_6,
        (TM_DAY + 5),
        DAY_7,
        (TM_DAY + 6),
        MON_1,
        (TM_MONTH + 0),
        MON_2,
        (TM_MONTH + 1),
        MON_3,
        (TM_MONTH + 2),
        MON_4,
        (TM_MONTH + 3),
        MON_5,
        (TM_MONTH + 4),
        MON_6,
        (TM_MONTH + 5),
        MON_7,
        (TM_MONTH + 6),
        MON_8,
        (TM_MONTH + 7),
        MON_9,
        (TM_MONTH + 8),
        MON_10,
        (TM_MONTH + 9),
        MON_11,
        (TM_MONTH + 10),
        MON_12,
        (TM_MONTH + 11),
#ifdef _DATE_FMT
        _DATE_FMT,
        TM_DEFAULT,
#else
        D_T_FMT,
        TM_DEFAULT,
#endif
        D_FMT,
        TM_DATE,
        T_FMT,
        TM_TIME,
#ifdef ERA
        ERA,
        TM_ERA,
        ERA_D_T_FMT,
        TM_ERA_DEFAULT,
        ERA_D_FMT,
        TM_ERA_DATE,
        ERA_T_FMT,
        TM_ERA_TIME,
#endif
#ifdef ALT_DIGITS
        ALT_DIGITS,
        TM_DIGITS,
#endif
};

static void
native_lc_time(Lc_info_t *li)
{
	char *s;
	char *t;
	char **b;
	int n;
	int i;

	n = 0;
	for(i = 0; i < elementsof(map); i++)
	{
		if(!(t = nl_langinfo(map[i].native)))
			t = tm_data.format[map[i].local];
		n += strlen(t) + 1;
	}
	if(!(b = newof(0, char *, TM_NFORM, n)))
		return;
	s = (char *)(b + TM_NFORM);
	for(i = 0; i < elementsof(map); i++)
	{
		b[map[i].local] = s;
		if(!(t = nl_langinfo(map[i].native)))
			t = tm_data.format[map[i].local];
		while(*s++ = *t++)
			;
	}
	fixup(li, b);
}

#else

#define native_lc_time(li) ((li->data = (tm_info.format = tm_data.format)), (tm_info.deformat = tm_info.format[TM_DEFAULT]))

#endif

/*
 * load the LC_TIME data for the current locale
 */

static void
load(Lc_info_t *li)
{
	char *s;
	char **b;
	char **v;
	char **e;
	unsigned char bom[3];
	ssize_t n;
	iconv_t cvt;
	FILE *sp;
	ast_wbuf_t tp = AST_WBUF_INIT;
	int have_tp = 0;
	char path[PATH_MAX];

	if(b = (char **)li->data)
	{
		tm_info.format = b;
		if(!(tm_info.deformat = state.format))
			tm_info.deformat = tm_info.format[TM_DEFAULT];
		return;
	}
	tm_info.format = tm_data.format;
	if(!(tm_info.deformat = state.format))
		tm_info.deformat = tm_info.format[TM_DEFAULT];
	if(mcfind(NULL, NULL, LC_TIME, 0, path, sizeof(path)) && (sp = fopen(path, "r")))
	{
		fseek(sp, 0, SEEK_END);
		n = ftell(sp);
		fseek(sp, 0, SEEK_SET);
		if(fread(bom, 1, 3, sp) == 3)
		{
			if(bom[0] == 0xef && bom[1] == 0xbb && bom[2] == 0xbf && (cvt = iconv_open("", "utf")) != (iconv_t)(-1))
			{
				if(!ast_wbuf_open(&tp))
				{
					n = iconv_move(cvt, sp, &tp, (size_t)(-1), NULL);
					have_tp = 1;
				}
				iconv_close(cvt);
			}
			if(!have_tp)
				fseek(sp, 0, SEEK_SET);
		}
		else
			fseek(sp, 0, SEEK_SET);
		if(b = newof(0, char *, TM_NFORM, n + 2))
		{
			v = b;
			e = b + TM_NFORM;
			s = (char *)e;
			if(have_tp && memcpy(s, ast_wbuf_base(&tp), n) || !have_tp && (ssize_t)fread(s, 1, n, sp) == n)
			{
				s[n] = '\n';
				while(v < e)
				{
					*v++ = s;
					if(!(s = strchr(s, '\n')))
						break;
					*s++ = 0;
				}
				fixup(li, b);
			}
			else
				free(b);
		}
		if(have_tp)
			ast_wbuf_close(&tp);
		fclose(sp);
	}
	else
		native_lc_time(li);
}

/*
 * check that tm_info.format matches the current locale
 */

char **
tmlocale(void)
{
	Lc_info_t *li;

	if(!tm_info.format)
	{
		tm_info.format = tm_data.format;
		if(!tm_info.deformat)
			tm_info.deformat = tm_info.format[TM_DEFAULT];
		else if(tm_info.deformat != tm_info.format[TM_DEFAULT])
			state.format = tm_info.deformat;
	}

	/* load the locale set in LC_TIME */
	li = LCINFO(AST_LC_TIME);
	if(!li->data || state.locale != li)
	{
		load(li);
		state.locale = li;
	}

	return tm_info.format;
}

/***********************************************************************
*                                                                      *
*               This software is part of the ast package               *
*          Copyright (c) 1982-2012 AT&T Intellectual Property          *
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
*                  David Korn <dgk@research.att.com>                   *
*                                                                      *
***********************************************************************/
#pragma prototyped

/*
 * tables for the test builin [[...]] and [...]
 */

#include	<ast.h>

#include	"defs.h"
#include	"test.h"

/*
 * This is the list of binary test and [[...]] operators
 */

const Shtable_t shtab_testops[] =
{
		"!=",		TEST_SNE,
		"-a",		TEST_AND,
		"-ef",		TEST_EF,
		"-eq",		TEST_EQ,
		"-ge",		TEST_GE,
		"-gt",		TEST_GT,
		"-le",		TEST_LE,
		"-lt",		TEST_LT,
		"-ne",		TEST_NE,
		"-nt",		TEST_NT,
		"-o",		TEST_OR,
		"-ot",		TEST_OT,
		"=",		TEST_SEQ,
		"==",		TEST_SEQ,
		"=~",           TEST_REP,
		"<",		TEST_SLT,
		">",		TEST_SGT,
		"]]",		TEST_END,
		"",		0
};

const char test_opchars[]	= "HLNRSVOGCaeohrwxdcbfugkv"
#if SHOPT_TEST_L
	"l"
#endif
				"psnzt";
const char e_argument[]		= "argument expected";
const char e_missing[]		= "%s missing";
const char e_badop[]		= "%s: unknown operator";
const char e_tstbegin[]		= "[[ ! ";
const char e_tstend[]		= " ]]\n";

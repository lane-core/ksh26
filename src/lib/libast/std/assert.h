/***********************************************************************
*                                                                      *
*              This file is part of the ksh 93u+m package              *
*             Copyright (c) 2024 Contributors to ksh 93u+m             *
*                      and is licensed under the                       *
*                 Eclipse Public License, Version 2.0                  *
*                                                                      *
*                A copy of the License is available at                 *
*      https://www.eclipse.org/org/documents/epl-2.0/EPL-2.0.html      *
*         (with md5 checksum 84283fa8859daf213bdda5a9f8d1be1d)         *
*                                                                      *
*                  Martijn Dekker <martijn@inlv.org>                   *
*                                                                      *
***********************************************************************/

/*
 * Since native OS assert.h headers often don't play well with libast,
 * here is a simple AST implementation of assert.h.
 * It may be included more than once with or without NDEBUG defined.
 */

#include <ast_common.h>

#undef assert
#ifdef NDEBUG
#define assert(e) ((void)0)
#else
#define assert(e) ((e) ? (void)0 : _ast_assertfail(#e, __func__, __FILE__, __LINE__))
#endif

#ifndef _ASSERT_H
#define _ASSERT_H
extern void _ast_assertfail(const char *, const char *, const char *, int);
#endif

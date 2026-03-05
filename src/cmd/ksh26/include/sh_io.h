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
#ifndef _sh_io_h_defined
#define _sh_io_h_defined 1

/*
 * sh_io.h — I/O type abstraction for ksh26
 *
 * Provides ksh26-specific type names for sfio structures. This layer
 * decouples the ksh source from direct sfio dependency at the type level,
 * making future I/O subsystem replacements easier.
 *
 * This is a type-only abstraction. Function names (sf*) and semantics
 * remain unchanged — a future sfio replacement will provide compatible
 * implementations of the same sf* API.
 */

#include <sfio.h>

/* Stream types — aliases for sfio structures */
typedef Sfio_t sh_stream_t;
typedef Sfdisc_t sh_disc_t;
#define sh_off_t Sfoff_t

/* Discipline callback types */
typedef Sfread_f sh_read_f;
typedef Sfwrite_f sh_write_f;
typedef Sfseek_f sh_seek_f;
typedef Sfexcept_f sh_except_f;

/* Formatted I/O types */
typedef Sffmt_t sh_fmt_t;
typedef Sffmtext_f sh_fmtext_f;
typedef Sffmtevent_f sh_fmtevent_f;

/* Stream flags — ksh26 names mapping to SFIO_ constants */
#define SH_IO_READ SFIO_READ
#define SH_IO_WRITE SFIO_WRITE
#define SH_IO_STRING SFIO_STRING
#define SH_IO_APPENDWR SFIO_APPENDWR
#define SH_IO_MALLOC SFIO_MALLOC
#define SH_IO_LINE SFIO_LINE
#define SH_IO_SHARE SFIO_SHARE
#define SH_IO_EOF SFIO_EOF
#define SH_IO_ERROR SFIO_ERROR
#define SH_IO_STATIC SFIO_STATIC
#define SH_IO_IOCHECK SFIO_IOCHECK
#define SH_IO_PUBLIC SFIO_PUBLIC
#define SH_IO_WHOLE SFIO_WHOLE
#define SH_IO_IOINTR SFIO_IOINTR
#define SH_IO_WCWIDTH SFIO_WCWIDTH

#define SH_IO_BUFSIZE SFIO_BUFSIZE

/* Exception events */
#define SH_IO_CLOSING SFIO_CLOSING
#define SH_IO_DPUSH SFIO_DPUSH
#define SH_IO_DPOP SFIO_DPOP
#define SH_IO_DBUFFER SFIO_DBUFFER
#define SH_IO_SYNC SFIO_SYNC
#define SH_IO_PURGE SFIO_PURGE
#define SH_IO_FINAL SFIO_FINAL
#define SH_IO_READY SFIO_READY
#define SH_IO_NEW SFIO_NEW
#define SH_IO_SETFD SFIO_SETFD

/* For sfreserve */
#define SH_IO_LOCKR SFIO_LOCKR
#define SH_IO_LASTR SFIO_LASTR

/* Discipline stack sentinels */
#define SH_IO_POPSTACK SFIO_POPSTACK
#define SH_IO_POPDISC SFIO_POPDISC

/* Standard streams */
#define sh_stdin sfstdin
#define sh_stdout sfstdout
#define sh_stderr sfstderr

/* String stream macros — route to sh_strbuf.h implementations */
#include "sh_strbuf.h"

#endif /* !_sh_io_h_defined */

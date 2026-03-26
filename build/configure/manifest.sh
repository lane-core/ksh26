#
# manifest.sh — probe registry for ksh26 configure
#
# Declares all probes with: name, tier, dependencies, type, library,
# and FEATURE-to-header copy mapping.
#
# The driver reads this manifest, topologically sorts by tier, and
# runs probes in parallel within tiers. After each tier, FEATURE
# headers are copied to ast_*.h and probe_defs.h is regenerated.
#
# Types:
#   complex   — shell function with multiple C programs / batch helpers
#   delegate  — runs an external .sh or .c file
#   static    — emits fixed text (no detection)
#   shell     — runs shell commands (locale, cmds, kill -l)
#   cl        — standalone C probe: compile + link
#   clr       — standalone C probe: compile + link + run
#   batch     — pure batch helper calls (hdr/lib/mem/typ/dat)
#   generator — reads sysdeps/prior results, produces derived files
#
# Depends: driver.sh (for the probe() registration function)

# ── Registration function ────────────────────────────────────────

_manifest_probes=""
_manifest_count=0

probe()
{
	# Usage: probe NAME TIER DEPS TYPE LIB FEATURE_COPIES
	# DEPS: comma-separated list of probe names, or "" for none
	# LIB: which library's FEATURE dir (libast, ksh26, libcmd, pty)
	# FEATURE_COPIES: space-separated "feature=header.h" pairs, or ""
	# Pipe-delimited storage (not tab) — tabs collapse empty fields in POSIX read.
	_manifest_probes="${_manifest_probes}
${1}|${2}|${3}|${4}|${5}|${6}"
	_manifest_count=$((_manifest_count + 1))
}

# ── Tier 0: standards (everything depends on this) ───────────────

probe ast-standards	0 "" \
	complex		libast	"standards=ast_standards.h"

# ── Tier 1: api, common, lib (independent, all need standards) ──

probe ast-api		1 "ast-standards" \
	static		libast	"api=ast_api.h"

probe ast-common	1 "ast-standards" \
	complex		libast	"common=ast_common.h"

probe ast-lib		1 "ast-standards,ast-common" \
	complex		libast	"lib=ast_lib.h"

# ── Tier 2: system capabilities ─────────────────────────────────

probe ast-eaccess	2 "ast-common,ast-lib" \
	complex		libast	"eaccess=ast_eaccess.h"

probe ast-aso		2 "ast-common" \
	complex		libast	""

probe ast-asometh	2 "ast-aso" \
	complex		libast	""

probe ast-sig		2 "ast-common,ast-lib" \
	delegate	libast	"sig=sig.h"

probe ast-fs		2 "ast-common,ast-lib" \
	complex		libast	"fs=ast_fs.h"

probe ast-sfio		2 "ast-common" \
	complex		libast	""

probe ast-sys		2 "ast-common" \
	complex		libast	"sys=ast_sys.h"

probe ast-param		2 "ast-common" \
	delegate	libast	"param=ast_param.h"

probe ast-tty		2 "ast-common,ast-lib" \
	complex		libast	"tty=ast_tty.h"

probe ast-map		2 "ast-common" \
	delegate	libast	"map=ast_map.h"

probe ast-mmap		2 "ast-sys" \
	complex		libast	""

probe ast-wchar		2 "ast-common,ast-lib" \
	complex		libast	"wchar=ast_wchar.h"

# ── Tier 3: fcntl ───────────────────────────────────────────────

probe ast-fcntl		3 "ast-param,ast-fs" \
	delegate	libast	"fcntl=ast_fcntl.h"

# ── Tier 4: conf + limits ───────────────────────────────────────

probe conf		4 "ast-param" \
	generator	libast	""

probe ast-limits	4 "ast-param,conf" \
	delegate	libast	"limits=ast_limits.h"

# ── Tier 5: subsystem features (wide parallel band) ─────────────

probe ast-tvlib		5 "ast-common,ast-sys" \
	complex		libast	""

probe ast-syscall	5 "ast-common" \
	complex		libast	""

probe ast-hack		5 "ast-common" \
	complex		libast	""

probe ast-tmlib		5 "ast-lib" \
	complex		libast	""

probe ast-float		5 "ast-common" \
	complex		libast	"float=ast_float.h"

probe ast-dirent	5 "ast-common,ast-lib" \
	complex		libast	"dirent=ast_dirent.h"

probe ast-wctype	5 "ast-wchar" \
	complex		libast	"wctype=ast_wctype.h"

probe ast-nl_types	5 "ast-limits" \
	complex		libast	"nl_types=ast_nl_types.h"

probe ast-ccode		5 "" \
	complex		libast	"ccode=ast_ccode.h"

probe ast-time		5 "ast-sys" \
	complex		libast	"time=ast_time.h"

probe ast-tv		5 "ast-fs" \
	complex		libast	"tv=tv.h"

probe ast-ndbm		5 "" \
	complex		libast	"ndbm=ast_ndbm.h"

probe ast-sizeof	5 "ast-common" \
	complex		libast	"sizeof=ast_sizeof.h"

probe ast-align		5 "ast-common" \
	delegate	libast	"align=align.h"

probe ast-random	5 "" \
	complex		libast	"random=ast_random.h"

probe ast-stdio		5 "ast-common,ast-lib" \
	complex		libast	"stdio=ast_stdio.h"

probe ast-siglist	5 "" \
	complex		libast	""

probe ast-mode		5 "" \
	delegate	libast	"mode=ast_mode.h"

# ── Tier 6: final probes ────────────────────────────────────────

probe ast-signal	6 "ast-siglist" \
	delegate	libast	""

probe ast-tmx		6 "ast-common" \
	complex		libast	"tmx=tmx.h"

probe ast-iconv		6 "" \
	complex		libast	"iconv=ast_iconv.h"

probe ast-sfinit	6 "ast-common,ast-float" \
	delegate	libast	""

probe ast-locale	6 "" \
	shell		libast	""

probe ast-libpath	6 "" \
	delegate	libast	""

# ── ksh26 probes (all tier 7 — after libast) ────────────────────

probe ksh26-cmds	7 "" \
	shell		ksh26	""

probe ksh26-posix8	7 "" \
	batch		ksh26	""

probe ksh26-time	7 "" \
	complex		ksh26	""

probe ksh26-poll	7 "" \
	complex		ksh26	""

probe ksh26-rlimits	7 "" \
	batch		ksh26	""

probe ksh26-fchdir	7 "" \
	complex		ksh26	""

probe ksh26-locale	7 "" \
	complex		ksh26	""

probe ksh26-options	7 "" \
	complex		ksh26	""	# batch (sys/acct) + clr (SHOPT_GLOBCASEDET)

probe ksh26-externs	7 "" \
	complex		ksh26	""

probe ksh26-math	7 "" \
	generator	ksh26	""

# ── libcmd probes (tier 7 — parallel with ksh26) ────────────────

probe libcmd-symlink	7 "" \
	complex		libcmd	""

probe libcmd-sockets	7 "" \
	batch		libcmd	""

probe libcmd-ids	7 "" \
	batch		libcmd	""

probe libcmd-utsname	7 "" \
	complex		libcmd	""

# ── pty probe (tier 7) ──────────────────────────────────────────

probe pty		7 "" \
	complex		pty	""

# ── Summary ─────────────────────────────────────────────────────
# 58 probes: 43 libast (tiers 0-6) + 10 ksh26 + 4 libcmd + 1 pty (tier 7)
# All monolith probes present — no eliminations until byte-identical output verified.

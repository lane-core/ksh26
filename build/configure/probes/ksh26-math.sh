# probe: ksh26-math — reads math.tab, probes math functions, generates shtab_math[]
# FEATURE: ksh26/FEATURE/math
# Type: generator (reads math.tab → C table + extern decls)
#
# This is adapted from the monolith's run_ksh26_math with minimal changes:
# - Function renamed probe_ksh26_math
# - Uses $LIBAST_INCS instead of hardcoded -I paths
# - Uses _probe_stdin_link instead of _math_probe_link (stdin heredocs)
# - Uses configure_log/putln for output
# - Removes cache check (handled by driver)
#
# The math probe is intentionally NOT refactored into a clean abstraction
# because its complexity is irreducible — it reads a data file, probes
# ~75 functions, generates C source code with type-appropriate wrappers,
# and emits a lookup table. The monolith's approach (eval'd dynamic
# variables, IFS manipulation, string-built C) is ugly but correct and
# well-tested. A cleaner rewrite is a future TODO (see ergonomics review).

# Monolith-compatible wrappers for the math probe.
# The monolith's probe functions read C from stdin (heredocs).
# Our driver's _math_probe_compile/_math_probe_link take file arguments.
# These wrappers bridge the gap.
_math_probe_compile() { _probe_stdin_compile "$@"; }
_math_probe_link() { _probe_stdin_link "$@"; }
_math_probe_lib()
{
	_probe_stdin_link "${2:-}" <<EOF
extern int ${1}();
volatile void *_p;
int main(void) { _p = (void*)${1}; return 0; }
EOF
}
_math_probe_dat()
{
	_probe_stdin_link <<EOF
#include <${2:-math.h}>
extern int ${1};
int main(void) { return (int)${1}; }
EOF
}
_math_probe_typ()
{
	_probe_stdin_compile <<EOF
static ${1} _probe_v;
int n = sizeof(_probe_v);
EOF
}

probe_ksh26_math()
{
	_saved_PROBE_STD_INC="$_PROBE_STD_INC"
	_PROBE_STD_INC=""  # monolith compat — math.sh ran without standards preamble
	_probe_out_file="${_probe_tmpdir}/math"  # monolith compat — temp file prefix
	_out="$1"
	if [ "$opt_force" = 0 ] && [ -f "$_out" ] \
	   && [ "$_out" -nt "$KSH_SRC/features/math.sh" ] \
	   && [ "$_out" -nt "$KSH_SRC/data/math.tab" ]; then
		return 0
	fi

	_math_inc="$LIBAST_INCS"
	_math_cc="$CC $CFLAGS_BASE $_math_inc"
	_math_ld="$LDFLAGS_BASE -lm"
	_math_tab="$KSH_SRC/data/math.tab"

	# ── Probe 1: typ long.double ──
	# iffe's math.sh runs with -n (nodefine), so _typ_long_double is
	# only meaningful when long double is LARGER than double. On darwin
	# ARM64, long double == double — iffe's -n flag effectively sets
	# _typ_long_double=0, suppressing l-variant preference and local wrappers.
	_typ_long_double=0
	if _math_probe_typ "long double"; then
		if _math_probe_compile <<'EOF'
int x[sizeof(long double) > sizeof(double) ? 1 : -1];
EOF
		then
			_typ_long_double=1
		fi
	fi

	# ── Probe 2: does math.h need ast_standards.h? ──
	_use_ast_standards=0
	if _math_probe_link "$_math_inc -lm" <<'EOF'
#include <ast_standards.h>
#include <math.h>
#ifndef isgreater
#define isgreater(a,b) 0
#endif
int main(void) { return isgreater(0.0,1.0); }
EOF
	then
		_use_ast_standards=1
	fi

	# ── Probe 3: does ieeefp.h work? ──
	_use_ieeefp=0
	_math_hdrs="ast_float.h"
	if _math_probe_link "$_math_inc -lm" <<'EOF'
#include <math.h>
#include <ieeefp.h>
int main(void) { return 0; }
EOF
	then
		_use_ieeefp=1
		_math_hdrs="$_math_hdrs ieeefp.h"
	fi

	# ── Read math.tab: collect function names, aliases, numeric constants ──
	_m_names=""
	_m_libs=""
	_m_nums=""
	_m_ifs="$IFS"
	while read _m_type _m_args _m_name _m_aka; do
		case $_m_type in
		[fix])
			_m_names="$_m_names $_m_name"
			_m_libs="$_m_libs,$_m_name"
			case $_typ_long_double in
			1) _m_libs="$_m_libs,${_m_name}l" ;;
			esac
			for _m_a in $_m_aka; do
				case $_m_a in
				'{'*) break ;;
				*=*)
					IFS='=|'
					set -- $_m_a
					IFS="$_m_ifs"
					case ",$_m_libs," in
					*,$1,*) ;;
					*)	_m_names="$_m_names $1"
						_m_libs="$_m_libs,$1"
						case $_typ_long_double in
						1) _m_libs="$_m_libs,${1}l" ;;
						esac ;;
					esac
					shift
					while [ $# -gt 0 ]; do
						case ",$_m_nums," in
						*,$1,*) ;;
						*) _m_nums="$_m_nums,$1" ;;
						esac
						shift
					done ;;
				esac
			done
			eval "_M_TYPE_$_m_name='$_m_type' _M_ARGS_$_m_name='$_m_args' _M_AKA_$_m_name='$_m_aka'"
			;;
		esac
	done < "$_math_tab"

	# ── Probe 4: lib check — which math functions exist as symbols? ──
	# Uses _math_probe_lib (extern int fn()) — detects real lib symbols only.
	# Correctly rejects fnl on darwin ARM64 where long double == double.
	_m_inc_flags="-I$FEATDIR/libast"
	case $_use_ast_standards in
	1) _m_inc_flags="$_m_inc_flags -include $FEATDIR/libast/ast_standards.h" ;;
	esac
	for _m_h in $_math_hdrs; do
		_m_inc_flags="$_m_inc_flags -include $FEATDIR/libast/$_m_h"
	done
	IFS=,
	for _m_fn in $_m_libs; do
		IFS="$_m_ifs"
		case $_m_fn in
		"") continue ;;
		esac
		if _math_probe_lib "$_m_fn" "-lm"; then
			eval "_lib_${_m_fn}=1"
		else
			eval "_lib_${_m_fn}="
		fi
	done
	IFS="$_m_ifs"

	# Determine which variant (name or namel) to use.
	# _typ_long_double already encodes sizeof(long double) > sizeof(double)
	_m_prefer_l=$_typ_long_double
	# When long double == double, clear the l variant results so the
	# generation loop uses the base variant (matching iffe's behavior).
	if [ "$_m_prefer_l" = 0 ]; then
		for _m_name in $_m_names; do
			eval "_lib_${_m_name}l="
		done
	fi
	_m_lib=""
	for _m_name in $_m_names; do
		eval "_m_xl=\${_lib_${_m_name}l:-} _m_x=\${_lib_${_m_name}:-}"
		case $_m_prefer_l:$_m_xl in
		1:1) _m_lib="$_m_lib,${_m_name}l" ;;
		esac
		case $_m_x in
		1) case $_m_prefer_l:$_m_xl in
		   1:1) ;;  # already added l variant
		   *) _m_lib="$_m_lib,${_m_name}" ;;
		   esac ;;
		esac
	done

	# ── Probe 4b: callable detection for macro-only functions ──
	# Functions like fpclassify, signbit, isfinite are macros with no lib
	# symbol. _math_probe_lib rejects them (correctly). This probe detects them
	# as usable callables so the generation loop can create local_ wrappers.
	for _m_name in $_m_names; do
		eval "_m_xl=\${_lib_${_m_name}l:-} _m_x=\${_lib_${_m_name}:-}"
		case $_m_xl:$_m_x in
		*1*) continue ;;  # already found as lib — no need to test callable
		esac
		# Try calling fn(0.0) or fn(0.0,0.0) with just <math.h>
		_callable_src="$_probe_tmpdir/math.callable.c"
		cat >| "$_callable_src" <<EOF
#include <math.h>
int main(void) { volatile double r = (double)${_m_name}(0.0); return (int)r; }
EOF
		if "$CC" $CFLAGS_BASE -o "$_probe_tmpdir/math.callable" "$_callable_src" $LDFLAGS_BASE -lm 2>/dev/null; then
			eval "_lib_${_m_name}=1"
			_m_lib="$_m_lib,${_m_name}"
		else
			cat >| "$_callable_src" <<EOF
#include <math.h>
int main(void) { volatile double r = (double)${_m_name}(0.0,0.0); return (int)r; }
EOF
			if "$CC" $CFLAGS_BASE -o "$_probe_tmpdir/math.callable" "$_callable_src" $LDFLAGS_BASE -lm 2>/dev/null; then
				eval "_lib_${_m_name}=1"
				_m_lib="$_m_lib,${_m_name}"
			fi
		fi
	done

	# ── Probe 5: dat/npt/mac per function ──
	IFS=,
	for _m_fn in $_m_lib; do
		IFS="$_m_ifs"
		case $_m_fn in
		"") continue ;;
		esac
		# dat: is it a data symbol?
		if _math_probe_dat "$_m_fn" "math.h"; then
			eval "_dat_${_m_fn}=1"
		else
			eval "_dat_${_m_fn}="
		fi
		# mac: is it a macro?
		if _math_probe_compile "$_m_inc_flags -lm" <<EOF
${_PROBE_STD_INC}
#include <math.h>
#ifdef $_m_fn
int main(void) { return 0; }
#else
#error not a macro
#endif
EOF
		then
			eval "_mac_${_m_fn}=1"
		else
			eval "_mac_${_m_fn}="
		fi
		# npt: C23 mandates prototypes for all standard library functions.
		# Skip the npt test — never emit extern declarations.
		eval "_npt_${_m_fn}="
	done
	IFS="$_m_ifs"

	# ── Probe 6: numeric constants ──
	IFS=,
	for _m_num in $_m_nums; do
		IFS="$_m_ifs"
		case $_m_num in
		"") continue ;;
		esac
		if _math_probe_compile "$_m_inc_flags" <<EOF
${_PROBE_STD_INC}
#include <math.h>
static double x = $_m_num;
int main(void) { return (int)x; }
EOF
		then
			eval "_num_${_m_num}=1"
		else
			eval "_num_${_m_num}="
		fi
	done
	IFS="$_m_ifs"

	# ── Generate the output header ──
	# This replicates math.sh lines 124-344
	{
		echo "/* : : generated by configure.sh from ${_math_tab#"$PACKAGEROOT/"} : : */"
		echo "#ifndef _def_math_ksh26"
		echo "#define _def_math_ksh26	1"
		echo "#define _sys_types	1	/* #include <sys/types.h> ok */"
		cat <<MATHHEADER
#if __clang__
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif

/* : : generated by configure.sh from ${_math_tab#"${PACKAGEROOT:-/dev/null}"/} : : */

typedef Sfdouble_t (*Math_f)(Sfdouble_t,...);

MATHHEADER
		case $_use_ast_standards in
		1) echo "#include <ast_standards.h>" ;;
		esac
		echo "#include <math.h>"
		case $_use_ieeefp in
		1) echo "#include <ieeefp.h>" ;;
		esac
		cat <<'MATHIA64'
#include <ast_float.h>
#if defined(__ia64__) && defined(signbit)
# if defined __GNUC__ && __GNUC__ >= 4
#  define __signbitl(f)		__builtin_signbitl(f)
# else
#  if _lib_copysignl
#   define __signbitl(f)	(int)(copysignl(1.0,(f))<0.0)
#  endif
# endif
#endif
MATHIA64
		echo

		# Generate intercept functions and table entries
		_m_nl='
'
		_m_ht='	'
		_m_tab=""
		for _m_name in $_m_names; do
			eval "_m_xl=\${_lib_${_m_name}l:-} _m_x=\${_lib_${_m_name}:-}"
			eval "_m_r=\${_M_TYPE_${_m_name}:-f} _m_a=\${_M_ARGS_${_m_name}:-1} _m_aka=\${_M_AKA_${_m_name}:-}"
			case $_m_r in
			i) _m_L=int _m_R=1 ;;
			x) _m_L=Sfdouble_t _m_R=4 ;;
			*) _m_L=Sfdouble_t _m_R=0 ;;
			esac
			# some identifiers can't be functions in C but can in ksh
			case $_m_name in
			float|int) _m_xl=0; _m_x=1 ;;
			esac
			_m_F="local_$_m_name"
			case $_m_xl:$_m_x in
			1:*)
				_m_f="${_m_name}l"
				_m_t=Sfdouble_t
				_m_local=""
				;;
			*:1)
				_m_f="$_m_name"
				_m_t=double
				case $_m_name in
				float|int) _m_local=1 ;;
				*) _m_local=$_typ_long_double ;;
				esac
				;;
			*)
				# Neither namel nor name found — check aliases
				_m_body=""
				for _m_k in $_m_aka; do
					case $_m_body in
					?*) _m_body="$_m_body $_m_k"; continue ;;
					esac
					case $_m_k in
					'{'*) _m_body=$_m_k ;;
					*=*)
						IFS='=|'
						set -- $_m_k
						IFS="$_m_ifs"
						_m_f=$1; shift; _m_v="$*"
						eval "_m_axl=\${_lib_${_m_f}l:-} _m_ax=\${_lib_${_m_f}:-}"
						case $_m_axl:$_m_ax in
						1:*) _m_f="${_m_f}l" ;;
						*:1) ;;
						*) continue ;;
						esac
						_m_y=""
						while [ $# -gt 0 ]; do
							eval "_m_nx=\${_num_$1:-}"
							case $_m_nx in
							1) case $_m_y in ?*) _m_y="$_m_y || " ;; esac
							   _m_y="${_m_y}q == $1" ;;
							esac
							shift
						done
						case $_m_y in
						"") ;;
						*) _m_r=int _m_R=1
						   echo "static $_m_r $_m_F(Sfdouble_t a1) { $_m_r q = $_m_f(a1); return $_m_y; }"
						   _m_tab="$_m_tab$_m_nl$_m_ht\"\\0${_m_R}${_m_a}${_m_name}\",$_m_ht(Math_f)${_m_F},"
						   break ;;
						esac ;;
					esac
				done
				case $_m_body in
				?*)
					# Has a body — try to link it
					_m_code="static $_m_L $_m_F("
					_m_sep="" _m_ta="" _m_tc="" _m_td=""
					_m_p=1
					while [ "$_m_p" -le 9 ]; do
						case $_m_R:$_m_p in
						4:2) _m_T=int ;;
						*) _m_T=Sfdouble_t ;;
						esac
						_m_code="$_m_code${_m_sep}$_m_T a$_m_p"
						_m_ta="$_m_ta${_m_sep}a$_m_p"
						_m_tc="$_m_tc${_m_sep}0"
						_m_td="$_m_td$_m_T a$_m_p;"
						case $_m_a in
						$_m_p) break ;;
						esac
						_m_sep=","
						_m_p=$((_m_p + 1))
					done
					if _math_probe_link "$_m_inc_flags -lm" <<EOF
static $_m_L $_m_F($_m_ta)$_m_td${_m_body}int main(void){return $_m_F($_m_tc)!=0;}
EOF
					then
						_m_code="$_m_code)$_m_body"
						echo "$_m_code"
						_m_tab="$_m_tab$_m_nl$_m_ht\"\\0${_m_R}${_m_a}${_m_name}\",$_m_ht(Math_f)${_m_F},"
					fi ;;
				esac
				continue
				;;
			esac
			case $_m_r in
			i) _m_r=int ;;
			*) _m_r=$_m_t ;;
			esac
			eval "_m_n=\${_npt_$_m_f:-} _m_m=\${_mac_$_m_f:-} _m_d=\${_dat_$_m_f:-}"
			case $_m_d:$_m_m:$_m_n in
			1:*:*|*:1:*) ;;
			*:*:1)
				_m_code="extern $_m_r $_m_f("
				_m_sep=""
				_m_p=1
				while [ "$_m_p" -le 7 ]; do
					case $_m_p:$_m_f in
					2:ldexp*) _m_code="$_m_code${_m_sep}int" ;;
					*) _m_code="$_m_code${_m_sep}$_m_t" ;;
					esac
					case $_m_a in
					$_m_p) break ;;
					esac
					_m_sep=","
					_m_p=$((_m_p + 1))
				done
				_m_code="$_m_code);"
				echo "$_m_code" ;;
			esac
			case $_m_local:$_m_m:$_m_n:$_m_d in
			1:*:*:*|*:1:*:*|*:*:1:)
				_m_args="" _m_code="static $_m_L local_$_m_f("
				_m_sep=""
				_m_p=1
				while [ "$_m_p" -le 9 ]; do
					_m_args="$_m_args${_m_sep}a$_m_p"
					case $_m_R:$_m_p in
					4:2) _m_T=int ;;
					*) _m_T=Sfdouble_t ;;
					esac
					_m_code="$_m_code${_m_sep}$_m_T a$_m_p"
					case $_m_a in
					$_m_p) break ;;
					esac
					_m_sep=","
					_m_p=$((_m_p + 1))
				done
				_m_code="$_m_code)"
				case $_m_f in
				float)	_m_code="$_m_code{return $_m_args;}" ;;
				int)	_m_code="$_m_code{return ($_m_args < LDBL_LLONG_MIN || $_m_args > LDBL_ULLONG_MAX) ? (Sfdouble_t)0 : ($_m_args < 0) ? (Sfdouble_t)((Sflong_t)$_m_args) : (Sfdouble_t)((Sfulong_t)$_m_args);}" ;;
				*)	_m_code="$_m_code{return $_m_f($_m_args);}" ;;
				esac
				echo "$_m_code"
				_m_f="local_$_m_f"
				;;
			esac
			for _m_x in $_m_name $_m_aka; do
				case $_m_x in
				'{'*) break ;;
				*=*) continue ;;
				esac
				_m_tab="$_m_tab$_m_nl$_m_ht\"\\0${_m_R}${_m_a}${_m_x}\",$_m_ht(Math_f)$_m_f,"
			done
		done
		_m_tab="$_m_tab$_m_nl$_m_ht\"\",$_m_ht${_m_ht}NULL"

		cat <<MATHTAIL

/*
 * first byte is two-digit octal number.  Last digit is number of args
 * first digit is 0 if return value is double, 1 for integer
 */
const struct mathtab shtab_math[] =
{$_m_tab
};
MATHTAIL
		echo "#endif"
	} | atomic_write "$_out" || true
	_PROBE_STD_INC="$_saved_PROBE_STD_INC"
}

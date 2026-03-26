#
# gen-features.sh — generate FEATURE headers from sysdeps + probe output
#
# Skalibs model: probes write detection results to sysdeps (flat text).
# This generator reads sysdeps and probe output files to produce the
# FEATURE headers that the C source expects.
#
# Two responsibilities:
# 1. Copy FEATURE files to ast_*.h headers (the FEATURE→header mapping
#    declared in manifest.sh)
# 2. Install std/ wrapper headers after all probes complete
#
# Depends: driver.sh (atomic_write, FEATDIR, etc.)
#          manifest.sh (probe registrations with copy mappings)

# ── Copy FEATURE → ast_*.h headers ──────────────────────────────

copy_features()
{
	# Read the manifest and copy each probe's FEATURE output to its
	# header destination. Called after each tier completes.
	LOCAL _line _name _tier _deps _type _lib _copies _pair _feat _hdr _src _dst; BEGIN
		putln "$_manifest_probes" | while IFS='|' read -r _name _tier _deps _type _lib _copies; do
			# Skip empty lines
			case $_name in ''|'#'*) continue ;; esac

			# Skip probes with no copy mapping
			case $_copies in ''|'""') continue ;; esac

			# Process each feature=header.h pair
			for _pair in $_copies; do
				_feat=${_pair%%=*}
				_hdr=${_pair#*=}
				_src="$FEATDIR/${_lib}/FEATURE/${_feat}"
				_dst="$FEATDIR/${_lib}/${_hdr}"
				# Only copy if the FEATURE source exists. Don't create
			# empty headers for probes that haven't run yet —
			# empty headers cause false-positive include tests
			# (e.g., AST's fnmatch.h includes <ast_common.h>).
			if test -f "$_src"; then
				cp -f "$_src" "$_dst"
			fi
			done
		done
	END
}

# Special case: ast_common.h needs _def_map_ast stripped to avoid
# circular include (inherited from iffe convention).
fixup_ast_common()
{
	LOCAL _common; BEGIN
		_common="$FEATDIR/libast/ast_common.h"
		if test -f "$_common"; then
			sed '/define _def_map_ast/d' < "$_common" >|"${_common}.tmp"
			mv -f "${_common}.tmp" "$_common"
		fi
	END
}

# ── Install std/ wrapper headers ─────────────────────────────────
# These intercept <stdio.h>, <assert.h>, <wctype.h> and redirect
# through AST's wrappers. Installed AFTER probes complete so iffe-era
# probes (if any remain) don't pick them up via -I.

install_std_wrappers()
{
	LOCAL _std_dir; BEGIN
		_std_dir="$FEATDIR/libast/std"
		mkdir -p "$_std_dir"
		cp -f "$LIBAST_SRC/std/stdio.h" "$_std_dir/stdio.h"
		cp -f "$LIBAST_SRC/std/assert.h" "$_std_dir/assert.h"
		cp -f "$LIBAST_SRC/std/wctype.h" "$_std_dir/wctype.h"
	END
}

# ── Endian stubs ─────────────────────────────────────────────────
# Depend on ast_common.h + ast_map.h existing.

install_endian_stubs()
{
	touch "$FEATDIR/libast/std/bytesex.h" "$FEATDIR/libast/std/endian.h"
}

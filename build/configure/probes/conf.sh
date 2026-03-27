# probe: conf — generator that runs conf.sh + lcgen
# Tier 4 (generator). Creates $BUILDDIR/libast_conf/, runs conf.sh
# to produce conflim.h, conftab.h, conftab.c. Also runs lcgen to
# produce lc.h and lctab.c.
#
# Lifted from monolith run_libast_conf with API translations:
# - output path from $1 (unused — conf writes to FEATDIR directly)

probe_conf()
{
	# $1 is the output path from the driver, but conf doesn't write
	# a single FEATURE file — it installs headers into FEATDIR/libast/.
	# We use $1 as a sentinel to track cache validity.
	_out="$1"

	_conf_dir="$BUILDDIR/libast_conf"
	_inc="$FEATDIR/libast"
	_conftab="$LIBAST_SRC/comp/conf.tab"

	# Cache: skip if outputs exist, are newer than inputs, AND are installed
	if [ "$opt_force" = 0 ] && [ -f "$_conf_dir/conftab.h" ] \
	   && [ "$_conf_dir/conftab.h" -nt "$_conftab" ] \
	   && [ "$_conf_dir/conftab.h" -nt "$LIBAST_SRC/comp/conf.sh" ] \
	   && [ -f "$_inc/conflim.h" ]; then
		return 0
	fi

	mkdir -p "$_conf_dir"

	# conf.sh runs from cwd, needs FEATURE/{standards,common,param}
	[ -L "$_conf_dir/FEATURE" ] || ln -sf "$_inc/FEATURE" "$_conf_dir/FEATURE"

	# Create conf runner: prepend HOSTTYPE, then conf.sh body
	printf '%s\n' "HOSTTYPE='$HOSTTYPE'" >| "$_conf_dir/conf"
	cat "$LIBAST_SRC/comp/conf.sh" >> "$_conf_dir/conf"
	chmod +x "$_conf_dir/conf"

	# Run conf.sh: args are conf.tab then CC + flags.
	# conf.sh searches $DEFPATH then $PATH for external getconf(1).
	# Append standard system paths so getconf(1) is found even when
	# PATH contains only nix store paths (as in nix build sandboxes).
	_sys_path=$(command -p getconf PATH 2>/dev/null) || _sys_path="/usr/bin:/bin"
	(
		cd "$_conf_dir"
		PATH="$PATH:$_sys_path"
		"$SHELL" ./conf -v "$_conftab" \
			"$CC" $CFLAGS_BASE -fno-strict-aliasing
	) >>"$LOGDIR/conf.log" 2>&1 || true

	# Copy generated headers to the include area
	for _f in conflim.h conftab.h conftab.c; do
		[ -f "$_conf_dir/$_f" ] && cp -f "$_conf_dir/$_f" "$_inc/$_f"
	done

	# Generate lc.h and lctab.c via lcgen
	if [ -f "$LIBAST_SRC/port/lcgen.c" ]; then
		"$CC" $CFLAGS_BASE -o "$_conf_dir/lcgen" \
			"$LIBAST_SRC/port/lcgen.c" 2>/dev/null || true
		if [ -x "$_conf_dir/lcgen" ]; then
			"$_conf_dir/lcgen" "$_inc/lc.h" "$_inc/lctab.c" \
				< "$LIBAST_SRC/port/lc.tab" 2>/dev/null || true
		fi
	fi

	# Write sentinel so the driver can track this probe ran
	echo "/* conf probe completed */" | atomic_write "$_out" || true
}

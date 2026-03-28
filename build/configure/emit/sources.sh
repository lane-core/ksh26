# emit/sources.sh — collect source file lists for ninja generation
# Depends: core.sh (SRC, LIBAST_SRC, LIBCMD_SRC, KSH_SRC, FEATDIR)

collect_libast_sources()
{
	find "$LIBAST_SRC" -name '*.c' -not -path '*/features/*' \
		-not -path '*/man/*' \
		-not -name 'sfdcfilter.c' \
		-not -name 'omitted.c' | sort
	putln "$FEATDIR/libast/conftab.c"
	putln "$FEATDIR/libast/lctab.c"
}

collect_libcmd_sources()
{
	for _f in basename cat cmdinit cp cut dirname getconf lib ln mktemp mv stty; do
		putln "$LIBCMD_SRC/$_f.c"
	done
}

collect_ksh26_sources()
{
	for _d in sh bltins data edit; do
		find "$KSH_SRC/$_d" -name '*.c' | sort
	done
}

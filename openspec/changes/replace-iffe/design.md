## Context

configure.sh orchestrates 57 iffe invocations across 6 tiers. Each invocation
forks a shell, runs iffe.sh (4,322 lines), which creates temp files, compiles
test programs, and emits `FEATURE/` headers. configure.sh then copies these
to their final locations.

The existing `probe_c` and `probe_c_output` functions already handle the hard
work (compile+link tests, compile+run with stdout capture). What iffe adds:
- Primitive dispatch (`hdr`, `lib`, `mem`, `typ`, `tst`, `cat{}`, `output{}`)
- Guard generation (`#ifndef _def_NAME_LIB`)
- Header cascade (`if/elif` chains)
- Temp file management

All of this is replaceable with ~6 shell helper functions and direct translation
of each probe's logic.

## Goals / Non-Goals

**Goals:**
- Every generated header is byte-identical between iffe and native (verified
  by diff on both darwin and linux).
- configure.sh is the single source of truth for all feature detection.
- Probes run faster (no fork per probe, no temp file overhead).
- Cross-platform bugs are diagnosable with `sh -x configure.sh`.

**Non-Goals:**
- Changing what's probed. Same features, same defines, same headers.
- Removing probes that the sfio rewrite will eliminate (sfio, stdio, sfinit,
  mmap). Replace them now, delete them later.
- Rewriting the tier/parallel execution model. Keep `&` + `wait`.

## Decisions

### 1. Probe helper functions

Six helpers, all using the existing `$CC $CFLAGS_BASE` and `$_probe_out`
temp file pattern from `probe_c`:

| Helper | What it does | iffe equivalent |
|--------|-------------|-----------------|
| `probe_hdr HDR` | `$CC -include HDR -c` | `hdr` |
| `probe_sys HDR` | `$CC -include sys/HDR -c` | `sys` |
| `probe_lib FN [LIBS]` | link test for function | `lib` |
| `probe_mem STRUCT.FIELD HDR` | `sizeof(s.field)` compile test | `mem` |
| `probe_typ TYPE HDR` | `sizeof(TYPE)` compile test | `typ` |
| `probe_dat SYM [HDR]` | link test for data symbol | `dat` |

`probe_c` (compile+link) and `probe_c_output` (compile+run+capture) already
exist and handle `tst compile{}`, `tst link{}`, `tst execute{}`, `output{}`.

`cat{}` blocks are just inline `cat <<'EOF'` in the probe function — no helper
needed.

### 2. Per-probe function pattern

Each iffe probe becomes a function:

```sh
probe_ast_tv()
{
    _out="$FEATDIR/libast/FEATURE/tv"
    {
        echo '#ifndef _TV_H'
        echo '#define _TV_H 1'
        # ... header preamble
        if probe_mem stat.st_mtim.tv_nsec sys/stat.h; then
            echo '#define ST_MTIME_NSEC_GET(st) ((st)->st_mtim.tv_nsec)'
        elif probe_mem stat.st_mtimespec.tv_nsec sys/stat.h; then
            echo '#define ST_MTIME_NSEC_GET(st) ((st)->st_mtimespec.tv_nsec)'
        # ...
        fi
        echo '#endif'
    } | atomic_write "$_out"
}
```

### 3. Translation order

Translate probes tier-by-tier, bottom-up:
1. **Tier 0**: `standards` (1 probe, moderate)
2. **Tier 1**: `api`, `common`, `lib` (3 probes)
3. **Tier 2**: 12 probes (fs, sys, sig, etc.)
4. **Tier 3-4**: `fcntl`, conf+limits (2 probes)
5. **Tier 5**: 17 probes (the big parallel band)
6. **Tier 6**: 6 probes (signal, tmx, iconv, etc.)
7. **ksh26**: 10 probes + 7 supplemental
8. **libcmd**: 4 probes
9. **pty**: 1 probe

After each tier, run `just build` + `just test` to catch regressions.

### 4. Verification

For each probe, compare old and new output:
```sh
# Generate with iffe (old)
run_iffe_ast "tv" "tv"
cp FEATURE/tv /tmp/tv.iffe

# Generate with native (new)
probe_ast_tv
cp FEATURE/tv /tmp/tv.native

diff /tmp/tv.iffe /tmp/tv.native
```

Minor whitespace/comment differences are acceptable. Define values must match.

### 5. What happens to iffe.sh

- Remove from build path (no more `IFFE=` variable, no `run_iffe*` functions).
- Keep at `tests/infra/iffe.sh` — the iffe regression tests (`just test-iffe`)
  continue to work as a smoke test for the old tool.
- `src/cmd/INIT/iffe.sh` stays in the tree but is no longer referenced by
  configure.sh.

## Risks / Trade-offs

**[Edge cases in iffe we don't know about]** → Mitigated by byte-comparison
of all generated headers on both platforms. If iffe was doing something
subtle, the diff catches it.

**[configure.sh gets longer]** → Yes, ~400-600 lines of probe functions.
But it replaces ~200 lines of iffe invocation machinery plus the entire
4,322-line iffe.sh dependency. Net complexity decreases.

**[Parallel probe races]** → Same model as today (`&` + `wait`). Each probe
writes to its own FEATURE/ file. No shared state.

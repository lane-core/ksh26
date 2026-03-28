## 1. Layer 1: Reduction

- [x] 1.1 Delete dead libast subsystems: stdio/ (75 files), hash/ (15 files), dir/ (6 files). Relocate strkey/strsum to string/. Update configure.sh.
- [x] 1.2 Delete dead libraries: libdll/ (12 files), libsum/ (11 files). Remove from configure.sh feature tests, source collection, link line. Remove dlldefs.h include from cdtlib.h.
- [x] 1.3 Thin libcmd: reduce compiled sources from 47 to 12 (build system change only).
- [x] 1.4 Thin libast/comp: delete 21 of 38 compat shims (link-time audit to identify which).
- [x] 1.5 Platform removal Phase 1: strip dead iffe probes (Windows, QNX, Cygwin, obsolete ASO, HP-UX, NeXT).
- [x] 1.6 Platform removal Phase 2: remove platform-specific source code. Remaining NeXTBSD refs in features/standards are Darwin detection (kept).
- [x] 1.7 Security audit: remove signal handler malloc (fault.c), add integer overflow guard (streval.c). Document in notes/security/.
- [x] 1.8 Verify: `just build && just test` passes. 366 objects, 109/110 gate (pre-existing pipefail flake).

## 2. Layer 2: Type Foundation

- [x] 2.1 Set -std=c23 in configure.sh. Gate on GCC 14+ / Clang 18+.
- [x] 2.2 Convert typed enums (enum : type): nv_subop, sh_jmpmode, sh_polartype. sfio flag namespaces deferred to sfio-rewrite.
- [x] 2.3 Convert constexpr: NV_* flags in nval.h, buffer size constants.
- [x] 2.4 Add static_assert: Namval size (nval.h), SH_DEBUGTRAP (fault.h), Shopt_t size (shell.h).
- [x] 2.5 Convert [[maybe_unused]] (198 occurrences), nullptr (2339 occurrences) throughout.
- [x] 2.6 Add POSIX Issue 8 probes: pipe2, posix_close (already in features/lib), dup3, ppoll, mkostemp (added), O_CLOFORK (added to features/fcntl.c).
- [x] 2.7 Verify: `just build && just test` passes. 366 objects, 109/110 gate.

## 3. Layer 3: Polarity Infrastructure (Interpreter Side of Pairs 0-6)

Each task here is the interpreter side of a correspondence pair. The
sfio side lives in `sfio-rewrite` (see its task groups 0-7). Build
order: interpreter side first (works with legacy sfio), then sfio side.
See notes/IMPLEMENTATION.md §Layers 3+4 for the full pair rationale.

- [x] 3.1 Pair 0 (Vocabulary): sh_node_polarity[] constexpr table (shnodes.h), error convention annotations (⊕/⅋ in fault.h, fault.c, xec.c, cflow.c). _(sfio side: sfio-rewrite group 0 — sfio.h, sfhdr.h)_
- [x] 3.2 Pair 1 (Mode Transitions): Polarity frame API (struct sh_polarity, enter/leave). sh_debug (lite), sh_fun (lite), sh_trap (full, unconditional). _(sfio side: sfio-rewrite group 1 — sfmode.c)_
- [x] 3.3 Pair 2 (Context Management): sh_scope_set (defs.h), 27-site continuation classification (REDESIGN.md), argnod_guard (shell.h + name.c + fault.c). _(sfio side: sfio-rewrite group 2 — sflife.c)_
- [x] 3.4 Pair 3 (Interception): sh_getenv/putenv/sh_setenviron converted (name.c), frame_depth (shell.h + xec.c). _(sfio side: sfio-rewrite group 3 — sfdisc.c)_
- [x] 3.5 Pair 4 (Positive): Prefix guard API (sh_prefix_enter/leave), 4 of 5 sites converted. Site 3 (nv_open) unconverted — see AGENT.md hazard 3. _(sfio side: sfio-rewrite group 4 — sfwrite.c)_
- [x] 3.6 Pair 5 (Negative): macro.c degree 2→3 promotion (subcopy, copyto S_BRACT). dotdot preserved. _(sfio side: sfio-rewrite group 5 — sfread.c)_
- [x] 3.7 Pair 6 (Optimizations): Empty DEBUG trap early exit, sh_polarity_lite, scope pool (SCOPE_POOL_MAX=8). _(sfio side: sfio-rewrite group 6 — sfvprintf.c)_
- [x] 3.8 Verify: `just build && just test` passes. 366 objects, 110/110 gate.

## 4. Layer 4: sfio Rewrite

- [ ] 4.1 See `sfio-rewrite` change for detailed tasks (Pairs 0-7 sfio side + integration swap).

## 5. Completion

- [ ] 5.1 Update REDESIGN.md to reflect clean-base state.
- [ ] 5.2 Verify main branch is in correct state for release.
- [ ] 5.3 Verify: `just check-all` passes (all nix checks).

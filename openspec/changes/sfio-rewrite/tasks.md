## Correspondence pairs

Each sfio task group has a matched interpreter-side counterpart in
`fresh-rewrite` Layer 3. notes/IMPLEMENTATION.md organizes these as
paired manifestations of the same polarity theory. Build order:
interpreter side first (works with legacy sfio), then sfio side.

| sfio group | Interpreter counterpart (fresh-rewrite task) |
|------------|--------------------------------------------------|
| 0. Headers | 3.1 — sh_exec classification, error conventions |
| 1. Shift Mediator | 3.2 — polarity frame API, convert sh_debug/sh_fun/sh_trap |
| 2. Lifecycle | 3.3 — scope unification, continuation classification, longjmp safety |
| 3. Interception | 3.4 — convert sh_getenv/putenv/sh_setenviron (name.c), add depth tracking (frame_depth) |
| 4. Write Ops | 3.5 — prefix guard API, convert 5 sites |
| 5. Read Ops | 3.6 — macro.c degree 2→3 promotion |
| 6. Format Engine | 3.7 — empty DEBUG early exit, lite frame, scope pool |
| 7. Encoding | (no interpreter counterpart) |


## 0. Headers (Pair 0 — Vocabulary)

- [x] 0.1 Write sfio.h: Sfio_t struct, C23 typed enums for 3 flag namespaces, static_assert for buffer field offsets, static inline fast-path functions, [[nodiscard]] annotations. _(commit 08e473b5, staging: src/lib/libsfio/sfio.h)_
- [x] 0.2 Write sfhdr.h: internal macros, _Sfextern global state struct, format engine types. _(commit 08e473b5, staging: src/lib/libsfio/sfhdr.h)_
- [x] 0.3 Verify headers compile independently against C23.

## 1. Shift Mediator (Pair 1 — Mode Transitions)

- [x] 1.1 Write sfmode.c: _sfmode() state machine, sfsetbuf, sfclrlock, _sfsetpool, _sfcleanup. _(commit 7076619b, staging: src/lib/libsfio/sfmode.c, 662 lines)_
- [x] 1.2 Verify sfmode.c compiles against new headers.

## 2. Lifecycle (Pair 2 — Context Management)

- [x] 2.1 Write sflife.c: sfnew, sfopen, sfclose, sfstack, sfswap, sfsetfd, sfsetfd_cloexec, sfset, sfseek, sftell, sfsize, sfsync, sfpurge, sftmp, sfpool, sfnotify. _(commit 890b803d, staging: src/lib/libsfio/sflife.c, 1055 lines)_
- [x] 2.2 Integrate POSIX Issue 8: posix_close in sfclose, mkostemp in sftmp, dup3 in sfsetfd.
- [x] 2.3 Verify sfnotify fires at correct lifecycle points (contract B11).
- [x] 2.4 Unit test: sfnew/sfclose/sfstack lifecycle sequences.

## 3. Interception (Pair 3)

- [x] 3.1 Write sfdisc.c: sfdisc push/pop, _sfexcept, sfraise, Dccache_t replay. _(commit 9665c972, staging: src/lib/libsfio/sfdisc.c, 316 lines)_
- [x] 3.2 Test Dccache: discipline push with buffered data replays correctly.
- [x] 3.3 Test with ksh discipline configs: outexcept, slowread, piperead.

## 4. Write Operations (Pair 4 — Positive)

- [x] 4.1 Write sfwrite.c: sfwr, _sfflsbuf, sfwrite, sfputr, sfnputc. _(commit 09104873, staging: src/lib/libsfio/sfwrite.c, 422 lines)_
- [x] 4.2 Verify NUL sentinel contract: sfwrite does NOT NUL-terminate (B4).
- [x] 4.3 Verify line buffering trick: SF_LINE sets _endw = _data (B10).
- [x] 4.4 Verify LOCKR release: sfwrite(f, buf, 0) releases peek lock.
- [x] 4.5 Test write operations on both fd-backed and string streams.

## 5. Read Operations (Pair 5 — Negative)

- [x] 5.1 Write sfread.c: sfrd, _sffilbuf, sfread, sfreserve, sfgetr, sfungetc, sfpkrd, sfmove, _sfrsrv. _(commit 256f3b30, staging: src/lib/libsfio/sfread.c, 683 lines)_
- [x] 5.2 Unit test all 5 sfreserve calling patterns independently. _(tests/infra/sfio/sfio_test.c)_
- [x] 5.3 Verify rsrv sharing between sfgetr and sfreserve (B5).
- [x] 5.4 Verify GETR destructive NUL and _sfmode restore (B7).
- [x] 5.5 Verify sfungetc sfstack fallback (B8).
- [x] 5.6 Test sfpkrd timed reads with ppoll (Issue 8).

## 6. Format Engine (Pair 6)

- [x] 6.1 Write sfvprintf.c: sfvprintf, sfprintf, sfprints, %! protocol, FMTSET/FMTGET, shadow pointer optimization. _(commit 73a19486, staging: src/lib/libsfio/sfvprintf.c, 756 lines)_
- [x] 6.2 Verify %! extf protocol works with ksh's extend() callback.
- [x] 6.3 Verify standard specifiers delegate to libc vsnprintf.
- [x] 6.4 Run all 48+ printf-exercising tests.

## 7. Encoding (Pair 7 — Self-contained)

- [x] 7.1 Write sfvle.c: sfputl/sfgetl, sfputu/sfgetu, sfputd/sfgetd, sfputm/sfgetm. _(commit 8b8ceecb, staging: src/lib/libsfio/sfvle.c, 304 lines)_
- [x] 7.2 Verify encoding round-trips for edge cases. _(tests/infra/sfio/sfio_test.c, 6 review fix commits)_

## 8. Integration (Incremental Replacement)

The big-bang swap approach (delete legacy, move staging) failed with heap
corruption during sh_init. The incremental approach avoids this entirely:
legacy sfio is already being consolidated into the same file layout as
the rewrite (commit aa3c9798: 80→42 files). After E2+E3 consolidation
(42→~35 files), each legacy consolidated file can be incrementally
replaced by its staging counterpart with build+test gates at every step.

- [x] 8.1 Complete legacy consolidation E2: write path → sfwrite.c (~5 files → 1). _(commit 398f22e9)_
- [x] 8.2 Complete legacy consolidation E3: seek/sync path → sfseek.c (~6 files → 1). _(commit ef38bc61)_
- [ ] 8.3 Incremental replacement: swap each legacy file with its staging counterpart, one at a time. Gate each with `just build && just test`. **sfvle.c swapped** (commit fc617a34, 110/110). Remaining 6 files (sfmode.c, sflife.c, sfdisc.c, sfwrite.c, sfread.c, sfvprintf.c) have global state and internal coupling — need coordinated swap plan.
- [ ] 8.4 Remove legacy-only files (sfextern.c, sftable.c, sfsetbuf.c, sfexcept.c, sfpool.c, sfstack.c, sfswap.c, sfset.c, sfmove.c, sfwalk.c, sfpoll.c, sfcvt.c, sfprintf.c, sfprints.c, sfstrtof.h, sfhdr.h). Their functionality is absorbed into the consolidated files.
- [ ] 8.5 Eliminate ast_stdio.h interception header.
- [ ] 8.6 `just build && just test` — ≥114 stamps, ≥110 gate pass
- [ ] 8.7 `just build-asan && just test-asan` — clean
- [ ] 8.8 Verify total I/O code ≤ 3,500 lines
- [ ] 8.9 Verify zero ksh call site changes (git diff against pre-swap state)

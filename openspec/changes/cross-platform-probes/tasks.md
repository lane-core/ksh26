## 1. Fix probe compilation environment

- [x] 1.1 Set `INSTALLROOT="$PWD"` in `run_iffe_ast` before the iffe invocation
- [x] 1.2 Set `INSTALLROOT="$PWD"` in `run_iffe` (ksh26 probes need it too)
- [x] 1.3 Verify `ast_standards.h` (FEATURE/standards) exists by the time tier 1+ probes run

## 2. Fix stdio/wchar.h conflict on Linux

- [x] 2.1 Remove `____FILE_defined` guard preemption from `features/stdio` — let glibc define its internal `__FILE` type
- [x] 2.2 Remove `____FILE_defined` guard from `ast_std.h`

## 3. Validation

- [x] 3.1 `just build` — darwin build still works (no regression)
- [x] 3.2 `just test` — darwin tests still pass (110/110)
- [x] 3.3 `just build-linux` — aarch64-linux build succeeds (356/356)
- [ ] 3.4 `just test-linux` — BLOCKED: run-test.sh PATH issue (tracked in TODO.md)

## 4. Documentation

- [x] 4.1 Update `openspec/specs/build-system/spec.md` with the INSTALLROOT requirement

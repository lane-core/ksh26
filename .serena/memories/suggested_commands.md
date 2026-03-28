# Commands for Development

## Build & Test (unified porcelain)
```sh
just test                      # auto-detect platform, full nix test suite
just test linux                # test on linux (cross from darwin via builder)
just test --asan               # sanitizer variant
just test --one basic          # single test, local samu (iteration path)
just test --debug basic        # run under lldb/gdb
just test --repeat basic       # flakiness detection (10 runs)
just test --verbose            # show build artifacts after test

just build                     # auto-detect platform, nix
just build linux               # cross-build for linux
just build --asan              # sanitizer variant
just build --debug             # debug flags

just check-all                 # nix flake check (all platforms + formatting)
```

## Local Iteration (devshell only)
```sh
just configure                 # run configure.sh
just reconfigure               # force full reconfigure
just samu <args>               # raw samu passthrough
just compile-commands           # generate compile_commands.json for LSP
```

## Diagnostics
```sh
just errors                    # show build errors from log
just warnings                  # show build warnings
just failures                  # show failed tests with logs
just log [build|test] [name]   # show logs
just diagnose NAME             # comprehensive test failure diagnosis
```

## Formatting
```sh
just fmt                       # format changed C files
just fmt-check                 # check formatting (no modify)
```

## Maintenance
```sh
just clean [stage]             # clean: test|obj|lib|bin|log|all
just cleanall                  # remove all build artifacts
just install [prefix]          # install from nix build output
```

## CRITICAL Rules
- `just test` is the ONLY validation command. Never ./configure.sh or samu standalone.
- ALWAYS tee output: `just test 2>&1 | tee /tmp/ksh-test.log`
- NEVER grep/tail build output — read the log file afterward.
- NEVER re-run without a source change.
- BOTH `just test` AND `just test linux` before every commit.

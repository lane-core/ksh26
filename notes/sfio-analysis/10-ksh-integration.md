# 10: ksh Integration

How ksh93u+m / ksh26 uses SFIO. Three parallel arrays track per-fd state,
sfswap enables redirections, sftmp powers here-docs and comsub capture, and
sftrack keeps everything in sync.

## The three parallel arrays

`Legacy: shell.h:414-415, io.c:425-436`

Allocated as a single contiguous block, grown atomically by `sh_iovalidfd()`:

```
[sftable[0..n-1] | fdptrs[0..n-1] | fdstatus[0..n-1]]
```

| Array | Type | Purpose |
|-------|------|---------|
| `sh.sftable[fd]` | `Sfio_t**` | fd → Sfio_t* mapping (NULL if no stream) |
| `sh.fdstatus[fd]` | `unsigned char*` | Per-fd flags (IOREAD, IOWRITE, etc.) |
| `sh.fdptrs[fd]` | `int**` | Pointer into filemap (for save/restore tracking) |

### fdstatus flags

`Legacy: io.h:39-46`

| Flag | Value | Meaning |
|------|-------|---------|
| `IOREAD` | 001 | Readable |
| `IOWRITE` | 002 | Writable |
| `IODUP` | 004 | Duplicated for read |
| `IOSEEK` | 010 | Seekable (regular file) |
| `IONOSEEK` | 020 | Non-seekable (pipe/socket/tty) |
| `IOTTY` | 040 | Terminal |
| `IOCLEX` | 0100 | FD_CLOEXEC set |
| `IOCLOSE` | 030 | IOSEEK\|IONOSEEK — sentinel for closed fd |

`IOCLOSE = 030` is a clever encoding: a real fd cannot be both seekable and
non-seekable, so both bits set means "closed."

---

## sh_ioinit()

`Legacy: io.c:473-503`

Called from `init.c:1243` during shell startup.

```
sh_iovalidfd(16)                      /* ensure arrays cover fd 0–15 */
sftable[0] = sfstdin; sftable[1] = sfstdout; sftable[2] = sfstderr
sfnotify(sftrack)                     /* register global notification callback */
sh_iostream(0); sh_iostream(1)        /* install disciplines on stdin, stdout */
outpool = sfopen(NULL, NULL, "sw")    /* pool header (write-only string) */
outbuff = malloc(IOBSIZE + 4)        /* stdout buffer */
errbuff = malloc(IOBSIZE / 4)        /* stderr buffer */
sfsetbuf(sfstderr, errbuff, IOBSIZE/4)
sfsetbuf(sfstdout, outbuff, IOBSIZE)
sfpool(sfstdout, outpool, SFIO_WRITE)
sfpool(sfstderr, outpool, SFIO_WRITE) /* stdout + stderr share a flush pool */
sfset(sfstdout, SFIO_LINE, 0)
sfset(sfstderr, SFIO_LINE, 0)
sfset(sfstdin, SFIO_SHARE|SFIO_PUBLIC, 1)
```

Note: `sh_iostream(2)` (stderr) is not called explicitly — stderr joins
the pool via `sfpool()` but doesn't get a discipline at init time.

---

## sh_iostream(fd) — stream constructor

`Legacy: io.c:557-626`

Central stream constructor. Creates or reinitializes a stream for fd:

1. `sh_iocheckfd(fd)` — lazy probe via fcntl/lseek/fstat for fdstatus.
2. Allocate buffer: read streams get private IOBSIZE+1 buffer, write
   streams share `sh.outbuff`.
3. `sfnew()` — create or reinitialize stream.
4. Allocate `sh_disc_t` discipline with appropriate callbacks:
   - TTY read → `slowread` (line editing, timeouts, prompts)
   - Pipe read → `piperead` (SFIO_IOINTR, job wait)
   - Write pipe → `pipeexcept` (SIGPIPE, ECONNRESET)
   - Write non-pipe → `outexcept` (write errors, pool removal)
5. `sfdisc(iop, dp)` — push discipline.
6. Write streams: `sfpool(iop, sh.outpool, SFIO_WRITE)` — join output pool.
7. `sh.sftable[fd] = iop`.

---

## sftrack() — global notification callback

`Legacy: io.c:2253-2334`

Registered via `sfnotify(sftrack)` in `sh_ioinit()`. SFIO calls this on
every stream lifecycle event.

### SFIO_NEW (stream opened)

For fd < 3: returns immediately (stdin/stdout/stderr are populated manually
in `sh_ioinit`, not via sftrack).

For fd ≥ 3: requires BOTH `!sftable[fd]` AND `fdstatus[fd] == IOCLOSE`.
If both conditions hold: populate `sftable[fd]` and `fdstatus[fd]`, call
`sh_iostream(fd)` to install discipline. Adds to current checkpt's `olist`
(for cleanup on longjmp) only when `pp->mode == SH_JMPCMD`.

### SFIO_CLOSING or SFIO_SETFD with newfd ≤ 2

Clears `sftable[fd]`, sets `fdstatus[fd] = IOCLOSE`. Removes from olist.

### SFIO_SETFD

Invokes `fdnotify` (external fd-notification callback used by history/jobs)
with old and new fd numbers. Also called for SFIO_CLOSING events.

⚠ Hazard: When `newfd < 0` and the event is SFIO_SETFD, the flag is
reclassified to SFIO_CLOSING internally, and `fdnotify` receives `-1` as
the new fd.

Special case: `sh.heredocs` is moved above fd 10 when sftrack sees it
trying to set fd < 10.

### SH_NOTRACK

State flag that suppresses sftrack processing when temporarily disabled.

---

## Redirections: sh_redirect → sh_iorenumber

`Legacy: io.c:1148-1598`

`sh_redirect(struct ionod *iop, int flag)` processes a linked list of ionod
structs (parsed redirect list).

### sh_iorenumber(f1, f2)

`Legacy: io.c:669-717`

Installs the fd at position `f1` into position `f2`:

**For fds ≤ 2 (stdin/stdout/stderr):**

```c
spnew = sh_iostream(f1);
sfsetfd(spnew, f2);         /* move stream's fd */
sfswap(spnew, sp);          /* swap into the static global */
sfset(sp, SFIO_SHARE|SFIO_PUBLIC, 1);
```

The `sfswap(spnew, sp)` is critical: it swaps the contents of the two
Sfio_t structs in-place. After swap, the global `sfstdout` (or sfstderr)
pointer — which is a static address — now describes the redirected fd.
Code throughout ksh writes to `sfstdout`/`sfstderr` without updating
pointers.

**For fds > 2:**

```c
fdstatus[f2] = fdstatus[f1] & ~IOCLEX;
sh_fcntl(f1, F_DUPFD, f2);  /* kernel dup */
```

---

## sh_iosave / sh_iorestore

`Legacy: io.c:1700-1868`

Operates on `filemap[]`, a growable array of `struct fdsave`:

```c
struct fdsave {
    int  orig_fd;    /* fd being saved */
    int  save_fd;    /* where it was copied (≥ 10, CLOEXEC) */
    int  subshell;   /* belongs to a subshell? */
    char *tname;     /* temp file name for >; redirects */
};
```

`sh.topfd` is the current stack depth.

### sh_iosave(origfd, ...)

1. `F_dupfd_cloexec(origfd, 10)` → save_fd.
2. Record in filemap.
3. For fds 0/1/2: `sfswap(sp, NULL)` — create fresh copy at save_fd.

### sh_iorestore(last, jmpval)

Iterate filemap backwards:
1. For `>;` truncation: sfsync then ftruncate.
2. `sh_close(origfd)` — close redirect.
3. `sh_fcntl(savefd, F_DUPFD, origfd)` — restore.
4. For fds 0/1/2: `sfswap(sftable[savefd], sftable[origfd])` — swap back.
5. `sh_close(savefd)`.

---

## Here-documents: io_heredoc()

`Legacy: io.c:1602-1681`

Here-doc bodies accumulate in `sh.heredocs` (a `sftmp()` temp file) during
parsing. Each ionod has `iooffset` and `iosize` recording its position.

### Flow

```
outfile = sftmp(0)                           /* or sftmp(size) */
sfputr(outfile, name, '\n')                  /* here-string <<< */

/* or for heredocs: */
infile = subopen(sh.heredocs, offset, size)  /* bounded read view */
sfmove(infile, outfile, SFIO_UNBOUND, -1)    /* copy raw bytes */
/* or: sh_machere(infile, outfile, name)     /* expand $vars */

fd = sffileno(outfile)
sfsetfd(outfile, -1)                         /* detach fd from stream */
sfclose(outfile)                             /* free stream, keep fd */
lseek(fd, 0, SEEK_SET)
```

`subopen()` creates a bounded read view via a `sub_disc` discipline on a
PSEUDOFD stream (fd=32767, not a real kernel fd).

---

## Command substitution capture

`Legacy: subshell.c:524-798`

### Setup

```c
sp->saveout = sfswap(sfstdout, NULL);  /* detach current sfstdout */
iop = sftmp(PIPE_BUF);                /* capture buffer */
sfswap(iop, sfstdout);                /* install as new sfstdout */
sfset(sfstdout, SFIO_READ, 0);
```

All writes to sfstdout now go to the sftmp. If output exceeds PIPE_BUF
(512 bytes), the string stream promotes to a real temp file.

### Execute

`sh_exec(t, flags)` runs in virtual subshell.

### Teardown

```c
iop = sfswap(sfstdout, NULL);          /* recover capture buffer */
sfset(iop, SFIO_READ, 1);             /* switch to read mode */
sfswap(sp->saveout, sfstdout);        /* restore original sfstdout */
```

The returned `iop` is read by macro.c to collect substitution text.

`Polarity:` Command substitution capture is a complete polarity round-trip:
(1) save computation context (detach stdout), (2) install value target
(sftmp), (3) execute command (computation produces values into sftmp),
(4) restore computation context (swap back), (5) reverse the capture
buffer's polarity (`sfset(iop, SFIO_READ, 1)` — value-producing becomes
value-consuming). Steps 4–5 are a polarity reversal of the capture buffer.

### ${ ...; } shared-state comsub

Does not swap sfstdout — body executes with parent's stdout intact.

---

## Pipes: sh_pipe()

`Legacy: io.c:943-1005`

Default: `socketpair(AF_UNIX, SOCK_STREAM)` + `shutdown()` for
unidirectional. Falls back to `pipe2()` with `--posix`.

After creation:
- `fdstatus[pv[0]] = IONOSEEK|IOREAD|cloexec`
- `fdstatus[pv[1]] = IONOSEEK|IOWRITE|cloexec`
- If either end is fd 0/1/2: `sh_iomovefd(pv[i], 3)` — push above 2.

---

## Co-processes: sh.cpipe / sh.coutpipe

`Legacy: xec.c:3383-3423`

```
sh.cpipe[0] = shell reads co-process output
sh.cpipe[1] = shell writes to co-process stdin (moved ≥ 10)
sh.coutpipe = sh.inpipe[1]  (write to co-process)
```

In redirections: `>&p` → `sh.coutpipe`, `<&p` → `sh.cpipe[0]`.

---

## Output pooling

`sfstdout` and `sfstderr` share `sh.outpool` (write pool). The SFIO pool
mechanism ensures: when any pool member flushes, all others flush first.
Prevents interleaving of stdout and stderr output.

`sh.outpool` is a write-only string stream that serves only as a
synchronization anchor (never actually written to).

Before executing external commands: `sfpool(sfstderr, NULL, SFIO_WRITE)` —
remove stderr from pool to prevent it from pulling in stdout's buffers.

---

## sfstderr ≠ stderr

`sfstderr` is a static `Sfio_t` object. ksh redirects it via `sfswap()` +
`sfsetfd()` — the struct contents change, but the pointer stays fixed.

stdio's `stderr` always maps to kernel fd 2. `sfstderr` can map to any fd
after a redirection.

`Contract:` All ksh error output and prompts must use `sfstderr`, not
`fprintf(stderr, ...)`. Code that uses stdio's stderr bypasses shell
redirections.

---

## Pre-fork flush call sites

| Location | Call |
|----------|------|
| `xec.c:2950` (sh_fork) | `sfsync(NULL)` |
| `xec.c:1281` (before execve) | `sfsync(NULL)` after `sfpool(sfstderr, NULL)` |
| `subshell.c:543` | `sfsync(sh.outpool)` at virtual subshell start |
| `path.c:980` | Before `execv()` in path_spawn |
| `io.c:1828` | Before `ftruncate` during `>;` restore |

---

## Architecture summary

```
Shell_t.sftable[fd]         →  Sfio_t stream object
  └── Sfdisc_t discipline chain
        ├── slowread/slowexcept   (tty: prompts, timeouts)
        ├── piperead/pipeexcept   (pipe: SIGPIPE, job sync)
        └── outexcept             (output error handling)

Shell_t.fdstatus[fd]        →  IOREAD|IOWRITE|IONOSEEK|IOTTY|IOCLEX|IOCLOSE
Shell_t.fdptrs[fd]          →  ptr into filemap (save/restore tracking)

sh.outpool                  →  SFIO pool: sfstdout + sfstderr flush together
sh.heredocs                 →  sftmp() accumulator for all here-docs

filemap[0..topfd-1]         →  save/restore stack (struct fdsave[])

sftrack()                   →  SFIO global callback → sftable/fdstatus sync
sfswap()                    →  in-place struct swap → sfstdout/sfstderr redirect
sftmp()                     →  anonymous temp file → here-docs + comsub capture
```

`Polarity:` I/O redirections are polarity boundary crossings. The sfswap
operation changes what value flow (which fd) a computation context
(the shell's execution) connects to — the stream identity (address) is
the polarity frame that holds stable across the crossing.

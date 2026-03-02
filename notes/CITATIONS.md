# Citations

Design influences and references for ksh26 code. When we borrow a
pattern or idea from an external project, record it here with the
source, license, and what we took.

## ast_wbuf_t (writer monad for string construction)

The `ast_wbuf_t` API replaces sfio string streams with a thin wrapper
over POSIX `open_memstream(3)`. Its design incorporates patterns from
two external projects:

### antirez/sds — Simple Dynamic Strings

- **Source**: <https://github.com/antirez/sds>
- **License**: BSD-2-Clause
- **Author**: Salvatore Sanfilippo (antirez)
- **What we took**:
  - *Consistent error return convention*: all mutation operations return
    a value that signals failure (negative int or NULL). Callers
    propagate errors through the call chain without ad-hoc checking.
    In sds this appears as `s = sdsMakeRoomFor(s, len); if (s == NULL)
    return NULL;` — we use the same pattern with int returns from
    write ops and NULL returns from extract ops.
  - *Debug assertions on invariants*: sds asserts bounds in
    `sdsIncrLen()`. We assert `w->fp != NULL` in all operations to
    catch use-after-close in debug builds.
- **What we didn't take**: variable-sized header trick (irrelevant —
  `open_memstream` manages our buffer), `sdscatfmt` fast-path formatter
  (libc `vfprintf` is sufficient).

### git strbuf

- **Source**: <https://github.com/git/git/blob/master/strbuf.h>
- **License**: GPL-2.0 (no code taken — only general API design patterns)
- **What we took**:
  - *Static initializer macro*: git's `STRBUF_INIT` allows stack
    declaration without calling an init function. Our `AST_WBUF_INIT`
    (`{ NULL, 0, NULL }`) enables the same lazy-open pattern.
  - *Detach as distinct from close*: git separates `strbuf_detach()`
    (transfer buffer ownership to caller) from `strbuf_release()` (free
    everything). Our `ast_wbuf_detach()` closes the stream and returns
    a caller-owned buffer, distinct from `ast_wbuf_close()` which frees
    both.
- **What we didn't take**: the 60+ function API surface, I/O operations,
  string manipulation helpers.

### clibs/buffer

- **Source**: <https://github.com/clibs/buffer>
- **License**: MIT
- **Reviewed but not used**: too simple for our needs (no formatted
  output, no positional access). The 1024-byte aligned growth strategy
  is handled by `open_memstream` in our case.

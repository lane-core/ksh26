# ksh26: Theoretical Foundation

## What this document is

ksh93's interpreter has structure that the original authors built correctly
but never named. Two execution modes, boundary crossings with state
discipline, dual error conventions, a continuation stack — these aren't
abstractions we're imposing; they're patterns already present in the C code,
maintained by careful programming across three decades.

Sequent calculus, polarized type theory, and duploid semantics give us
precise vocabulary for these patterns. This document maps the theory onto
the codebase: where the modes are, where the boundaries fall, what invariants
hold at each crossing, and what goes wrong when they're violated. The
analysis found bugs [001]–[003b] and informs every direction in
[REDESIGN.md](REDESIGN.md).

[001]: ../bugs/001-typeset-compound-assoc-expansion.ksh
[002]: ../bugs/002-typeset-debug-trap-compound-assign.ksh
[003a]: ../bugs/003-debug-trap-self-unset.ksh
[003b]: ../bugs/003-debug-trap-free-restore-uaf.ksh


## The observation

ksh93 already has sequent calculus structure. It just doesn't know it.

The shell has not two but **three** syntactic categories:

- **Producers** (words): literals, parameter expansions, quoted strings,
  arithmetic expressions. They produce values.
- **Consumers** (contexts): what's waiting to receive a value — a pipe reader,
  a redirect target, a variable assignment's left-hand side, the rest of the
  script after a command finishes.
- **Statements** (commands): a producer *cut against* a consumer. `echo hello`
  is a cut: the producer `hello` meets the consumer (stdout + the remaining
  script). A pipeline `cmd1 | cmd2` is a cut where cmd1's stdout is the
  producer and cmd2's stdin is the consumer.

This three-sorted structure is exactly the λμμ̃-calculus (with connectives) [5, 7], where:
- **Terms** produce values (producers)
- **Coterms** consume values (consumers/contexts)
- **Statements** connect a term to a coterm via a *cut* ⟨t | e⟩

The entire evaluation model respects this distinction — words go through
expansion (macro.c), commands go through execution (xec.c), and contexts are
managed via the continuation stack (fault.h) — but the boundaries are implicit,
enforced by convention and careful C coding rather than by any structural
invariant.

When the boundaries are respected, everything works. When they aren't — when a
computation-mode operation intrudes into a value-mode context without proper
mediation — you get bugs. The `sh.prefix` corruption bugs (001, 002) are
textbook examples of what happens when the cut discipline is violated.

The fix pattern is always the same: save, clear, do the work, restore. That
pattern is a **shift** — the exact mechanism that polarized type theory uses to
mediate between values and computations. ksh93 is reinventing this mechanism
ad-hoc, one bug at a time.


## Theoretical framework

Nine papers provide the formal scaffolding, each contributing a different angle
on the same underlying structure. They're not prescriptive — we're not
implementing a type checker — but they give us vocabulary for structures that
already exist in the codebase.

### The calculus

**Curien and Herbelin** [5] introduced the λμμ̃-calculus as a term assignment
for classical sequent calculus. Three syntactic categories: terms (μ-binder
captures the current context), coterms (μ̃-binder captures the current value),
and commands (a cut ⟨t | e⟩ connecting them). This is the foundation everything
else builds on.

**Spiwack** [1] dissects this into a **polarized** variant: positive types
(values, introduced eagerly) vs negative types (computations, introduced
lazily). The polarized discipline controls evaluation order and eliminates
non-confluence. Shift connectives (↓N for thunking, ↑A for returning) mediate
between polarities. Polarized L is a linear variant of Levy's CBPV [4].

### The duality

**Wadler** [6] shows that call-by-value is the De Morgan dual of call-by-name.
His **dual calculus** makes this an involution: dualizing twice returns to the
original term. The critical pair — a covariable abstraction (S).α cut against a
variable abstraction x.(T) — is the precise point where non-confluence arises.
CBV resolves it by restricting the left rule to values; CBN by restricting the
right rule to covalues.

This critical pair is the structural condition underlying the sh.prefix bugs: a computation
context (covariable abstraction / DEBUG trap) cut against a value context
(variable abstraction / compound assignment), with two possible reduction orders
yielding different results.

**Curien and Munch-Maccagnoni** [8] resolve this via **focalization**: in the
focused calculus, the critical pair has only one reduction order. This is the
theoretical basis for the polarity frame API — see §"The critical pair" for the
concrete application.

### The semantics

**Mangel, Melliès, and Munch-Maccagnoni** [2] define **duploids** — non-
associative categories that integrate call-by-value (Kleisli/monadic) and call-
by-name (co-Kleisli/comonadic) computation. Three of four associativity
equations hold; the fourth's failure captures the CBV/CBN distinction. Maps
restoring full associativity are **thunkable** (pure, value-like). In a
**dialogue duploid** (duploid + involutive negation), thunkable = central:
purity and commutativity coincide in the presence of classical control
(Hasegawa-Thielecke theorem).

**Munch-Maccagnoni's thesis** [3] is where duploids originate. Develops the
adjoint equation framework and shift-based polarity discipline. The companion
paper [9] gives the clearest self-contained definition of pre-duploids and
duploids, and Table 1 maps the abstract structure to concrete PL concepts:
thunk, return, Kleisli (monadic), co-Kleisli (comonadic), and oblique maps.

### The practice

**Binder, Tzschentke, Müller, and Ostermann** [7] present the λμμ̃ as a
compiler intermediate language, compiling a surface language **Fun** into a
sequent-calculus-based **Core**. The most accessible introduction in our
collection. Key insights:

- **Evaluation contexts are first-class**: the μ̃-binder reifies "what happens
  next" as a bindable object. This is what `struct checkpt` already is.
- **Let-bindings (μ̃) are dual to control operators (μ)**: variable assignment
  is dual to trap/label setup. Not two separate mechanisms — the same operation
  viewed from opposite sides of the cut.
- **Case-of-case falls out as μ-reduction**: commutative conversions (important
  compiler optimizations) are just ordinary β-reduction in the sequent calculus.
- **⊕ vs ⅋ error handling**: tagged error return (like `$?` / Rust's Result)
  is dual to continuation-based error handling (like traps / JS onSuccess/
  onFailure callbacks). The shell has both conventions, and the sequent calculus
  explains why they coexist.


## The correspondence

The mapping isn't metaphorical. These are structural correspondences — at
varying levels of precision, from formal identifications (the three-sorted AST,
the continuation stack, the let/control duality) to structural analogies (the
monadic expansion pipeline, commands as oblique maps). The failure modes and fix
disciplines are shared across levels; what varies is how much of the formal
structure carries over. Where the evidence supports a direct identification, the
text below says "is"; where the correspondence is structural but incomplete, it
says "has the structure of" or "composes like."

### Three sorts: producers, consumers, statements

| Shell concept | λμμ̃ analog | Where in the code |
|---|---|---|
| Words (literals, expansions, quoted strings) | Terms / producers | macro.c — the expansion engine (~3000 lines) |
| Contexts (pipe reader, redirect target, assignment LHS, trap handler) | Coterms / consumers | fault.h (checkpt), shell.h (sh.st.trap[]) |
| Commands (simple, pipeline, compound) | Statements / cuts ⟨t \| e⟩ | `sh_exec()` in xec.c — switch on Shnode_t type |
| Shnode_t union (shnodes.h) | AST for all three sorts | Tagged by `tretyp & COMMSK` |
| Shell command execution | Oblique map P → N [9] | `sh_exec()` dispatching on Shnode_t |

The AST embeds this three-way distinction. `TCOM` (simple command) is a
statement: it holds both `comarg` (producer — the arguments) and `comnamp` (the
command to execute — which determines how the values are consumed). `TFIL`
(pipe) is a statement connecting a producer (left command's stdout) to a
consumer (right command's stdin). The `argnod` struct carries pure value-level
data. The `ionod` struct describes I/O redirections — contexts/consumers that
determine where produced values flow.

### Shifts: crossing the polarity boundary

| Shell mechanism | Shift type | Direction | Where |
|---|---|---|---|
| `$(cmd)` command substitution | Force then return (↓→↑) | computation → value | macro.c (comsubst handling) |
| `<(cmd)` process substitution | Thunk (↓N) | computation → storable value | io.c (process sub as fd path) |
| `eval "$string"` | Force (elim ↓) | value → computation | bltins/misc.c, b_eval() |
| `x=val; rest` (assignment then continue) | μ̃-binding (let) | bind value, continue | name.c, nv_setlist() |
| Function call / return | μ-abstraction / return | capture continuation, compute | xec.c TCOM handler |

The shift connectives in System L have "reversed introduction rules" — ↑A
(return/val) is *negative* but introduced by a *value* operation, and ↓N
(thunk) is *positive* but introduced by a *computation* operation. This is
exactly how `$(cmd)` works: a command (negative) is *forced* to produce a value
(positive) that can be substituted into word position. And `eval` does the
reverse: a string value (positive) is *forced* into command position (negative).

Most entries in the shift table are formal identifications with the shift
connectives. The exception is process substitution (`<(cmd)`): the polarity
shift is genuine — a computation is packaged as a storable value — but the
process runs eagerly, making it closer to a future than a lazy thunk. The ↓N
label captures the polarity structure, not the evaluation strategy.

### The let/control duality

Binder et al. [7] show that let-bindings (μ̃) are exactly dual to control
operators (μ). In ksh93:

| μ̃ (let / value-binding) | μ (control / context-binding) |
|---|---|
| `x=val` — bind a value to a variable | `trap 'handler' SIG` — bind a handler to a signal context |
| `typeset x=val` — declare + bind | `label α {body}` — declare + bind a continuation |
| nv_setlist() in name.c | sh_debug() / sh_trap() in xec.c |
| Extends Γ (antecedent / variable context) | Extends Θ (succedent / continuation context) |

These are not separate mechanisms that happen to look similar. They are the
*same structural operation* — binding a name in a context — applied on opposite
sides of the sequent. The save/restore discipline they both require is the
same because they are dual.

### The ⊕ / ⅋ error-handling duality

ksh93 supports two conventions for error handling, and they are dual in the
sense of linear logic (⊕/⅋ originate there; the error-handling interpretation
is from [7]):

| ⊕ (caller inspects result) | ⅋ (callee invokes continuation) |
|---|---|
| Exit status `$?` | `trap 'handler' ERR` |
| `if cmd; then ok; else err; fi` | Trap handler runs automatically on error |
| Caller's responsibility to check | Callee decides which continuation to invoke |
| Data type (case/pattern-match) | Codata type (copattern-match) |

The exit status convention (⊕) is like Rust's `Result<T,E>`: the function
returns a tagged value and the caller must inspect it. The trap convention (⅋)
is like passing onSuccess/onFailure callbacks: the function *chooses* which
continuation to invoke, and the caller doesn't need to check anything.

Both conventions coexist in ksh93 because both are legitimate. The sequent
calculus explains their relationship: they are De Morgan duals, connected by the
same involutive negation that swaps CBV and CBN.

### Continuations and classical control

| Shell mechanism | Sequent calculus analog | Where |
|---|---|---|
| `sigjmp_buf` / `struct checkpt` | Continuation frame (reified coterm) | fault.h |
| `sh.jmplist` (linked stack of checkpts) | Continuation stack (μ-variable binding) | shell.h (`Shell_t`) |
| `sh_pushcontext` / `sh_popcontext` | Save/restore continuation | fault.h |
| Traps (DEBUG, ERR, EXIT) | Delimited continuations | `sh.st.trap[]` (shell.h) |
| `break` / `continue` / `return` | Named continuation jumps (goto α) | sh.st.breakcnt, SH_JMPFUN, etc. |
| Subshell `(...)` | Classical contraction (fork continuation) | xec.c TPAR handler |

The longjmp mode values (`enum sh_jmpmode` in fault.h) are a taxonomy of 13
continuation types, ordered by severity. Below `SH_JMP_PROPAGATE` (= `SH_JMPFUN`),
errors are caught locally (⊕ — the caller inspects); at or above it, they propagate
up the call stack (⅋ — the callee drives control):

```
SH_JMPNONE(0)  SH_JMPBLT(1)  SH_JMPDOT(2)  SH_JMPEVAL(3)
SH_JMPTRAP(4)  SH_JMPIO(5)   SH_JMPCMD(6)
                                ─── SH_JMP_PROPAGATE ───
SH_JMPFUN(7)   SH_JMPERRFN(8) SH_JMPSUB(9)  SH_JMPERREXIT(10)
SH_JMPEXIT(11) SH_JMPSCRIPT(12)
```

Each represents a different way to *cut* the current computation and resume at a
captured context. The `SH_JMP_PROPAGATE` boundary is itself an instance of the
⊕/⅋ duality (§"The ⊕ / ⅋ error-handling duality"): modes below it are recoverable
returns; modes at or above it are propagating jumps.

The `sh_pushcontext` / `sh_popcontext` macros implement a stack discipline for
these continuations — exactly the μ-binding discipline where `μα.c` captures
the current context as α and runs command c.

### Scoping as viewpath (CDT shadow chains)

| Shell mechanism | Categorical analog | Where |
|---|---|---|
| `sh.var_tree` / `sh.var_base` | Scoped environment (context extension) | shell.h (`Shell_t`) |
| `dtview(child, parent)` | Viewpath linking (scope chain) | `sh_scope()` in name.c |
| Function-local scope | New scope node in viewpath | `dtview(newscope, sh.var_tree)` in name.c |

When a function is called, a new CDT dictionary is allocated and linked via
`dtview()` to shadow the caller's scope. Lookup walks the chain. This is
environment extension — the sequent context Γ, x:A extends Γ with a new
binding, and lookup proceeds by searching the extended context first.

### The monolithic state: `Shell_t`

The entire interpreter state lives in a single struct (`Shell_t` in shell.h).
The fields relevant to the polarity story:

```
sh.prefix    — compound assignment context (positive mode marker)
sh.st        — scoped state snapshot (struct sh_scoped)
sh.jmplist   — continuation stack head
sh.var_tree  — current scope (mutable)
sh.var_base  — global scope (stable)
sh.stk       — stack allocator (bulk-freed at boundaries)
```

The problem isn't that these fields exist — they correspond to real semantic
concepts. The problem is that they're all mutable fields on a single global
struct with no structural enforcement of when they can be read or written. Any
function anywhere can reach into `sh.prefix` and corrupt it, because nothing in
the type system or the calling convention prevents it.


## Where the structure breaks down

### The critical pair

Wadler [6] identifies the exact point where non-confluence arises: a covariable
abstraction (S).α cut against a variable abstraction x.(T). The two possible
reductions yield different results:

```
        (S).α • x.(T)
       ↙              ↘
  S{x.(T)/α}    T{(S).α/x}
```

In the calculus, this is a pure phenomenon: two reduction strategies yield
different normal forms, and the system is non-confluent. In an interpreter with
shared mutable state, the same structural condition — two valid reduction
orders — manifests as state corruption: which reduction fires first determines
whether shared state is left in a consistent or corrupted configuration. The
critical pair identifies the *structural condition*; the shell bug is a specific
instantiation in a stateful setting.

In ksh93, this critical pair manifests concretely. Consider `typeset` during a
compound assignment while a DEBUG trap is active:

```
     typeset -C var=(field=val)    ← compound assignment context (sh.prefix set)
              ↓
         DEBUG trap fires          ← computation intrudes into value context
        ↙              ↘
  trap first           assignment first
  (sh.prefix leaked)   (sh.prefix correct)
```

The compound assignment context (`sh.prefix` set, value mode) is the variable
abstraction x.(T). The DEBUG trap is the covariable abstraction (S).α. Which
one reduces first determines whether `sh.prefix` is corrupted.

CBV resolves this by restricting the left reduction rule to **values**: only
values — not arbitrary computations — may substitute into variable abstractions.
The shell is *mostly* CBV: variables hold word-level data, not suspended
commands, and this restriction normally prevents the critical pair from forming.
But traps, eval, and name resolution side effects inject computation into value
contexts, creating a mixed regime. At these boundaries, the CBV restriction
fails to hold and the critical pair appears — not as a violation of CBV, but as
evidence that the shell operates in a region where pure CBV discipline doesn't
fully apply.

Curien and Munch-Maccagnoni [8] show that **focalization** eliminates the
critical pair syntactically: in the focused calculus, there is only one way to
reduce ⟨μα.c₁|μ̃x.c₂⟩. The polarity frame API (`sh_polarity_enter`/
`sh_polarity_leave`) enforces at runtime what focalization guarantees at the
type level: a deterministic reduction order at every boundary crossing. Both
resolve the same structural problem; the mechanism differs (syntactic prevention
vs runtime enforcement), but the resolution strategy is the same. See
§"Tightening the analogies" for incremental steps that narrow the gap between
runtime enforcement and structural prevention.

### Non-associativity made concrete: the sh.prefix bugs

The duploid framework [2] provides the categorical perspective on the same
phenomenon: composition of value-mode and computation-mode operations is
**non-associative**. Three of four associativity equations hold; the one that
fails is the (+,−) equation: `(h ○ g) • f ≠ h ○ (g • f)` where • composes
through a positive (value) intermediary and ○ through a negative (computation)
intermediary [2, 3]. The two bracketings evaluate `f` and `h` in different
orders — exactly the non-determinism in the critical pair.

Concretely, take the three operations that compose in bug 002:

```
f: parameter expansion         positive (produces an expanded value)
g: compound assignment body    positive → negative (sets sh.prefix, enters computation)
h: DEBUG trap dispatch         negative (computation-mode intrusion)

(h ○ g) • f    f produces a value; g and h compose in computation mode.
               g's sh.prefix is contained within the (h ○ g) frame —
               the trap fires with sh.prefix managed by the frame.

h ○ (g • f)    g and f compose through the positive intermediary — f
               expands within g's sh.prefix context — then h fires
               around the result, seeing (and corrupting) sh.prefix.
```

The left bracketing contains `sh.prefix` within the computation frame; the
right exposes it. Bug 002 is the right bracketing in action.

**Bug 001** (`bugs/001-typeset-compound-assoc-expansion.ksh`): `typeset -i`
combined with compound-associative array expansion produces "invalid variable
name." Root cause: the lexer's S_DOT handler (lex.c:873) resets
`varnamelength` when it sees `.` preceded by `]`, which is correct for
compound LHS names like `foo[x].bar=value`. But the handler had no nesting-
level guard: in `typeset -i n=${#T[k].arr[@]}`, the `.` between `T[k]` and
`arr` is inside the `${}` expansion, not part of the LHS name `n`. The
handler fired anyway, zeroing `varnamelength` from 1 to 0, causing `parse.c`
to write an empty name and `nv_open("", ...)` to fail. Fixed in commit
91f0d162 (lex.c): add a `lp->lexd.level==inlevel` guard.

**Bug 002** (`bugs/002-typeset-debug-trap-compound-assign.ksh`): `typeset`
inside a function fails when called from a DEBUG trap during compound
assignment. Root cause: `sh_debug()` in xec.c executes the trap handler
without saving/restoring `sh.prefix`. The compound assignment context
(`sh.prefix` set, positive mode) is a value-level operation; the DEBUG trap
is a computation-level operation. Running the trap without clearing the prefix
lets the computation context corrupt the value context. Fixed by the
polarity lite frame in `sh_debug()`.

**Bug 003a** (`bugs/003-debug-trap-self-unset.ksh`): `trap - DEBUG` inside a
DEBUG trap handler has no lasting effect — the trap keeps firing. Root cause:
`sh_debug()` saves the full `sh.st` struct (including `sh.st.trap[]`) before
running the handler, then does a blanket restore afterward. The handler's
`trap - DEBUG` zeros the trap slot, but the restore overwrites it with the old
pointer, resurrecting the trap. This is a **stale context** violation: the saved
state becomes invalid during handler execution, and the restore clobbers the
handler's intentional mutation.

**Bug 003b** (`bugs/003-debug-trap-free-restore-uaf.ksh`): Related to 003a,
but the failure mode is use-after-free. The handler's `trap - DEBUG` frees the
trap string and zeros the slot. But the saved `sh.st` copy still holds the now-
freed pointer. The blanket restore writes this dangling pointer back to
`sh.st.trap[]`, and the next DEBUG event dereferences it.

Both 003a and 003b are stale context violations (§"The taxonomy of boundary
violations", category 2), distinct from the missing-shift bugs (001, 002). The
fix requires **selective restoration**: the polarity frame must honor the
handler's mutations to trap state while restoring other scoped fields. This is
exactly what `sh_polarity_leave` implements — it restores `sh.prefix`,
`sh.namespace`, and `sh.var_tree`, but preserves the handler's trap state
changes.

### The save/restore pattern IS the shift

Look at the sh.prefix usage across the codebase (name.c has 30+ occurrences):

```c
/* name.c — entry to compound name resolution */
char *prefix = sh.prefix;

/* name.c — around macro expansion within name resolution */
sh.prefix = 0;
/* ... expand ... */
sh.prefix = prefix;

/* xec.c — around trap execution (now via polarity frame) */
sh_polarity_enter(&frame);    /* saves and clears sh.prefix */
/* ... run trap ... */
sh_polarity_leave(&frame);    /* restores sh.prefix */
```

This is not ad-hoc defensive programming. It is the *implementation* of a
polarity shift: entering a negative (computation) context from a positive
(value) context requires clearing the positive marker, doing the computation,
then restoring it. The pattern recurs because the boundary crossing recurs — and
every time someone forgets to add it, you get a new bug.

The same pattern applies to the full scoped state (`sh.st`) in `sh_debug()`
and `sh_trap()` (via polarity frames), and to the continuation stack
everywhere via `sh_pushcontext` / `sh_popcontext` (fault.h).

### Monadic and comonadic patterns in C

The duploid [2, 9] integrates two familiar compositional styles: Kleisli
(monadic/CBV — thread values through effectful steps) and co-Kleisli
(comonadic/CBN — extract from and extend contexts). Both appear as concrete C
idioms in ksh93. Commands have the structure of oblique maps P → N [9, Table 1]:
they receive values and enter computation, matching the type signature. Whether
the full composition laws carry over is unverified (structural analogy; see
§"Tightening the analogies" for a refined composition hierarchy). Formal
definitions stay in the references; this section shows what the patterns look
like in C.

#### The monadic side: value composition (macro.c)

Word expansion composes like Kleisli maps. Each stage — tilde → parameter →
command sub → arithmetic → field split → glob — takes a partial value, produces
an expanded value with possible side effects, and passes the result forward.
The `Mac_t` struct (macro.c:81) is the monadic state threaded through the
pipeline: `sh_macexpand()` (entry point; takes `argnod*`, accesses `Mac_t` via
`sh.mac_context`) → `copyto()` → `varsub()` → `comsubst()`.

The implementation is a character-scan event loop (`copyto()` in macro.c:441)
rather than sequential function calls, but the expansion pipeline has monadic
structure: each stage is a Kleisli-shaped step (value in → expanded value +
effects), with `Mac_t`/`Stk_t` state and `siglongjmp` errors as the implicit
monad. The stages compose within `copyto()`'s character loop rather than via
explicit bind — structural analogy, not formal Kleisli composition. See
§"Tightening the analogies" for what explicit threading would require.

Associativity holds within this pipeline: the stages compose freely because
they all operate on the same polarity (positive/value). What breaks
associativity is interleaving expansion with computation — command substitution
mid-expansion requires a shift. `comsubst()` implements this explicitly: it
saves `Mac_t` and the stack state, enters computation mode via `sh_subshell()`,
then restores the expansion context.

#### The comonadic side: context management (xec.c, fault.h)

Command execution operates comonadically on contexts. The interpreter carries
a rich evaluation context (`sh.prefix`, `sh.st`, `sh.var_tree`, `sh.jmplist`)
and operations extract from, extend, and restore it.

Pattern in C:

```c
/* Comonadic extract/extend/restore */
frame.field = sh.field;     /* extract: observe the current context */
sh.field = new_value;       /* extend: modify for nested computation */
result = compute();         /* operate in extended context */
sh.field = frame.field;     /* restore: return to outer context */
```

This is exactly what `sh_polarity_lite_enter`/`sh_polarity_lite_leave`
(xec.c:533–551) and `sh_pushcontext`/`sh_popcontext` (fault.h:110–123) do.
The polarity frame API consolidates ad-hoc instances of this pattern.

Associativity also holds within the comonadic side: nested context frames
compose correctly (push A, push B, pop B, pop A). What breaks associativity
is when a value-mode operation intrudes into the context management — the
(+,−) failure.

#### Oblique maps: where the two sides meet

A shell command functions as an oblique map P → N [9]: it receives values (arguments,
redirections — positive/monadic data) and enters computation mode (executes,
produces side effects, yields an exit status — negative/comonadic context).

The cut ⟨t | e⟩ is `sh_exec(t, flags)`: the AST node `t` meets the execution
context. The `sh_exec` switch dispatches on `tretyp & COMMSK` across all three
sorts: Mixed nodes (TCOM, TWH, TFOR, TSETIO, TFUN) are genuine cuts where
producers meet consumers; Computation nodes (TLST, TAND, TORF, TFIL, TIF) are
sequencing within computation mode; Value nodes (TTST, TSW, TARITH) produce
results without mode crossing.

#### Design guidelines

| You are... | Pattern | C idiom | Example |
|---|---|---|---|
| Threading values through stages | Monadic (Kleisli) | Return result, early-return on error | macro.c expansion pipeline |
| Managing execution context | Comonadic (co-Kleisli) | Save/compute/restore frame | `sh_polarity_lite`, `sh_pushcontext` |
| Crossing value↔computation | Shift | API call at boundary | `sh_polarity_enter`/`sh_polarity_leave` |
| Dispatching on AST node type | Cut (⟨t\|e⟩) | Switch on `tretyp` | `sh_exec()` |
| Handling errors via exit status | ⊕ (data) | Check `$?`, return code | `if(exitval) return` |
| Handling errors via trap | ⅋ (codata) | Continuation jump | `siglongjmp` to `checkpt` |

#### When to use which

- **Adding a new expansion feature?** → Monadic. Add a stage that takes and
  returns values. Thread through `Mac_t`. Use early return for errors.
- **Adding a new execution context?** → Comonadic. Save/restore via polarity
  frame. Never leave mutable global state modified across a boundary crossing.
- **Adding a new builtin?** → Oblique map. It receives arguments (values),
  does computation, returns exit status.
- **The test**: if your change only touches values/words (no context mutation),
  it's monadic. If it saves/restores global state, it's comonadic. If it does
  both, you're at a polarity boundary and need a shift (polarity frame).

### The taxonomy of boundary violations

The documented bugs fit two of four boundary violation patterns predicted by the
framework:

1. **Missing shift** — A computation-mode operation runs in a value-mode context
   without saving/restoring the context markers. (Bugs 001, 002)

2. **Stale context** — A saved context is restored after the underlying state has
   moved on, causing the restoration to overwrite valid state. (Bugs 003a, 003b)

3. **Scope leak** — A `dtview()` chain is set up but not properly unwound,
   leaving dangling scope links. (Predicted — namespace cleanup)

4. **Continuation misfire** — A `siglongjmp` unwinds to the wrong `checkpt`
   because the push/pop discipline was violated. (Predicted — nested eval/trap)

Categories 3 and 4 are not yet represented in the documented bug corpus. The
framework predicts them as the remaining failure modes for scope chains and
continuations respectively; the parentheticals indicate where we expect to find
instances.

All four are instances of the same structural problem: **the polarity
boundary discipline is maintained by convention, not by construction.**


### Tightening the analogies

The calibration in §"Monadic and comonadic patterns in C" identified two
structural analogies (the monadic expansion pipeline and oblique map composition
laws). Two further correspondences are partial identifications with gaps:
focalization (§"The critical pair") resolves the same problem by different
mechanism; process substitution (§"Shifts") has the correct polarity structure
but a different evaluation strategy. This section examines all four, since the
analysis informs refactoring priorities.

#### Monadic expansion pipeline → explicit Kleisli threading

**Current gap**: The expansion stages compose within `copyto()`'s character loop
(macro.c:441) via global `Mac_t` access through `sh.mac_context`, rather than via
explicit Kleisli bind. The monadic structure is present but implicit.

**Existence proof**: `comsubst()` (macro.c:2244) already IS explicit Kleisli
composition. It saves the full `Mac_t` state (`Mac_t savemac = *mp`, line 2253),
enters computation mode via `sh_subshell()`, then restores the expansion context
(`*mp = savemac`, line 2375). This is save → compute → restore: the Kleisli bind
`a >>= f` where `a` is the expansion state, `f` is the command substitution, and
the result is threaded back into the pipeline.

**What would close the gap**: Generalize the `comsubst()` pattern to all stage
transitions within `copyto()`. Concretely:

- Each handler (`S_DOL`, `S_GRAVE`, `S_BRACE`, etc.) explicitly receives `Mac_t*`
  as a parameter rather than reaching through `sh.mac_context`
- Stage boundaries within the character loop use the same save/compute/restore
  pattern that `comsubst()` uses at the command-substitution boundary
- The implicit monad (`Mac_t` + `Stk_t` state + `siglongjmp` errors) is named
  and its bind operation is uniform

Multi-pass restructuring is not needed and would violate POSIX: the standard
requires tilde, parameter, command sub, and arithmetic expansion to be
interleaved within a single scan. The character loop is the correct architecture;
what changes is making the state threading explicit within it.

**Assessment**: Closable to identification. `comsubst()` is the existence proof;
the remaining work is propagating its discipline to the other handlers.

#### Command composition → duploid composition hierarchy

**Current gap**: §"Oblique maps" treats all command composition uniformly as
P → N oblique maps. Examination of `sh_exec()` reveals three distinct composition
patterns, each satisfying a different duploid equation:

| Pattern | Node types | Intermediary | Duploid equation | Mechanism |
|---|---|---|---|---|
| Pipeline | TFIL | Positive (pipe fd) | (•) Kleisli | Data flows left → pipe → right |
| Sequencing | TLST, TAND, TORF | Negative (exec context) | (○) co-Kleisli | Exit status in `sh.exitval`; context shared |
| Cut | TCOM, TFOR, TSETIO | — (fundamental interaction) | ⟨t \| e⟩ | Values meet computation |

**Pipeline (•)**: The TFIL handler (xec.c:1865) creates actual pipes
(`sh_pipe(pvn,1)`, line 1906), executes the left subtree with output redirected
into the pipe, and the right subtree reads from it. The pipe fd is a genuine
positive intermediary — data produced by the left command is consumed by the
right. This IS oblique map composition: the (•) equation holds because both
commands are P → N maps composed through a positive (value/data) link.

**Sequencing (○)**: The TLST handler (xec.c:1978) executes left then right with
no data link. TAND/TORF (xec.c:1993, 2003) branch on the left command's exit
status (`sh_exec(...)==0` / `!=0`). Exit status is carried in the execution
context (negative intermediary), not flowed as a value. This is co-Kleisli
composition: the (○) equation holds because both commands operate within the
same negative (computation) context.

**Cut ⟨t|e⟩**: TCOM expands its arguments (value mode), then executes the
command (computation mode). TFOR expands its word list (value), then iterates
the body (computation). These are not compositions of commands — they are the
fundamental cut where a producer meets a consumer. The polarity frame API
mediates the boundary.

**Assessment**: The correspondence strengthens by differentiating. Individual
commands are oblique maps (the type signature P → N holds). Their *composition*
falls into three categories matching three duploid structures. The uniform claim
was imprecise, not wrong — it described the maps correctly but elided the
distinct composition mechanisms. Naming the hierarchy makes the non-associativity
result sharper: the (+,−) failure (§"Non-associativity made concrete") occurs
specifically when pipeline-style (•) and sequencing-style (○) composition
interact — when a value-mode intermediary appears inside a computation-mode
context.

#### Focalization → structural polarity enforcement

**Current gap**: Focalization prevents the critical pair syntactically (type
system); polarity frames enforce at runtime (save/restore discipline). The
`sh_node_polarity[]` table (shnodes.h:232) classifies all 16 node types by
polarity but is currently metadata — `sh_exec()` doesn't query it to determine
frame discipline.

**Three incremental steps**, each independently moving from convention toward
construction:

**Step 1 — Runtime depth tracking.** Add a `frame_depth` counter to `Shell_t`.
Increment on `sh_polarity_enter`, decrement on `sh_polarity_leave`. Assert
proper nesting unconditionally (two integer comparisons per boundary
crossing — negligible cost on a non-hot path). This catches frame mismatches
(enter without leave, double leave) automatically without changing any handler
logic. Cost: one integer, four assertions. Immediate value: turns silent
corruption into caught violations.

**Step 2 — Activate the polarity table.** `sh_exec()` queries
`sh_node_polarity[]` at dispatch time and auto-pushes a lite frame for
`SH_POL_COMPUTE` nodes that don't already have one. This centralizes the
frame discipline: instead of each handler deciding whether to push a frame,
the dispatch loop handles it based on the classification table. Cost: a
conditional at the top of the switch. Value: reduces the number of sites where
a missing frame can cause a bug from ~16 (each handler) to 1 (the dispatch
conditional).

**Step 3 — Split mixed handlers.** Factor TCOM, TFOR, TWH, TSETIO, and TFUN
into explicit value-phase and computation-phase sub-handlers with a frame
boundary between them. Instead of a single `case TCOM:` that interleaves
argument expansion and command execution, there would be `tcom_expand()` (value
phase — expand arguments, process assignments) and `tcom_execute()` (computation
phase — dispatch to builtin/external/function) with a polarity frame at the
boundary. Cost: significant refactoring of the largest handlers. Value: makes
the polarity boundary structural in the code, not just conventional. This is as
close to syntactic prevention as C gets without custom static analysis tooling.

**Assessment**: Step 1 is nearly free and should be early. Step 3 is the most
invasive but produces code where the polarity boundary is visible in the
function call graph, not just in save/restore patterns within a function.

**Step 2 is architecturally unsound** and should not be implemented. Deep
analysis of the node types shows it would duplicate existing work at the wrong
abstraction level: COMPUTE nodes (TFORK, TPAR, TFIL, TLST, TAND, TORF, TIF,
TTIME) don't set `sh.prefix` and are inherently safe — auto-framing is pure
overhead. MIXED nodes (TCOM, TFOR, TWH, TSETIO, TFUN) already have precise
internal frames at their actual value→computation boundaries. The fundamental
issue is that polarity framing is *caller-side* (sh_debug, sh_trap), not
*callee-side* (node dispatch). The table remains valuable as a classification
aid and for documentation; activating it at dispatch would add overhead without
preventing any bugs that the existing internal frames don't already catch.

#### Process substitution: why eagerness is correct

The `<(cmd)` polarity shift (↓N — packaging a computation as a storable value)
is genuine: a command (negative) is reified as a file path (positive) that can
appear in word position. But the process runs eagerly — the fd must exist before
the consumer opens it, because the consumer may be an external program that does
a synchronous `open(2)`.

This makes `<(cmd)` a **future**, not a **thunk**: same polarity structure (↓N),
different evaluation strategy. A thunk defers execution until first access; a
future starts execution immediately and provides the result when ready. The
eagerness is not a gap to close but a design constraint imposed by POSIX process
semantics. Lazy evaluation would require the shell to intercept the consumer's
`open(2)` and start the producer on demand — possible in theory (via FUSE or
ptrace), but architecturally absurd for a shell.

The analogy label is correct: the polarity shift is exact, the evaluation
strategy differs from the theoretical thunk.


## The refactoring direction

### Principle: make the implicit structure explicit

The goal is not to rewrite ksh93 in a functional style or add a type system.
It's to make the three-sorted, shift-mediated, continuation-stack structure
that *already exists* visible and enforceable in the C code.

Binder et al. [7] frame this as compilation: their surface language **Fun** is
compiled into a sequent-calculus IR **Core** that makes evaluation contexts
first-class. ksh93's interpreter already *is* this compilation pipeline — the
parser produces an AST (surface), and `sh_exec()` evaluates it using a
continuation stack, scope chain, and polarity markers (core). The refactoring
makes the core representation principled rather than accidental.

### Concrete directions

**1. Context frames instead of global mutation**

The ad-hoc `sh.prefix` / `sh.st` save/restore pattern has been replaced with
explicit context frames that are pushed and popped at polarity boundaries.
Instead of:

```c
char *savprefix = sh.prefix;
sh.prefix = NULL;
/* ... computation ... */
sh.prefix = savprefix;
```

The implemented context-crossing API (shell.h, xec.c):

```c
struct sh_polarity {          /* full frame: all polarity-sensitive state */
    char         *prefix;     /* saved sh.prefix */
    Namval_t     *namespace;  /* saved sh.namespace */
    struct sh_scoped st;      /* saved sh.st */
    Dt_t         *var_tree;   /* saved sh.var_tree */
};

struct sh_polarity_lite {     /* lightweight: prefix, namespace, var_tree only */
    char         *prefix;
    Namval_t     *namespace;
    Dt_t         *var_tree;
};

void sh_polarity_enter(struct sh_polarity *frame);   /* save + clear */
void sh_polarity_leave(struct sh_polarity *frame);   /* restore */
```

`sh_polarity_enter`/`sh_polarity_leave` handle full boundary crossings (trap
dispatch in sh_trap, subshell setup). `sh_polarity_lite_enter`/
`sh_polarity_lite_leave` handle the lightweight case (sh_debug, where trap
state is managed by the inner sh_trap call). Every place that formerly did
ad-hoc save/restore of polarity-sensitive state now uses this API, making
boundary crossings visible and auditable. This is the C analog of Binder
et al.'s static focusing [7] — lifting subcomputations to positions where
they can be properly evaluated.

**2. Classify sh_exec cases by polarity**

The `sh_exec()` switch in xec.c handles 16 base node types (TCOM through TFUN,
defined in shnodes.h; composite types like TUN and TSELECT carry flag bits above
COMMSK). These fall into the three sorts — matching the `sh_node_polarity[]` table
in shnodes.h:

| Value (SH_POL_VALUE) | Computation (SH_POL_COMPUTE) | Mixed (SH_POL_MIXED) |
|---|---|---|
| TTST (`[[ ]]` conditional) | TPAR (subshell) | TCOM (assignments + execution) |
| TSW (case) | TFIL (pipeline) | TWH (condition + body) |
| TARITH (`(( ))`) | TLST (command list) | TFOR (list expansion + body) |
| | TIF | TSETIO (redirection + subtree) |
| | TAND, TORF | TFUN (symbol table + body) |
| | TFORK | |
| | TTIME | |

This classification is now explicit in the `sh_node_polarity[]` constexpr table
(shnodes.h), which handlers can query to determine boundary-crossing discipline.

**3. Within-value prefix isolation**

Name resolution sites that call into nested expansion or assignment — in
`nv_setlist`, `nv_open`, `nv_rename`, and `sh_exec(TFUN)` — need to prevent
the outer compound assignment context from leaking inward. These sites now use
the `sh_prefix_enter`/`sh_prefix_leave` API (`struct sh_prefix_guard` in
shell.h), which saves and clears `sh.prefix`, `sh.prefix_root`, and
`sh.first_root`, then restores them on exit.

This is deliberately lighter than a polarity frame: prefix guards stay within
value mode (no `sh.st` save needed). The guard prevents inner name resolution
from inheriting the outer compound assignment context, eliminating the class of
bugs where inner traversal corrupts the outer prefix.

**4. Unify the continuation stack with polarity frames**

The `checkpt` stack (fault.h) is the continuation mechanism — the
reified coterm/consumer [7]. The mode values (`SH_JMPNONE` through
`SH_JMPSCRIPT`) classify continuations by type. The refactoring:

- Every `sh_pushcontext` has a matching `sh_popcontext` on all code
  paths (including error/longjmp paths)
- Polarity frames complement `struct checkpt`, so entering a new
  continuation frame automatically saves polarity state — the μ-binding and
  the polarity shift become a single atomic operation
- All `siglongjmp` calls have been audited to verify they unwind to the
  correct frame

**5. Name the dual error conventions**

The ⊕/⅋ duality [7] between exit-status checking and trap handling is made
explicit:

- Documenting which functions use ⊕ (return an exit status for the caller to
  inspect) vs ⅋ (invoke a trap/continuation on error)
- Ensuring that the two conventions don't interact incorrectly — specifically,
  that a ⅋-style trap handler doesn't corrupt the ⊕-style exit status path
  or vice versa
- Recognizing that `set -e` (errexit) is a mechanism for *converting* ⊕ to ⅋:
  it takes exit-status-based error reporting and automatically invokes the ERR
  trap continuation, bridging the two conventions

**6. Stack allocator boundaries**

`sh.stk` (the Stk_t stack allocator) is bulk-freed at function and script
boundaries. This is a form of region-based memory management that aligns
naturally with the polarity story: positive (value) allocations live on the
stack and are freed when the enclosing computation frame ends. The stk
boundaries already align at polarity boundary sites; the correspondence is
now documented.


## What this buys us

### Bug prevention

The immediate payoff is structural: bugs like 001, 002, 003a, and 003b become
impossible rather than merely fixed. If boundary crossings go through a
consolidated API, there's exactly one place to get the save/restore right (and
the selective restoration for trap state), instead of 30+.

### Auditability

When someone asks "is this code correct?", the answer can reference structural
properties ("this function operates entirely within a positive context, so it
doesn't need shift discipline") rather than requiring manual trace through
all possible call paths.

### Merge clarity

As the ksh26 branch diverges from dev, the polarity framework gives a
vocabulary for documenting *why* a dev bugfix doesn't apply: "this fix adds a
save/restore for sh.prefix at call site X; in ksh26, this boundary crossing is
handled by sh_polarity_enter() so the fix is structurally unnecessary."

### Optimization vocabulary

The sequent calculus gives names to compiler optimizations that are otherwise
ad-hoc. Case-of-case is μ-reduction [7]. Dead code elimination is weakening.
Common subexpression elimination is contraction. These aren't new optimizations
— they're existing optimizations with a structural justification for when they're
safe to apply.

### Incremental applicability

Nothing here required a big-bang rewrite. Each concrete direction was applied
independently: the context frame API was introduced at a single call site, then
expanded; the polarity classification started as comments and became a constexpr
table; the name resolution refactoring proceeded one function at a time. The
theory provides direction; the implementation proceeds at whatever pace the
codebase allows.


## References

1. Arnaud Spiwack. "A Dissection of L." 2014.
   Source: `~/gist/dissection-of-l.gist.txt`

2. Éléonore Mangel, Paul-André Melliès, and Guillaume Munch-Maccagnoni.
   "Classical notions of computation and the Hasegawa-Thielecke theorem."
   *Proceedings of the ACM on Programming Languages* (POPL), 2026.
   Source: `~/gist/classical-notions-of-computation-duploids.gist.txt`

3. Guillaume Munch-Maccagnoni. "Syntax and Models of a non-Associative
   Composition of Programs and Proofs." PhD thesis, Université Paris Diderot —
   Paris 7, 2013.

4. Paul Blain Levy. *Call-by-Push-Value: A Functional/Imperative Synthesis.*
   Springer, 2004.

5. Pierre-Louis Curien and Hugo Herbelin. "The duality of computation."
   *International Conference on Functional Programming*, 2000.

6. Philip Wadler. "Call-by-Value is Dual to Call-by-Name, Reloaded."
   Invited talk, *Rewriting Techniques and Applications*, 2005. Revised 2008.
   Local: `notes/wadler-reloaded.pdf`

7. David Binder, Marco Tzschentke, Marius Müller, and Klaus Ostermann.
   "Grokking the Sequent Calculus (Functional Pearl)."
   *Proceedings of the ACM on Programming Languages* (ICFP), 2024.
   Source: `~/gist/grokking-the-sequent-calculus.gist.txt`

8. Pierre-Louis Curien and Guillaume Munch-Maccagnoni. "The duality of
   computation under focus." *IFIP TCS*, 2010.
   Local: `notes/duality-of-computation.tex`
   Key contribution: shows focalization eliminates the critical pair (§4:
   "Note that we now have only one way to reduce ⟨μα.c₁|μ̃x.c₂⟩ (no more
   critical pair)"). Formal basis for polarity frames.

9. Guillaume Munch-Maccagnoni. "Models of a Non-Associative Composition."
   FoSSaCS, 2014. Shortened Chapter II of the PhD thesis [3].
   Local: `notes/Models of a Non-Associative Composition.pdf`
   Key contribution: clearest self-contained definition of pre-duploids and
   duploids. Table 1 maps abstract structure to PL concepts (thunk, Kleisli,
   co-Kleisli, oblique maps).

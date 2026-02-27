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
analysis found bugs [001]–[003] and informs every direction in
[REDESIGN.md](REDESIGN.md).

[001]: ../bugs/001-typeset-compound-assoc-expansion.ksh
[002]: ../bugs/002-typeset-debug-trap-compound-assign.ksh
[003]: ../bugs/003-debug-trap-self-unset.ksh


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

This three-sorted structure is exactly the λμμ̃-calculus [5, 7], where:
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

Seven papers provide the formal scaffolding, each contributing a different angle
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

This critical pair is the formal name for the sh.prefix bugs: a computation
context (covariable abstraction / DEBUG trap) cut against a value context
(variable abstraction / compound assignment), with two possible reduction orders
yielding different results.

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
adjoint equation framework and shift-based polarity discipline.

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

The mapping isn't metaphorical. These are structural identifications — the same
patterns, the same failure modes, the same fix disciplines.

### Three sorts: producers, consumers, statements

| Shell concept | λμμ̃ analog | Where in the code |
|---|---|---|
| Words (literals, expansions, quoted strings) | Terms / producers | macro.c — 2984-line expansion engine |
| Contexts (pipe reader, redirect target, assignment LHS, trap handler) | Coterms / consumers | fault.h (checkpt), shell.h (sh.st.trap[]) |
| Commands (simple, pipeline, compound) | Statements / cuts ⟨t \| e⟩ | sh_exec() in xec.c:793 — switch on Shnode_t type |
| Shnode_t union (shnodes.h:190) | AST for all three sorts | Tagged by `tretyp & COMMSK` (shnodes.h:50–67) |

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
| `eval "$string"` | Force (↑) | value → computation | xec.c, b_eval() |
| `x=val; rest` (assignment then continue) | μ̃-binding (let) | bind value, continue | name.c, nv_setlist() |
| Function call / return | μ-abstraction / return | capture continuation, compute | xec.c TCOM handler |

The shift connectives in System L have "reversed introduction rules" — ↑A
(return/val) is *negative* but introduced by a *value* operation, and ↓N
(thunk) is *positive* but introduced by a *computation* operation. This is
exactly how `$(cmd)` works: a command (negative) is *forced* to produce a value
(positive) that can be substituted into word position. And `eval` does the
reverse: a string value (positive) is *forced* into command position (negative).

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
sense of linear logic [7]:

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
| `sigjmp_buf` / `struct checkpt` | Continuation frame (reified coterm) | fault.h:89–112 |
| `sh.jmplist` (linked stack of checkpts) | Continuation stack (μ-variable binding) | shell.h:306 |
| `sh_pushcontext` / `sh_popcontext` | Save/restore continuation | fault.h:99–112 |
| Traps (DEBUG, ERR, EXIT) | Delimited continuations | sh.st.trap[] (shell.h:222) |
| `break` / `continue` / `return` | Named continuation jumps (goto α) | sh.st.breakcnt, SH_JMPFUN, etc. |
| Subshell `(...)` | Classical contraction (fork continuation) | xec.c TPAR handler |

The longjmp mode values (fault.h:71–81) are a taxonomy of continuation types:
`SH_JMPEVAL` (eval return), `SH_JMPTRAP` (trap return), `SH_JMPFUN` (function
return), `SH_JMPSUB` (subshell return), `SH_JMPEXIT` (exit). Each represents a
different way to *cut* the current computation and resume at a captured context.

The `sh_pushcontext` / `sh_popcontext` macros implement a stack discipline for
these continuations — exactly the μ-binding discipline where `μα.c` captures
the current context as α and runs command c.

### Scoping as viewpath (CDT shadow chains)

| Shell mechanism | Categorical analog | Where |
|---|---|---|
| `sh.var_tree` / `sh.var_base` | Scoped environment (context extension) | shell.h:246,288 |
| `dtview(child, parent)` | Viewpath linking (scope chain) | name.c:2280–2292 |
| Function-local scope | New scope node in viewpath | name.c:2280 (`dtview(newscope, sh.var_tree)`) |

When a function is called, a new CDT dictionary is allocated and linked via
`dtview()` to shadow the caller's scope. Lookup walks the chain. This is
environment extension — the sequent context Γ, x:A extends Γ with a new
binding, and lookup proceeds by searching the extended context first.

### The monolithic state: `Shell_t`

The entire interpreter state lives in a single struct (`Shell_t`, shell.h:243).
The fields relevant to the polarity story:

```
sh.prefix      (shell.h:305)  — compound assignment context (positive mode marker)
sh.st          (shell.h:282)  — scoped state snapshot (sh_scoped, shell.h:198–228)
sh.jmplist     (shell.h:306)  — continuation stack head
sh.var_tree    (shell.h:246)  — current scope (mutable)
sh.var_base    (shell.h:288)  — global scope (stable)
sh.stk         (shell.h:283)  — stack allocator (bulk-freed at boundaries)
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
This is exactly the restriction that shell variables hold word-level data, not
suspended commands. When the restriction is violated (via eval, traps, or name
resolution side effects), the critical pair forms and non-confluence appears as
a bug.

### Non-associativity made concrete: the sh.prefix bugs

The duploid framework [2] provides the categorical perspective on the same
phenomenon: composition of value-mode and computation-mode operations is
**non-associative**. Three of four associativity equations hold; the one that
fails is (CBV-then-CBN): `(h ∘ g) ∘ f ≠ h ∘ (g ∘ f)` when the intermediate
type changes polarity. The two bracketings evaluate `f` and `h` in different
orders — exactly the non-determinism in the critical pair.

**Bug 001** (`bugs/001-typeset-compound-assoc-expansion.ksh`): `typeset -i`
combined with compound-associative array expansion produces "invalid variable
name." Root cause: during `nv_create()` path resolution (name.c:749), walking
a dotted path like `T[k].arr` requires entering a compound (positive) context
via `sh.prefix`. When the lexer processes nested `${#...}` expansions, it
resets `varnamelength` without accounting for the active prefix, causing
subsequent declarations to see an empty variable name. Fixed in commit
91f0d162 (lex.c).

**Bug 002** (`bugs/002-typeset-debug-trap-compound-assign.ksh`): `typeset`
inside a function fails when called from a DEBUG trap during compound
assignment. Root cause: `sh_debug()` (xec.c:464) executes the trap handler
without saving/restoring `sh.prefix`. The compound assignment context
(`sh.prefix` set, positive mode) is a value-level operation; the DEBUG trap
is a computation-level operation. Running the trap without clearing the prefix
lets the computation context corrupt the value context. Fixed by adding the
save/clear/restore pattern at xec.c:508–509,524.

### The save/restore pattern IS the shift

Look at the sh.prefix usage across the codebase (name.c has 30+ occurrences):

```c
/* name.c:223 — entry to compound name resolution */
char *prefix = sh.prefix;

/* name.c:271,273 — around macro expansion within name resolution */
sh.prefix = 0;
/* ... expand ... */
sh.prefix = prefix;

/* xec.c:508-509,524 — around trap execution */
char *savprefix = sh.prefix;
sh.prefix = NULL;
/* ... run trap ... */
sh.prefix = savprefix;
```

This is not ad-hoc defensive programming. It is the *implementation* of a
polarity shift: entering a negative (computation) context from a positive
(value) context requires clearing the positive marker, doing the computation,
then restoring it. The pattern recurs because the boundary crossing recurs — and
every time someone forgets to add it, you get a new bug.

The same pattern applies to the full scoped state (`sh.st`) in sh_debug()
(xec.c:504–523), and to the continuation stack everywhere via
`sh_pushcontext` / `sh_popcontext` (fault.h:99–112).

### The taxonomy of boundary violations

Every ksh93 bug we've encountered fits one of these patterns:

1. **Missing shift** — A computation-mode operation runs in a value-mode context
   without saving/restoring the context markers. (Bugs 001, 002)

2. **Stale context** — A saved context is restored after the underlying state has
   moved on, causing the restoration to overwrite valid state. (Various trap
   interaction bugs)

3. **Scope leak** — A `dtview()` chain is set up but not properly unwound,
   leaving dangling scope links. (Namespace cleanup issues)

4. **Continuation misfire** — A `siglongjmp` unwinds to the wrong `checkpt`
   because the push/pop discipline was violated. (Nested eval/trap issues)

All four are instances of the same structural problem: **the polarity
boundary discipline is maintained by convention, not by construction.**


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

Replace the `sh.prefix` / `sh.st` save/restore pattern with explicit context
frames that are pushed and popped at polarity boundaries. Instead of:

```c
char *savprefix = sh.prefix;
sh.prefix = NULL;
/* ... computation ... */
sh.prefix = savprefix;
```

Define a context-crossing API:

```c
struct sh_polarity_frame {
    char *prefix;
    struct sh_scoped st;
    /* other polarity-sensitive state */
};

void sh_enter_computation(struct sh_polarity_frame *frame);
void sh_leave_computation(struct sh_polarity_frame *frame);
```

This is the same save/restore, but named and consolidated. Every place that
currently does ad-hoc save/restore of polarity-sensitive state would use
this API instead, making boundary crossings visible and auditable. This is the
C equivalent of Binder et al.'s static focusing [7] — lifting subcomputations
to positions where they can be properly evaluated.

**2. Classify sh_exec cases by polarity**

The `sh_exec()` switch (xec.c:860) handles 16 node types. These fall into
the three sorts:

| Producers (value-producing) | Consumers (context-managing) | Statements (cut / mixed) |
|---|---|---|
| TCOM (assignments only) | TSETIO (I/O redirection setup) | TCOM (with command) |
| TARITH | | TFIL (pipe: producer \| consumer) |
| | | TPAR (subshell) |
| | | TLST, TAND, TORF |
| | | TIF, TWH, TSW |
| | | TFOR (loop var = value, body = computation) |
| | | TFORK, TFUN |

Making this classification explicit — even just as comments and grouping in the
switch — would clarify which handlers need boundary-crossing discipline and
which don't.

**3. Shift-aware name resolution**

`nv_create()` (name.c:749) walks dotted paths through compound variables. Each
dot-separated component is a boundary crossing: entering a sub-namespace
(positive context within a positive context). The function already manages
`sh.prefix` carefully, but it does so with 30+ manual save/restore sites.

A cleaner approach: `nv_create()` manages a local path-resolution context that
is explicitly separate from `sh.prefix`. The global `sh.prefix` is set only at
the outermost compound assignment boundary, and inner path traversal uses its
own context. This eliminates the class of bugs where inner traversal corrupts
the outer prefix.

**4. Unify the continuation stack with polarity frames**

The `checkpt` stack (fault.h:89–112) is the continuation mechanism — the
reified coterm/consumer [7]. The mode values (`SH_JMPDOT` through
`SH_JMPSCRIPT`) classify continuations by type. The refactoring direction:

- Ensure every `sh_pushcontext` has a matching `sh_popcontext` on all code
  paths (including error/longjmp paths)
- Make the polarity frame part of `struct checkpt`, so that entering a new
  continuation frame automatically saves polarity state — the μ-binding and
  the polarity shift become a single atomic operation
- Audit all `siglongjmp` calls to verify they unwind to the correct frame

**5. Name the dual error conventions**

The ⊕/⅋ duality [7] between exit-status checking and trap handling is
currently implicit. Making it explicit means:

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
stack and are freed when the enclosing computation frame ends. Making this
correspondence explicit would clarify allocation lifetime guarantees.


## What this buys us

### Bug prevention

The immediate payoff is structural: bugs like 001 and 002 become impossible
rather than merely fixed. If boundary crossings go through a consolidated API,
there's exactly one place to get the save/restore right, instead of 30+.

### Auditability

When someone asks "is this code correct?", the answer can reference structural
properties ("this function operates entirely within a positive context, so it
doesn't need shift discipline") rather than requiring manual trace through
all possible call paths.

### Merge clarity

As the ksh26 branch diverges from dev, the polarity framework gives a
vocabulary for documenting *why* a dev bugfix doesn't apply: "this fix adds a
save/restore for sh.prefix at call site X; in ksh26, this boundary crossing is
handled by sh_enter_computation() so the fix is structurally unnecessary."

### Optimization vocabulary

The sequent calculus gives names to compiler optimizations that are otherwise
ad-hoc. Case-of-case is μ-reduction [7]. Dead code elimination is weakening.
Common subexpression elimination is contraction. These aren't new optimizations
— they're existing optimizations with a structural justification for when they're
safe to apply.

### Incremental applicability

Nothing here requires a big-bang rewrite. Each concrete direction can be applied
independently. The context frame API can be introduced and used at a single call
site, then gradually expanded. The polarity classification of sh_exec cases can
start as comments. The name resolution refactoring can proceed one function at
a time. The theory provides direction; the implementation proceeds at whatever
pace the codebase allows.


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
   Local: `wadler-cbv-dual-cbn-reloaded.pdf` (untracked)

7. David Binder, Marco Tzschentke, Marius Müller, and Klaus Ostermann.
   "Grokking the Sequent Calculus (Functional Pearl)."
   *Proceedings of the ACM on Programming Languages* (ICFP), 2024.
   Source: `~/gist/grokking-the-sequent-calculus.gist.txt`

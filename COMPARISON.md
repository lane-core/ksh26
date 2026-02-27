# ksh26: Feature Vision

What ksh26 should do for users. Interactive features, scripting extensions,
and design principles for a Unix shell in 2026. For how we're getting there:
[REDESIGN.md](REDESIGN.md). For the theoretical analysis informing the
architecture: [SPEC.md](SPEC.md).


## Vision: the Unix shell in 2026

ksh26 is not a compatibility project. It's an answer to the question: what
should a Unix shell look like in 2026?

The modern shell landscape splits into two camps. The **reinventors** (nushell,
elvish, oil) discard POSIX compatibility for clean-slate designs — typed
pipelines, structured data throughout, new syntax. The **accretors** (bash, zsh)
pile features onto the POSIX foundation without rethinking the architecture.

ksh26 takes a third path: **fidelity to POSIX where it matters, refinement
where the standard is silent.** The shell should run any POSIX script correctly.
It should also provide a modern interactive experience — completions with
descriptions, autosuggestions, structured editor extensibility — without
requiring users to learn a new language or abandon their scripts.

This is yash's design sensibility applied to ksh93's robust internals. yash
proved that you can be the most POSIX-compliant shell *and* have thoughtful
extensions. ksh93 has deeper infrastructure (disciplines, compound variables,
the polarity frame) that enables more ambitious extensions while remaining
faithful to the Unix philosophy: text streams, composable tools, no magic.

The proposals in this document are filtered through this lens. Every feature
must either (a) make the shell more correct, or (b) make it more useful
interactively, without compromising either.


## Design constraints (non-negotiable)

These filter every proposal in this document:

1. **Minimalist and modular.** Every new mechanism must justify its existence.
   If ksh93 already has infrastructure that does the job (disciplines,
   compound variables, nameref, continuation stack), use it. No second
   systems.

2. **Performance-preserving.** Nothing on the non-interactive hot path. Editor
   enhancements must not add cost when running scripts. The shell's execution
   engine (`sh_exec`, `sh_fun`, `nv_open`) is off-limits for interactive-only
   changes.

3. **Principled, not accretive.** New features should fall out of architectural
   changes that have holistic benefits. If a feature requires bolting on a
   subsystem that nothing else uses, it doesn't belong in ksh26.

4. **Backward compatible.** Existing ksh93 scripts and KEYBD trap handlers
   must continue to work unchanged.


## Design reference: yash

yash (Yet Another SHell) is instructive because it occupies the design space
ksh26 is aiming for: rigorous POSIX compliance with carefully chosen
extensions. Where zsh and bash accumulate features, yash curates them.

Source: yash manual (https://magicant.github.io/yash/), source code
(https://github.com/magicant/yash-rs — Rust rewrite, original in C).

### Key extensions worth studying

**`errreturn` option.** Like `errexit` (`set -e`) but returns from the
current function instead of exiting the shell. This fixes the fundamental
usability problem with `errexit` — a failed command in a utility function
shouldn't kill the entire script; it should propagate the error to the caller.

```sh
set -o errreturn
f() {
    false        # returns from f with status 1, doesn't exit shell
    echo "never" # not reached
}
f
echo "still here, \$? = $?"  # reached, $? = 1
```

Implementation cost: ~20 lines in `sh_exec()`. The `errexit` path already
checks `sh_isstate(SH_ERREXIT)` — `errreturn` adds an alternative that calls
`siglongjmp` to the function's `sh_pushcontext` frame instead of
`sh_exit()`. The polarity frame guarantees state is correctly unwound.

**`forlocal` option.** Loop variables in `for` loops are automatically local
to the loop body. Prevents a common bug class where loop variables leak into
the enclosing scope.

```sh
set -o forlocal
x=outer
for x in a b c; do :; done
echo "$x"  # "outer" — loop variable didn't leak
```

Implementation cost: ~10 lines in the `TFOR` handler in `sh_exec()`. Push a
scope for the loop variable, pop on loop exit.

**`notifyle` option.** Defer job completion notifications until the next
prompt, rather than interrupting the current line edit. Without this, a
background job completing while you're typing inserts `[1]+ Done ...` into
your input, corrupting the display.

```sh
set -o notifyle
sleep 1 &   # notification appears at next prompt, not mid-keystroke
```

Implementation cost: ~10 lines. Queue notifications in the job table, drain
at `ed_setup()` (prompt time) instead of `job_reap()`.

**Honest POSIX mode.** When `set -o posix` is active, non-POSIX extensions
are genuinely disabled, not cosmetically suppressed. This means ksh26 scripts
that use extensions will fail loudly in POSIX mode rather than silently
behaving differently. This is the right behavior — it makes the boundary
between portable and non-portable code explicit.

**Array-valued hooks.** `PROMPT_COMMAND` is an array — multiple handlers
compose naturally without string-concatenation hacks. Compare bash's single
`PROMPT_COMMAND` string (which requires `;`-separated commands or function
wrapping) to yash's:

```sh
PROMPT_COMMAND=(update_git_status update_title record_history)
```

**Completion descriptions.** Completions have a description field displayed
alongside the candidate. Same UX as fish's `-d` flag. This is the single
most impactful completion UX feature across all shells surveyed.

**Right prompt (`PS1R`).** A right-aligned prompt string. Useful for
displaying metadata (git branch, time, context) without consuming left-side
space. Auto-erased when the cursor reaches it.

**`POST_PROMPT_COMMAND` with `$COMMAND`.** A preexec equivalent — runs after
Enter, before execution. `$COMMAND` contains the command about to be
executed. Cleaner than bash's DEBUG trap or zsh's `preexec` hook.

### What to take from yash

| Feature | Effort | Value | Take? |
|---------|--------|-------|-------|
| `errreturn` | ~20 lines C | Fixes `errexit` footgun | **Yes** |
| `forlocal` | ~10 lines C | Prevents scope leaks | **Yes** |
| `notifyle` | ~10 lines C | Fixes display corruption | **Yes** |
| POSIX mode | ~50 lines C | Correctness boundary | **Yes** |
| Array hooks | 0 (compound vars) | Composable handlers | Already possible |
| Completion descriptions | Part of §4.2 | Fish-level UX | **Yes** (via widget) |
| Right prompt | ~30 lines C | Common feature request | **Yes** |
| `POST_PROMPT_COMMAND` | Part of §4.3 | Clean preexec | **Yes** (via lifecycle events) |


## Part 1: The shell landscape


### 1.1 Editor and keybinding architectures

#### ksh93: KEYBD trap + 4 magic variables

The only extension point. `trap '...' KEYBD` fires on every keystroke via
`keytrap()` (edit.c:1280), which calls `sh_trap()` — a full shell execution
cycle per character. Four variables are set before the trap:

| Variable | Set by C | Read back by C | Purpose |
|----------|----------|----------------|---------|
| `.sh.edchar` | yes | **yes** | Current keystroke bytes |
| `.sh.edtext` | yes | no | Full buffer snapshot |
| `.sh.edcol` | yes | no | Cursor column (0-based) |
| `.sh.edmode` | yes | no | ESC = vi command mode |

Only `.sh.edchar` is read back. The handler can replace it (inject a different
character) or unset it (suppress the character). The other three are
informational.

**Problems identified in practice:**
- `trap '...' KEYBD` silently fails when set during `.kshrc` sourcing via
  a package manager. The trap command succeeds but `trap -p KEYBD` returns
  empty afterward. Root cause not fully diagnosed; appears to be a bug in
  trap slot initialization timing during shell startup.
- `.sh.edtext` is a full buffer copy on every keystroke (linear cost per
  character typed).
- `keytrap()` saves `sh.savexit` and the lex state but not `sh.prefix` or
  `sh.st` — ksh26's polarity frame fixes this for `sh_trap` generally, but
  the `keytrap` function has its own inline dispatch that bypasses `sh_trap`.
- No way to inject multi-character strings. `.sh.edchar` is read back as a
  string, but the editor processes one character per KEYBD invocation.
  Workaround: sane.ksh maintains an inject buffer and drains it one char per
  subsequent KEYBD firing.
- No way to modify `.sh.edtext` (read back is not implemented).
- No widget concept: all key handling is in one monolithic trap handler.

#### bash: readline

bash delegates editing to GNU readline (a separate C library). readline has
its own key dispatch, completion API, and configuration language (inputrc).
Shell-level hooks:

| Mechanism | What it does |
|-----------|-------------|
| `bind -x '"key":function'` | Bind a shell function to a key sequence |
| `complete`, `compgen`, `COMPREPLY` | Programmable completion (see §1.2) |
| `READLINE_LINE`, `READLINE_POINT` | Buffer content and cursor position (read/write) |
| `inputrc` | Key binding configuration file |
| `bind -m keymap` | Switch between vi-insert, vi-command, emacs keymaps |

Strengths: `READLINE_LINE`/`READLINE_POINT` are writable, so `bind -x`
handlers can modify the buffer. Weaknesses: readline is an external
dependency with its own memory management and configuration system; the
interface between bash and readline is a shim layer that requires careful
synchronization.

#### zsh: ZLE widgets

zsh's line editor (ZLE) is built around named **widgets**. Every editor
operation — cursor movement, character insertion, history search, completion —
is a widget. Widgets are either builtin (C) or user-defined (shell function).

```zsh
zle -N my-widget my-function    # register shell function as widget
bindkey '\C-x\C-r' my-widget   # bind key sequence to widget
```

Inside a widget function, these variables are available:

| Variable | Read | Write | Purpose |
|----------|------|-------|---------|
| `$BUFFER` | yes | yes | Full edit buffer |
| `$CURSOR` | yes | yes | Cursor position |
| `$LBUFFER`, `$RBUFFER` | yes | yes | Text left/right of cursor |
| `$WIDGET` | yes | no | Name of current widget |
| `$KEYS` | yes | no | Keys that triggered this widget |
| `$KEYMAP` | yes | no | Current keymap name |
| `$REGION_ACTIVE` | yes | yes | Selection mode |

Strengths: composable — widgets can call other widgets via `zle
other-widget`. Clean separation between key binding and action. Multiple
keymaps (vicmd, viins, emacs, isearch, etc.) with independent bindings.

Weaknesses: the sheer number of builtins (~170 standard widgets) and the
compsys layer on top makes the system hard to learn. Widget functions run
in a special context with restrictions on what shell features are available.

#### fish: event-driven editor

fish's editor is event-driven with named **functions** bound to key sequences.
No separate widget concept — regular fish functions serve as key handlers.

```fish
bind \cr 'history-search-backward'
bind --mode insert \t 'complete'
bind --mode insert --sets-mode default \e ''   # ESC → normal mode
```

Built-in bindings use the same mechanism as user bindings. Mode support
is first-class: `--mode` specifies which mode the binding applies in,
`--sets-mode` specifies the mode to enter after the binding fires.

fish has `commandline` as the read/write interface to the editor:

```fish
commandline -f repaint          # trigger redraw
commandline -b                  # get full buffer
commandline -r "replacement"    # replace buffer
commandline -C                  # get cursor position
commandline -C 5                # set cursor position
```

Strengths: simple, discoverable, no special execution context. Weaknesses:
the `commandline` command is a grab-bag of flags rather than a structured
API.

#### elvish: modal editor with navigation

elvish has a modal editor where different modes (insert, completion,
navigation, history-listing, lastcmd) each have their own key bindings
and rendering. Modes are first-class values:

```elvish
edit:insert:binding[Ctrl-R] = { edit:history:start }
edit:completion:binding[Tab] = { edit:completion:accept }
```

Each mode can define a `start` function that initializes it and a custom
renderer. The editor transitions between modes explicitly.

Strengths: modes as first-class objects with independent binding tables
is clean. Navigation mode (filesystem browser in the editor) is a unique
feature that falls out naturally from the modal architecture.

#### PowerShell: PSReadLine module

PSReadLine is a loadable module (not baked into the engine) with key
handler registration, predictive IntelliSense, and syntax highlighting.

```powershell
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
Set-PSReadLineKeyHandler -Chord Ctrl+r -ScriptBlock {
    # arbitrary PowerShell code
}
```

Notable: `ICommandPredictor` interface with a **20ms deadline** — prediction
plugins that don't respond in time are skipped. This is a pragmatic approach
to keeping interactive responsiveness while allowing extensible prediction.

#### nushell: typed command signatures

nushell's editor (reedline, a Rust library) is separate from the shell.
Commands have typed signatures that declare their parameters:

```nu
def my-command [name: string, --verbose(-v)] { ... }
```

The editor reads these signatures for completion. No separate completion
spec needed — the command definition IS the completion spec.

Strengths: zero-cost completion for user-defined commands. Weaknesses:
requires the language to have typed parameters, which changes the
fundamental character of shell scripting.


### 1.2 Completion architectures

#### ksh93: none

ksh93 has `ed_expand()` (completion.c) which does filename/variable
completion internally. There is no registration mechanism, no programmable
completion, no user-facing API. The KEYBD trap can intercept Tab and do
something else, but it's working against the editor rather than with it.

`ed_expand()` is called from vi mode (`textmod()` handling `'\\'`) and emacs
mode (`escape()` handling `ESC ESC` / `ESC =`). It receives the raw edit
buffer, finds the word under the cursor, and does glob/variable expansion.

The Tab key path:
- emacs: Tab → inject ESC → `escape()` → `ed_expand(ep, ...)` with mode
  `'\\'` (complete) or `'='` (list) depending on `e_tabcount`.
- vi: Tab → inject `'\\'` → `escape:` label → `cntlmode()` → `textmod()`
  → `ed_expand(vp->ed, ...)`.

Both paths use `ed_ungetchar` tricks and stateful counters (`e_tabcount`)
to distinguish first-Tab (complete) from second-Tab (list) from third-Tab
(reset).

#### bash: complete/compgen/COMPREPLY

bash has a three-part programmable completion system:

```bash
complete -F _git_completion git      # register function per command
complete -W "start stop restart" service  # register word list
complete -C "command" git            # register external command
```

Inside a completion function:
- `COMP_WORDS` — array of words on the command line
- `COMP_CWORD` — index of the word under the cursor
- `COMP_LINE`, `COMP_POINT` — raw line and cursor position
- `COMPREPLY` — array to fill with completions (flat strings, no metadata)

`compgen` generates candidates from various sources:
```bash
compgen -f -- "$cur"       # filenames
compgen -d -- "$cur"       # directories
compgen -c -- "$cur"       # commands
compgen -v -- "$cur"       # variables
compgen -W "list" -- "$cur"  # word list
```

Strengths: simple, well-understood, massive ecosystem of completion scripts
(bash-completion project). Weaknesses: `COMPREPLY` is a flat array of strings
with no metadata (no descriptions, no grouping, no type information). The
completion function runs as a regular shell function, which means a full
fork+exec for external completers.

#### zsh: compsys + zstyle

zsh's completion system (compsys) is the most comprehensive and the most
complex. It's built on three layers:

1. **Low-level**: `compadd` builtin adds completions with metadata:
   ```zsh
   compadd -d descriptions -X header -J group -- word1 word2 word3
   ```

2. **Mid-level**: `_arguments`, `_values`, `_describe` — framework functions
   that parse command specs and generate `compadd` calls:
   ```zsh
   _arguments \
       '-v[verbose output]' \
       '-f+[specify file]:file:_files' \
       '*:input file:_files'
   ```

3. **Configuration**: `zstyle` provides context-sensitive configuration:
   ```zsh
   zstyle ':completion:*' menu select                    # menu selection
   zstyle ':completion:*:descriptions' format '%d'       # show descriptions
   zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'  # case-insensitive
   ```

The context string (`:completion:function:completer:command:argument:tag`)
enables different behavior for different commands, arguments, and completion
types.

Strengths: extraordinarily powerful. Can complete anything with any
presentation. Weaknesses: extraordinarily complex. The learning curve is
steep, the implementation is ~30,000 lines of zsh script, and debugging
completion problems requires understanding the full stack. This is the
canonical example of what ksh26 should NOT replicate.

#### fish: `complete` command

fish's completion system is declarative and simple:

```fish
complete -c git -s b -l branch -d "Create or list branches"
complete -c git -n '__fish_git_using_command checkout' -xa '(__fish_git_branches)'
```

Flags:
- `-c command` — which command this completion applies to
- `-s`, `-l`, `-o` — short/long/old-style option being completed
- `-r` — option requires an argument
- `-f` — don't complete filenames (exclusive with `-F`)
- `-d "text"` — human-readable description
- `-n condition` — only offer this completion when condition is true
- `-a args` — the actual completion candidates (can be a command substitution)

Completions have **descriptions** that appear in the menu alongside the
candidate. This is fish's signature UX feature for completion.

The `--wraps` mechanism handles command aliasing:
```fish
complete -c gco -w 'git checkout'   # gco gets git checkout's completions
```

Strengths: 10 flags, covers 90% of use cases. Descriptions are first-class.
Conditional completions via `-n` are powerful without being complex.
Weaknesses: no grouping/categorization of completions. No typed results.

#### elvish: value pipelines for completion

elvish completions are functions that output structured values:

```elvish
set edit:completion:arg-completer[git] = {|@args|
    # return list of candidates
    put (git branch --list | each {|b| str:trim $b ' '})
}
```

Candidates can be maps with metadata:
```elvish
edit:complex-candidate &display="branch (local)" &code-suffix=" " "main"
```

Strengths: completions are regular values (maps, lists) flowing through
pipes. No special syntax. Weaknesses: requires the dual byte/value channel
infrastructure that is specific to elvish.

#### nushell: typed command signatures

nushell commands declare their parameters with types:
```nu
def "git checkout" [
    branch: string@git-branches    # @function provides completions
    --force(-f)                    # flag
] { ... }
```

The `@function` annotation points to a completer function. Completion
options are configured per-command via records:

```nu
$env.config.completions = {
    algorithm: "fuzzy"       # prefix or fuzzy
    case_sensitive: false
    sort: "smart"            # smart, alphabetical
    partial: true            # complete partial paths
    external: {
        enable: true
        completer: {|spans| carapace $spans.0 nushell ...$spans | from json }
    }
}
```

Strengths: completion falls out of the type system with zero additional
work for user-defined commands. Weaknesses: requires a typed parameter
system, which is a fundamental language design choice.

#### External completion frameworks

Several cross-shell completion frameworks exist:

- **carapace** (Go): supports 20+ shells. Outputs completion candidates as
  JSON/TSV with descriptions, groups, and styling. Uses a spec format that
  can be generated from man pages or `--help` output. See §3.2 for detailed
  assessment.
- **bash-completion**: 2000+ completion scripts for bash. De facto standard.
- **zsh-completions**: community-maintained zsh completions.


### 1.3 Autosuggestions

#### fish: inline history suggestions

fish shows the most recent matching history entry as dim "ghost text" after
the cursor. Accept with right-arrow. The algorithm is simple: find the most
recent history entry whose prefix matches the current buffer.

This is fish's most recognized UX feature. It gives the shell a
"predictive" feel without any machine learning or complex infrastructure.

Implementation requirements:
1. History prefix search (backward scan through history file)
2. Ghost text rendering (dim text after cursor, not part of the buffer)
3. Accept mechanism (right-arrow copies ghost text into buffer)

#### zsh: zsh-autosuggestions plugin

A popular plugin that replicates fish's autosuggestion behavior. Implemented
as a ZLE widget that hooks into `zle-line-pre-redraw`. The fact that it can
be implemented as a plugin demonstrates that ZLE's widget architecture is
sufficient — no C changes needed.

#### PowerShell: predictive IntelliSense

PSReadLine's prediction system is more sophisticated:
- `ICommandPredictor` interface — plugins register prediction providers
- **20ms deadline** — predictions that don't arrive in time are dropped
- History-based and plugin-based sources combined
- List view (dropdown) in addition to inline ghost text

The deadline mechanism is notable: it guarantees interactive responsiveness
regardless of how expensive the prediction logic is.

#### ksh93 history infrastructure

ksh93 already has history search infrastructure in `history.c`:
- `hist_locate()` — locate a history entry by line number
- `hist_word()` — extract words from a history entry
- `hist_copy()` — copy history entries
- History file is memory-mapped for fast access
- The vi `ESC /` and emacs `Ctrl-R` commands already do history search

What's missing: (1) a way to display ghost text, (2) a way to trigger
search after each character (widget system), (3) accept-on-right-arrow.


### 1.4 Syntax highlighting

#### fish: native

fish highlights the command line as you type. Valid commands are one color,
invalid commands another, strings are quoted, etc. This is built into fish's
editor, not a plugin.

Implementation requires:
1. Tokenization of the current buffer on every keystroke
2. A token→color mapping
3. Rendering with ANSI escape codes interleaved with the buffer text

#### zsh: zsh-syntax-highlighting (plugin)

A ZLE widget that hooks into redraw. Uses zsh's own lexer (available via
the `lex` module) to tokenize the buffer and apply ANSI colors. Popular
but noticeably slows down editing on long lines.

#### bash: no native support

No built-in mechanism. Third-party attempts (ble.sh) exist but are fragile.

#### Relevance to ksh93/ksh26

ksh93 has a full lexer (`lex.c`) that could tokenize the edit buffer, but
the editor's display path (`ed_putchar`, `ed_flush`) has no concept of
styled output. Adding color support to the display path is moderate work.

Syntax highlighting is cosmetic — high user appeal but no architectural
payoff. It should NOT drive architecture decisions. However, if a widget
system exists (§4.1), syntax highlighting becomes a widget function that
can be added later without C changes to the display layer (the widget
returns ANSI-coded text and the display path passes it through).


### 1.5 Prompt systems

#### ksh93: PS1 expansion

Prompts are expanded via `sh_mactrim()`. The PS1 string goes through full
parameter expansion, command substitution, and arithmetic expansion.

No built-in `precmd` or `preexec` hooks. Workarounds:
- PS1 `.get` discipline (sane.ksh): fires when PS1 is read for display.
  Captures `$?` before hook machinery clobbers it.
- DEBUG trap (sane.ksh): fires before each command. Used for preexec.

#### bash: PROMPT_COMMAND

```bash
PROMPT_COMMAND='update_prompt'   # runs before each prompt
```

Simple and effective. Also supports `PS0` (printed after input, before
execution — a preexec equivalent).

#### zsh: precmd/preexec hooks

```zsh
precmd() { ... }                  # before prompt
preexec() { ... }                 # after input, before execution
add-zsh-hook precmd my_function   # composable registration
```

Multiple functions can be registered. `add-zsh-hook` is the standard
composition mechanism.

#### fish: event system

```fish
function my_prompt --on-event fish_prompt
    # runs before each prompt
end
function my_preexec --on-event fish_preexec
    # runs after input, before execution
end
```

fish's event system is general-purpose (not prompt-specific).

#### Relevance

ksh93 has no native hooks. The discipline mechanism (`.get` on PS1) is
a viable workaround but fragile. A small set of editor lifecycle events
(precmd, preexec, mode-change) at the C level would eliminate several
classes of workaround.


### 1.6 Vi mode quality

#### ksh93

ksh93's vi mode is the original. `ed_viread` (vi.c) implements a
two-loop architecture: `getline()` for insert mode, `cntlmode()` for
command mode. Most vi motions are supported. `ESC /` does history
search.

Missing relative to modern vi-mode implementations:
- No visual indicator of current mode (insert vs command)
- No text objects (`ci"`, `da(` etc.)
- No incremental search (search-as-you-type)
- No surround operations

#### zsh: vi-mode with text objects

zsh supports `ci"`, `ca(`, and similar text objects via `select-in-*` and
`select-a-*` widgets. Visual mode (`v` in vicmd) with character/line
selection. Mode indicator via `zle-keymap-select` hook.

#### fish: vi mode

fish's vi mode is relatively complete. Mode indicator changes the cursor
shape (block vs bar). `--sets-mode` in key bindings makes mode transitions
explicit.

#### bash: vi mode via readline

readline's vi mode. `set show-mode-in-prompt on` shows a mode indicator.
Otherwise similar to ksh93's in capability.

#### Relevance

Vi mode enhancements (text objects, mode indicator, surround) are
incrementally addable via a widget system. Mode change detection is
already available in ksh93 via `.sh.edmode`. If an editor event system
exists (§4.3), mode indicator falls out as a `mode-change` event handler
that adjusts the cursor shape via terminal escape codes.


### 1.7 Directory navigation

#### fish: `cdh` and dirprev/dirnext

fish maintains a directory history stack. `cdh` shows recent directories.
`Alt-Left` / `Alt-Right` navigate backward/forward.

#### zsh: `AUTO_CD`, directory stack

`setopt AUTO_CD` — typing a directory name without `cd` changes to it.
`pushd`/`popd`/`dirs` for directory stack. `hash -d name=path` for named
directories.

#### zoxide

Cross-shell "smart cd" (z, zi). Learns directory frecency (frequency +
recency). Available for all shells. Already integrated in sane.ksh.

#### Relevance

Directory navigation is a plugin-level concern, not a shell architecture
concern. sane.ksh already handles this well. No ksh26 changes needed.


### 1.8 History features

#### bash: `!` history expansion

`!!`, `!$`, `!:2`, `^old^new^` — csh-style history expansion. Controlled
by `histexpand` option.

ksh93 has this (`SHOPT_HISTEXPAND`, implemented in `hexpand.c`).

#### fish: history search with substring matching

`Ctrl-R` opens an interactive history search that matches anywhere in the
command (not just prefix). Combined with autosuggestions, this gives two
complementary history access patterns.

#### atuin/mcfly: enhanced history

Cross-shell history tools that store history in SQLite with context
metadata (directory, exit code, duration, host). TUI search interface.

#### Relevance

ksh93's history infrastructure is solid. The memory-mapped history file
is efficient. Enhanced history search (substring, fuzzy) could be a widget
function. SQLite-based history is a plugin concern, not a shell concern.


### 1.9 Unique modern shell ideas

These are notable innovations that may or may not fit ksh26's philosophy.

#### elvish: value pipelines

Pipes carry both byte streams and structured values simultaneously. Two
channels: byte (traditional) and value (Go-style channel of typed objects).

```elvish
put foo bar | each {|x| echo $x }   # value pipeline
```

**Assessment:** Fundamental language change. Not compatible with ksh93's
architecture without an impractical rewrite. The polarity frame infrastructure
doesn't help here — this requires a different execution model.

#### nushell: structured data throughout

Everything is a table. `ls` returns a table of file records, not text. Pipes
transform tables, not byte streams.

```nu
ls | where size > 10mb | sort-by modified
```

**Assessment:** Elegant but incompatible with Unix pipeline philosophy.
ksh93's compound variables provide *some* structured data capability
within a traditional framework.

#### PowerShell: object pipeline

Similar to nushell but with .NET objects. `Get-Process | Where-Object CPU
-gt 10`. Objects have properties and methods.

**Assessment:** Same incompatibility as nushell. Different paradigm.

#### ion: sigil distinction

ion uses `$` for strings, `@` for arrays:

```ion
let array = [@split(" " $string)]
echo @array[0..3]
```

**Assessment:** Breaking change to shell syntax for marginal clarity gain.
ksh93 already distinguishes scalars from arrays via `typeset -a`.

#### murex: MIME-aware pipes

murex's arrow pipe (`->`) filters output based on MIME type. The shell
tracks the data type of each command's output.

**Assessment:** Interesting but niche. Adds complexity for specialized use.

#### oils/ysh: exterior-first design

oils treats bash as an exterior language that can be gradually upgraded.
ysh expressions use `()` and methods, avoiding the ambiguity of shell syntax:

```ysh
var x = "hello" ++ " world"
if (len(x) > 5) { echo "long" }
```

**Assessment:** The gradual upgrade philosophy is compatible with ksh26's
approach. oils demonstrates that a shell can add expression-level
improvements without breaking backward compatibility. However, ksh93
already has `(( ))` for arithmetic and `[[ ]]` for conditionals, which
cover much of the same ground.


## Part 2: Visual rendering architecture

Modern shells have converged on a rendering architecture that enables
inline UI composition — completions with descriptions, autosuggestion
ghost text, syntax highlighting, and multi-line prompts — all on the main
screen buffer without alternate-screen takeover. Understanding how they
do it informs what ksh26 needs to build.


### 2.1 How modern shells render

#### elvish: inline widget composition

elvish's terminal rendering (documented in `pkg/cli/term/` in the Go source,
https://github.com/elves/elvish) is the cleanest example of the pattern.

The key abstraction is a **Buffer**: a 2D grid of Cells (each Cell = one
rune + a Style) plus a cursor position. The editor is composed of
**widgets** — each widget produces its own Buffer, and Buffers are combined
via two composition operators:

- `ExtendDown(other)`: vertical stacking. Appends `other`'s rows below the
  current buffer. Used for: prompt line + completion pager, input + status
  bar.
- `ExtendRight(other)`: horizontal concatenation. Appends `other`'s content
  to the right of the current buffer's last line. Used for: prompt string +
  input text.

The composed Buffer represents the entire editor surface. Rendering to the
terminal uses **delta updates**: compare the new Buffer against the previous
one, emit only the differences.

The delta renderer's cursor movement strategy is notable — it uses only
**relative** movements:
- CR (carriage return) to reach column 0
- cursor-down to reach the target row
- cursor-right to reach the target column

No absolute positioning (no `CSI row;col H`). This avoids depending on
terminal state (scroll region, origin mode) and works correctly when the
terminal has scrolled.

The rendering loop:
1. Each widget produces a Buffer
2. Buffers are composed into a single frame Buffer
3. Frame Buffer is diffed against the previous frame
4. Delta operations (cursor moves + cell writes) are emitted
5. Previous frame is replaced with current frame

#### fish: delta rendering with highlight pipeline

fish uses the same delta rendering pattern (source: `src/screen.cpp`,
https://github.com/fish-shell/fish-shell).

The highlight pipeline is fish-specific and worth noting:
1. The input buffer is tokenized (lexer pass)
2. Each token gets a highlight role (command, parameter, string, error, etc.)
3. A **background thread** validates commands (checks PATH for existence) and
   updates highlights asynchronously — the prompt stays responsive even if
   command validation is slow
4. Highlighted tokens are rendered as styled text

The completion pager uses a grid layout: candidates are arranged in columns
with descriptions right-aligned. The pager appears below the input line as
an inline widget (same ExtendDown composition pattern as elvish).

#### nushell (reedline): prompt-oriented rendering

reedline (https://github.com/nushell/reedline) uses a simpler model than
elvish: it tracks prompt lines and repaints them as needed. Less general
than elvish's Buffer composition but adequate for nushell's needs.

### 2.2 Terminal capability matrix

All three shells above rely on a surprisingly small set of terminal
capabilities. Surveying which sequences they actually use:

| Sequence | ANSI name | Used for |
|----------|-----------|----------|
| `\r` | CR | Move cursor to column 0 |
| `\033[A` | CUU | Cursor up (relative) |
| `\033[B` | CUD | Cursor down (relative) |
| `\033[C` | CUF | Cursor right (relative) |
| `\033[K` | EL | Clear to end of line |
| `\033[J` | ED | Clear to end of screen |
| `\033[?25h/l` | DECTCEM | Show/hide cursor (during repaint) |
| `\033[...m` | SGR | Colors and attributes (bold, dim, underline, etc.) |

That's 8 sequences. Every terminal emulator shipped in the last 20 years
supports all of them. No terminfo/termcap lookup needed for these — they're
de facto universal.

ksh93's editor currently uses:
- CR, cursor-right, and clear-to-EOL (basic line editing)
- `ed_putchar` / `ed_flush` for output (no SGR, no cursor up/down)

The gap: ksh93 can edit single lines. It cannot compose multi-line regions
(completion pager, status bar) or emit styled text (ghost text,
highlighting). The 8 sequences above are sufficient to close this gap.

### 2.3 Implications for ksh26

ksh26 doesn't need elvish's full Buffer abstraction on day one. The path
is incremental:

**Phase 1: SGR passthrough.** The display path (`ed_putchar`/`ed_flush`)
passes through ANSI escape sequences instead of treating them as printable
characters. This alone enables syntax highlighting as a widget that returns
pre-colored text. No new data structures.

**Phase 2: Ghost text (§4.4).** A single `e_ghost` string rendered in dim
after the cursor. Uses cursor-right and CR to restore position. Enables
autosuggestions. ~50-100 lines.

**Phase 3: Addon region.** A region below the input line for completion
menus, status information, etc. Uses cursor-down, clear-to-EOL,
clear-to-EOS. The region is cleared and redrawn on each update. ~150-200
lines. This is a simplified version of elvish's ExtendDown.

**Phase 4: Delta rendering.** Full old-vs-new buffer comparison for
flicker-free updates. Only needed if Phase 3's clear-and-redraw produces
visible flicker, which depends on terminal speed and content size. May
never be needed.

Each phase is independently useful and doesn't require the next.


## Part 3: External tool integration

Interactive shells increasingly delegate to external tools — completion
generators, fuzzy finders, history managers. ksh26 needs a clear model for
how these tools interact with the editor.


### 3.1 Integration taxonomy

Three patterns cover all cases:

| Pattern | Characteristics | Examples |
|---------|----------------|----------|
| **Fork-per-use** | Shell forks tool, reads stdout, tool exits | carapace (~5ms), compgen, custom scripts |
| **Foreground takeover** | Tool takes over terminal, shell suspends | fzf, atuin TUI, less, vim |
| **Persistent channel** | Long-lived process, shell talks over pipe | Hypothetical completion daemon, LSP |

Each pattern has different requirements from the shell:

- **Fork-per-use**: needs `$()` command substitution (already works) or a
  mechanism to run a command and capture structured output. Widget functions
  can already do this.
- **Foreground takeover**: needs the shell to (1) save editor state, (2)
  restore terminal modes, (3) wait for the tool to exit, (4) read the tool's
  output, (5) restore editor state with new content. sane.ksh does this now
  for fzf via KEYBD trap, but the result injection is char-at-a-time.
- **Persistent channel**: needs coprocess or named pipe. ksh93 has
  coprocesses. See §3.4.


### 3.2 carapace

carapace (https://github.com/carapace-sh/carapace-bin) is a cross-shell
completion framework written in Go. It provides completions for 1600+
commands via spec files.

#### Architecture

carapace is a **per-invocation binary**. Each Tab press forks a new
`carapace` process with the command line as arguments:

```sh
carapace git bash 'git' 'check'
```

Startup time is ~5ms (Go binary, no interpreter). This is fast enough for
interactive use — the user won't perceive the delay between pressing Tab and
seeing results.

carapace has no native ksh support. It supports: bash, elvish, fish,
nushell, oil, powershell, tcsh, xonsh, zsh, and several others.

#### Output formats

**Bash format** (simplest to parse):
```
nospace\x01checkout
nospace\x01cherry-pick
nospace\x01clean
```

Each line is `[directive]\x01[value]`. Directives: `nospace` (don't append
space), `filenames` (treat as filenames), `default` (normal completion).

**JSON export format** (richest):
```json
[{
    "value": "checkout",
    "display": "checkout",
    "description": "Switch branches or restore working tree files",
    "style": "blue",
    "tag": "commands"
}]
```

Fields: `value` (insertion text), `display` (menu text), `description`
(help text), `style` (ANSI color name), `tag` (grouping label).

**Bridge mode**: carapace can also wrap existing bash-completion scripts,
providing structured output from legacy completions:

```sh
carapace --bridge git/bash   # uses bash-completion's _git
```

#### ksh26 integration path

The bash output format is the simplest integration path — it requires no
JSON parser:

```ksh
function _carapace_complete {
    typeset -C -a .sh.value
    typeset line IFS=$'\x01'
    carapace "${.sh.editor.word}" bash "${.sh.editor.line}" |
    while read -r directive value; do
        .sh.value+=( ( value="$value" ) )
    done
}
complete -c '*' -f _carapace_complete   # fallback completer for all commands
```

For the JSON format (richer, with descriptions), ksh93's compound variable
infrastructure could parse it — but a small C helper or `jq` bridge would
be more pragmatic. The bash format covers 90% of the value.

carapace does NOT need a coprocess or persistent connection. Fork-per-use
is the right pattern: ~5ms per invocation, no state to manage, no daemon
to start/stop.


### 3.3 fzf

fzf (https://github.com/junegunn/fzf) is a general-purpose fuzzy finder.
It's the de facto standard for interactive selection in terminal
applications.

#### 4-channel I/O architecture

fzf uses four I/O channels simultaneously:

| Channel | Direction | Purpose |
|---------|-----------|---------|
| stdin | candidates → fzf | List of items to filter |
| stdout | fzf → shell | Selected item(s) |
| stderr | fzf → terminal | TUI rendering (the fuzzy finder interface) |
| /dev/tty | user → fzf | Keyboard input for the TUI |

This is a **foreground takeover** tool. fzf needs the terminal for its TUI.
The shell must suspend its own editing, hand control to fzf, then resume
editing with fzf's output.

#### Current sane.ksh integration

sane.ksh already integrates fzf for three widgets (`sane.ksh/lib/fzf.ksh`):
- `_sane_fzf_history` (Ctrl-R): history search
- `_sane_fzf_file` (Ctrl-T): file picker
- `_sane_fzf_cd` (Alt-C): directory picker

The integration pattern:
1. KEYBD trap detects the key sequence
2. Handler calls fzf via `$()` command substitution — the subshell gives fzf
   direct terminal access while capturing stdout
3. The result is placed in sane.ksh's inject buffer
4. The KEYBD trap drains the inject buffer one character per subsequent
   keystroke

This works but has three limitations:
- **Char-at-a-time injection**: the result is fed back one character per
  KEYBD firing. For a 50-character path, that's 50 KEYBD trap invocations.
- **Read-only buffer**: the handler can't modify `.sh.edtext` — it can only
  inject characters at the cursor position.
- **Read-only cursor**: the handler can't move the cursor — it can only
  read `.sh.edcol`.

#### What the widget system solves

With the widget system (§4.1), all three limitations disappear:
- `.sh.editor.line` is writable — replace the entire buffer at once
- `.sh.editor.col` is writable — set the cursor position
- `.sh.value` can return a multi-character string — no char-at-a-time drain

The fzf integration becomes:

```ksh
function .sh.editor.fzf_history {
    typeset result
    result=$(fc -l -n 1 | fzf --tac --no-sort)
    .sh.editor.line="$result"
    .sh.editor.col=${#result}
}
```

Three lines, no inject buffer, no drain loop.


### 3.4 Coprocess internals

ksh93 has a coprocess mechanism (`|&`, `<&p`, `>&p`) that creates a
persistent bidirectional pipe to a child process.

#### ksh93's single-slot coprocess

The implementation (xec.c, io.c) maintains a **single coprocess slot**:

| Field | Purpose |
|-------|---------|
| `sh.cpipe[2]` | Pipe fds for shell→coproc and coproc→shell |
| `sh.coutpipe` | Output fd from coproc |
| `sh.cpid` | PID of the coprocess |

`coproc_init()` (xec.c:3383) sets up the pipes. Only one coprocess can
be active at a time. Starting a new one closes the previous. The
`exec N>&p M<&p` trick moves the coproc fds to named fds, freeing the
slot for a new coprocess — this is the standard pattern for multiplexing.

#### Assessment for interactive tools

**carapace**: coprocess is the wrong pattern. carapace is per-invocation
(fork, run, exit). No state to maintain between invocations. `$()` is
sufficient and simpler.

**fzf**: coprocess is impossible. fzf needs foreground terminal access for
its TUI. A coprocess runs in the background with no terminal. `$()` is the
correct pattern — it gives fzf a subshell with terminal access.

**Hypothetical completion daemon**: a long-running process that maintains
an index of completions and responds to queries. This IS a coprocess use
case. But no such tool exists today in the shell ecosystem, and building
one is outside ksh26's scope.

**Verdict**: don't extend or modify the coprocess infrastructure for
interactive features. `$()` command substitution handles carapace and fzf.
If a persistent tool emerges, the existing coprocess mechanism is adequate.


## Part 4: Architectural proposals

These proposals are filtered through the design constraints. Each one
either (a) enables multiple features from a single mechanism, or (b)
fixes an existing architectural problem while unlocking new capability.


### 4.1 Editor widget system via `.sh.editor` discipline namespace

**Replaces:** The KEYBD trap as the sole extension point
**Enables:** Programmable completion, autosuggestions, mode indicators, and
any future interactive feature — all from one mechanism
**Leverages:** Discipline functions, compound variables, polarity frames

#### The problem

The KEYBD trap is ksh93's only editor extension mechanism, and it has
fundamental limitations:

1. It fires on every keystroke — one `sh_trap()` call per character.
2. Only `.sh.edchar` is read back — no buffer modification.
3. It silently fails when set during `.kshrc` sourcing (observed bug).
4. Multi-character injection requires an external buffer and drain loop.
5. No concept of named operations — one monolithic trap handler does
   everything, dispatching internally on `.sh.edchar` values.

These limitations forced sane.ksh to build an entire keybinding framework
on top of the KEYBD trap (dispatch tables, inject buffer, sequence
accumulator, prefix cache). The framework works but it's a shell-script
reimplementation of functionality that belongs in the editor.

#### The proposal

Extend `.sh.*` with a compound namespace `.sh.editor` backed by a C-level
discipline (same pattern as `.sh.stats.*` in init.c). Editor operations
become **widgets** — named shell functions dispatched by the C editor core
at defined points.

```ksh
# A completion widget
function .sh.editor.complete {
    # Read state:
    #   .sh.editor.line     current buffer content
    #   .sh.editor.col      cursor position
    #   .sh.editor.word     word under cursor (C-computed by find_begin)
    #
    # Write result via .sh.value — compound array of completions:
    typeset -C -a .sh.value=(
        ( value=checkout  description="Switch branches" )
        ( value=cherry-pick description="Apply a commit" )
    )
}

# An autosuggestion widget
function .sh.editor.suggest {
    # Search history for prefix match
    typeset match
    match=$(fc -l -1 -n | grep -m1 "^${.sh.editor.line}")
    .sh.value="${match#${.sh.editor.line}}"  # ghost text to display
}
```

The C editor core calls widgets at defined points:
- **complete**: Tab press (replaces the `ed_expand()` path)
- **suggest**: after each accepted character (new)
- **accept**: Enter pressed, line finalized (new)
- **mode-change**: vi mode transition (new, replaces `.sh.edmode` polling)
- **precmd**: before prompt display (new, replaces PS1 `.get` hack)
- **preexec**: after Enter, before execution (new, replaces DEBUG trap hack)

#### Implementation path

The `.sh.stats.*` namespace (init.c:~1594) is the template. The work:

1. **variables.c** — add `.sh.editor` and children (`.sh.editor.line`,
   `.sh.editor.col`, `.sh.editor.word`, `.sh.editor.mode`) to
   `shtab_variables[]`. Add `#define` index macros in `variables.h`.

2. **init.c** — write a `createf` discipline function for `.sh.editor`
   that maps dot-path names to internal nodes. Wire it up in `nv_init()`.

3. **edit.c** — add widget dispatch function that:
   - Sets `.sh.editor.line`, `.sh.editor.col`, etc.
   - Calls `sh_fun()` on the registered widget function
   - Reads back `.sh.value` for the result
   - The `sh_fun()` call goes through the polarity frame (already in place),
     giving each widget invocation correct state isolation for free.

4. **vi.c / emacs.c** — at Tab press, check for `.sh.editor.complete` widget.
   If present, call widget dispatch instead of `ed_expand()`. If absent,
   fall back to `ed_expand()` (backward compat). Similarly for other events.

5. **Retain KEYBD trap** — the trap continues to work exactly as before.
   Widgets are the primary extension path; the KEYBD trap is the low-level
   escape hatch.

#### Why this is a win-win

- **Fixes the KEYBD trap bug**: widgets are dispatched by `sh_fun()` at
  well-defined points in the editor loop, not via `sh.st.trap[SH_KEYTRAP]`
  which has the initialization timing problem.
- **Enables completion**: the `complete` widget replaces `ed_expand()`'s
  monolithic code with a programmable path.
- **Enables autosuggestions**: the `suggest` widget fires after each
  accepted character. fish's signature feature becomes a shell function.
- **Enables mode indicator**: the `mode-change` event fires on vi mode
  transitions. The handler emits cursor-shape escape codes.
- **Eliminates sane.ksh's workarounds**: the dispatch tables, inject
  buffer, sequence accumulator, and prefix cache become unnecessary —
  the C editor handles key dispatch and sequence accumulation natively.
- **Uses existing infrastructure**: disciplines, compound variables,
  `sh_fun()`, polarity frames — no new mechanisms invented.
- **Preserves the KEYBD trap**: backward compatible with existing handlers.

#### Polarity frame connection

Each widget invocation is a shift — the editor (value mode: building a
string) crosses into computation mode (running the widget function) and
back. This is exactly the `sh_polarity_enter`/`sh_polarity_leave` boundary
that ksh26 has already implemented.

The current `keytrap()` in edit.c:1280 does a partial shift: it saves
`sh.savexit` and the lex state. But it does NOT save `sh.prefix` or
`sh.st`. Widget dispatch via `sh_fun()` gets the full polarity frame,
making widget execution correct by construction.

In the duploid framework (SPEC.md §The semantics), widget invocation is
a thunkable map — the editor state is saved, the widget runs (possibly
involving arbitrary shell operations), and the editor state is restored.
The thunkability (purity) is enforced by the polarity frame. This means
widgets can safely call `nv_open`, run command substitutions, or do anything
else that a normal shell function can do, without risk of corrupting the
editor's state.

#### Cost assessment

- **C work**: moderate. ~200-300 lines for the discipline namespace, ~100
  lines for widget dispatch, ~50 lines for dispatch calls in vi.c/emacs.c.
- **Risk**: low. The widget system is additive — no existing code paths
  change unless a widget is registered. `ed_expand()` continues to work
  as the default when no `complete` widget exists.
- **Performance**: widget dispatch has the same cost as a discipline
  function call (~1 `sh_fun()` invocation per event). Events fire at
  defined points (Tab, Enter, mode change), not on every keystroke.
  Autosuggestions fire per character but are optional.


### 4.2 Structured completion results

**Replaces:** flat string completion (ed_expand returns a count + modifies
the buffer in place)
**Enables:** descriptions, grouping, filtering, external completer integration
**Leverages:** compound variables (ksh93's existing type system)

#### The problem

`ed_expand()` (completion.c) returns completions as flat strings inserted
into the buffer. When listing completions (`'='` mode), they're displayed
in columns with no metadata. There's no way to:
- Show a description alongside each candidate
- Group completions by category
- Filter completions by type
- Integrate external completers that return structured data

bash has the same limitation (COMPREPLY is a flat array). zsh solved it
with compsys (30,000 lines of zsh script). fish solved it with the `-d`
flag on `complete`.

#### The proposal

Completion results are compound variables. ksh93 already has compound
variables — this is using existing infrastructure:

```ksh
# In a completion widget function:
typeset -C -a .sh.value=(
    ( value=checkout    description="Switch branches"     group=commands )
    ( value=cherry-pick description="Apply a commit"      group=commands )
    ( value=clean       description="Remove untracked"    group=commands )
    ( value=branch      description="List/create branches" group=commands )
)
```

The C display layer reads `.value` for insertion and `.description` for
display. Minimal required fields:

| Field | Type | Required | Purpose |
|-------|------|----------|---------|
| `value` | string | yes | Text to insert on selection |
| `description` | string | no | Shown alongside the candidate |
| `group` | string | no | Category header in menu |
| `display` | string | no | Override display text (vs value) |

The display layer in `ed_expand()` needs ~50-100 lines of changes to render
descriptions alongside candidates. The column layout already exists; it just
needs a second column.

#### Why this is a win-win

- **No new language features**: compound variables already exist, serialize,
  and work with disciplines.
- **carapace integration**: parse JSON/TSV output from carapace into a
  compound array. The shell side is ~10 lines of ksh.
- **Descriptions in menu**: the display layer reads `.description` fields.
  This is fish's signature completion UX.
- **Grouping**: candidates organized by category. Minimal display logic.
- **Backward compatible**: if `.sh.value` is a flat string (not a compound
  array), the completion path falls back to inserting it directly.

#### Cost assessment

- **C work**: small. ~100 lines to read compound array entries in the
  display path. The compound variable infrastructure does the heavy lifting.
- **Risk**: minimal. Additive change to the display path.


### 4.3 Editor lifecycle events

**Replaces:** PS1 `.get` discipline hack (precmd), DEBUG trap hack (preexec),
KEYBD trap `.sh.edmode` polling (mode change)
**Enables:** clean prompt hooks, preexec hooks, mode indicator
**Leverages:** discipline functions on `.sh.editor.*` sub-nodes

#### The problem

sane.ksh uses three separate hacks for editor lifecycle events:

1. **precmd** (before prompt): A `.get` discipline on a variable spliced
   into PS1. The discipline fires when PS1 is expanded. It must capture
   `$?` before any hook machinery clobbers it.

2. **preexec** (after input, before execution): The DEBUG trap, composed
   with any existing DEBUG trap handler via `eval` of `trap -p DEBUG`
   output. Fragile — the composition must handle single-quoted action
   strings, and DEBUG fires on every command, not just interactive input.

3. **mode-change** (vi mode transition): The KEYBD trap handler compares
   `.sh.edmode` against a cached previous value on every keystroke. Pure
   polling overhead.

These workarounds exist because ksh93 has no editor lifecycle hooks. bash
has `PROMPT_COMMAND`. zsh has `precmd`/`preexec`/`zle-keymap-select`. fish
has `fish_prompt`/`fish_preexec` events.

#### The proposal

A small set of well-defined events, implemented as discipline-attachable
nodes under `.sh.editor`:

| Event | Fires when | Replaces |
|-------|-----------|----------|
| `.sh.editor.precmd` | Before prompt display | PS1 `.get` hack |
| `.sh.editor.preexec` | After Enter, before execution | DEBUG trap hack |
| `.sh.editor.mode` | Vi mode transitions | KEYBD mode polling |

Registration via discipline:

```ksh
function .sh.editor.precmd.set {
    # ${.sh.value} contains the previous command's exit status
    _update_git_status "${.sh.value}"
}
```

Or, if a registration builtin is preferred:

```ksh
widget -e precmd _my_precmd_handler
```

The C implementation is ~30 lines total: call `sh_fun()` at the right
points in `ed_viread`/`ed_emacsread` (for mode change), in `ed_setup()`
(for precmd, where the prompt is computed), and in the line-accept path
(for preexec).

#### Why this is a win-win

- **Eliminates three hacks** with one mechanism.
- **Correct `$?` propagation**: the C layer captures exit status BEFORE
  any shell code runs, passes it as `.sh.value` to the precmd handler.
  No race condition, no ordering dependency.
- **No per-keystroke overhead**: events fire at defined lifecycle points,
  not on every character.
- **Composable**: multiple handlers via discipline chain.

#### Cost assessment

- **C work**: minimal. ~30 lines of `sh_fun()` calls at defined points.
- **Risk**: very low. Additive, no existing behavior changes.
- **Shares namespace with §4.1**: if the widget system exists, events are
  just widgets that fire on lifecycle transitions rather than key presses.


### 4.4 Ghost text rendering

**Replaces:** nothing (new capability)
**Enables:** autosuggestions, completion preview, inline documentation
**Leverages:** terminal escape codes (SGR dim attribute)

#### The problem

Autosuggestions (§1.3) and completion preview require displaying text that
is not part of the edit buffer. The editor's current display path
(`ed_putchar`, `ed_flush`, `ed_setcursor`) renders exactly the buffer
content with no concept of styled or ephemeral text.

#### The proposal

Add ghost text support to the editor display path:

1. A new `Edit_t` field `e_ghost` (pointer to a string, or NULL).
2. When `e_ghost` is non-NULL, the display path renders it after the
   cursor position in dim (SGR attribute 2) with the cursor restored to
   its pre-ghost position.
3. Ghost text is cleared on any buffer modification.
4. A widget (or the suggest mechanism) sets `e_ghost`.

The rendering sequence:

```
<buffer text up to cursor>           normal
<ghost text>                         dim (SGR 2)
<buffer text after cursor>           normal
<move cursor back to real position>  CSI sequences
```

This is ~50-100 lines in the display path. The dim attribute (SGR 2) is
supported by every modern terminal.

#### Why this is a win-win

- **Enables autosuggestions**: the `suggest` widget sets `e_ghost` to the
  suggested suffix. Accept with right-arrow copies ghost into buffer.
- **Enables completion preview**: show the top completion candidate inline
  before the user presses Tab.
- **Reusable**: any widget can set ghost text for any purpose.
- **Stepping stone**: ghost text rendering introduces SGR handling to the
  display path, which is prerequisite for syntax highlighting and the
  inline rendering engine (§4.7).

#### Cost assessment

- **C work**: small. ~50-100 lines in the display path.
- **Risk**: low. Ghost text is purely additive display-layer work.
- **Terminal compatibility**: SGR dim is universally supported. Terminals
  that don't support it simply show the text in normal weight.


### 4.5 `complete` builtin

**Replaces:** nothing (no completion registration exists)
**Enables:** per-command completion specs, external completer integration
**Leverages:** the widget system (§4.1) for dispatch

#### The proposal

A registration builtin that maps command names to completion functions:

```ksh
# Register a function as the completer for a command
complete -c git -f _git_completions
complete -c docker -f _docker_completions

# Simple word-list completion (no function needed)
complete -c service -w "start stop restart status"

# External completer (carapace, etc.)
complete -c '*' -x 'carapace $_command bash'
```

This is closer to fish's `complete` than bash's. Key design choices:

1. **Function-based, not flag-based.** bash's `complete` has ~25 flags for
   different completion sources (-f files, -d dirs, -c commands, -v vars,
   -A arrayvar, etc.). This is the wrong abstraction level — it pushes
   source knowledge into the builtin. Instead, provide a function callback
   and let the function decide how to generate candidates.

2. **Dispatch via widget.** When the user presses Tab, the C editor checks
   the `complete` builtin's registry for the current command. If found,
   calls the registered function as a widget. If not found, falls back to
   `ed_expand()`.

3. **External completer fallback.** The `-x` flag registers a command
   template (like carapace) as the completer for commands that don't have
   a specific registration. `$_command` is substituted with the current
   command name.

#### Implementation

A new builtin (`b_complete` in bltins/) that maintains an associative array
mapping command names to function names. ~100-150 lines of C.

Dispatch logic in the `complete` widget:

```
Tab pressed
  → extract command name from current buffer
  → look up in complete registry
  → if found: call registered function, display results
  → if not found and external completer registered: call external
  → if nothing: fall back to ed_expand()
```

#### Cost assessment

- **C work**: small. ~150 lines for the builtin, ~30 lines for dispatch.
- **Depends on**: §4.1 (widget system) or a simpler hook at the Tab
  press point in vi.c/emacs.c.


### 4.6 Incremental history search widget

**Replaces:** vi `ESC /` and emacs `Ctrl-R` (modal, non-incremental)
**Enables:** search-as-you-type history navigation
**Leverages:** widgets, existing history infrastructure

This is a pure shell-function widget that uses existing history
infrastructure (`fc`, `hist_locate`). Once the widget system exists,
this requires zero C changes:

```ksh
function .sh.editor.history_search {
    # .sh.editor.line = current search term
    # Use fc -l to search history
    # Set .sh.value to the matching entry
    # The editor replaces the buffer with the result
}
```

This is listed not as a C proposal but as evidence that the widget system
(§4.1) enables useful features at the shell-script level without further
C work.


### 4.7 Inline rendering engine

**Replaces:** nothing (new capability)
**Enables:** completion menus with descriptions, status bars, syntax
highlighting, multi-line prompts with proper reflow
**Leverages:** terminal sequences (§2.2), widget system (§4.1)

#### The problem

ksh93's editor can render exactly one thing: the edit buffer as a flat
string. It cannot:
- Display a completion menu below the input
- Show a status bar (git branch, mode indicator)
- Render styled text (bold, dim, colored)
- Compose multiple UI elements

Modern shells (elvish, fish) solve this with inline widget composition on
the main screen buffer (§2.1). ksh26 can adopt the same approach
incrementally.

#### The proposal

A phased rendering engine as described in §2.3:

**Phase 1** (SGR passthrough): ~30 lines. The display path stops counting
ANSI escape sequences as printable characters. Immediately enables syntax
highlighting via widget functions that return pre-colored strings.

**Phase 2** (ghost text): ~50-100 lines. This is §4.4 — listed separately
because it's independently valuable.

**Phase 3** (addon region): ~150-200 lines. A region below the input line,
managed by a simple clear-and-redraw loop. The region is an array of
strings (one per line). Widgets can set the region content. Used for:
- Completion menus with descriptions and grouping
- Status information (git branch, current mode, etc.)
- Error messages or inline documentation

Data structure: a new `Edit_t` field `e_addon` (array of strings + count).
Rendering: after drawing the input line, cursor-down into the addon region,
clear-to-EOS, print each addon line, cursor-up back to the input line.

**Phase 4** (delta rendering): ~300-500 lines. Full Buffer abstraction
(Cell grid + cursor) with old-vs-new comparison. Only needed if Phase 3
produces visible flicker. May be deferred indefinitely.

#### Why this is a win-win

- **Completion menus with descriptions**: Phase 3 renders structured
  completion results (§4.2) in a multi-line region below the input.
  fish/zsh parity for completion UX.
- **Status bar**: Phase 3 enables a persistent region for git branch,
  vi mode indicator, etc. Currently these are hacked into the prompt
  string.
- **Syntax highlighting**: Phase 1 enables syntax highlighting as a pure
  widget function — no display path changes beyond SGR passthrough.
- **Incremental**: each phase is useful independently. No big-bang.

#### Cost assessment

- **C work**: Phase 1 is trivial (~30 lines). Phase 2 is small (~100
  lines). Phase 3 is moderate (~200 lines). Phase 4 is significant
  (~500 lines) but may be unnecessary.
- **Risk**: low per phase. Each phase is additive. Phases 1-2 are
  display-path-only. Phase 3 adds a new region but doesn't change
  existing rendering. Phase 4 replaces the rendering loop but can be
  feature-flagged.


### 4.8 POSIX compatibility mode

**Replaces:** ksh93's current `-o posix` (which is incomplete)
**Enables:** clear boundary between portable and extended code
**Leverages:** existing option infrastructure, yash's design

#### The problem

ksh93 has `set -o posix` but it's a grab-bag of behavioral tweaks rather
than a principled compatibility boundary. Some non-POSIX features are
suppressed; others aren't. Users can't rely on POSIX mode to tell them
whether their script is portable.

yash's approach: when POSIX mode is active, non-POSIX extensions produce
errors. This is honest — it makes the extension boundary visible.

#### The proposal

When `set -o posix` is active:
- Non-POSIX builtins (`print`, `whence`, `typeset -C`, compound
  variables, etc.) produce a diagnostic and fail
- Non-POSIX syntax (e.g., `[[ ]]`, `(( ))`, `${ ...; }`) produces
  a parse error
- Non-POSIX options (`errreturn`, `forlocal`, `notifyle`, etc.) are
  unavailable
- The `.sh.*` namespace is unavailable

When POSIX mode is inactive (default), all ksh93 extensions work normally.

This gives script authors a reliable test: run with `ksh -o posix script.sh`
and if it succeeds, the script is portable.

#### Cost assessment

- **C work**: moderate. ~50 lines of checks scattered across builtins,
  the parser, and option handling. The infrastructure for conditional
  feature availability already exists (the `SHOPT_*` compile-time flags);
  this makes it runtime-switchable.
- **Risk**: medium. Must ensure the right set of features is gated.
  Getting this wrong (too strict or too lenient) undermines the purpose.
  Start conservative (gate only clearly non-POSIX features) and expand.


### 4.9 Language refinements

Small, high-value additions inspired by yash (see Design reference section).
Each is independently implementable.

#### `errreturn`

```ksh
set -o errreturn
```

Like `errexit` but returns from the current function with the failing
status instead of exiting the shell. Fixes the fundamental `errexit`
usability problem.

Implementation: in the `errexit` check path in `sh_exec()`, if
`SH_ERRRETURN` is set and we're inside a function (check `sh.st.fn_depth`),
`siglongjmp` to the function's `sh_pushcontext` frame instead of calling
`sh_exit()`. The polarity frame guarantees correct unwinding. ~20 lines.

#### `forlocal`

```ksh
set -o forlocal
```

Loop variables in `for` loops are automatically scoped to the loop body.

Implementation: in the `TFOR` handler in `sh_exec()`, if `SH_FORLOCAL` is
set, push a variable scope for the loop variable before the loop body,
pop on exit. ~10 lines.

#### `notifyle`

```ksh
set -o notifyle
```

Defer background job completion notifications until the next prompt
display, preventing them from corrupting the current line edit.

Implementation: in `job_reap()`, if `SH_NOTIFYLE` is set and the editor
is active, queue the notification instead of printing it immediately.
Drain the queue in `ed_setup()` (prompt time). ~10 lines.

#### Right prompt (`PS1R`)

```ksh
PS1R='%d'   # right-aligned prompt showing current directory
```

A right-aligned prompt string. Displayed on the right edge of the terminal.
Auto-erased when the cursor approaches it.

Implementation: in `ed_setup()`, after rendering the left prompt, calculate
remaining width, render `PS1R` right-aligned using cursor-right. Track the
right prompt boundary; if cursor reaches it during editing, clear it. ~30
lines.


## Part 5: What to avoid

### 5.1 Structured/typed pipelines

elvish's value pipelines, nushell's table pipelines, and PowerShell's object
pipelines are all interesting but represent a different paradigm from
Bourne-family shells. ksh93's byte-stream pipes are deeply embedded in the
execution engine (`sh_exec` TFIL handler, `sh_pipe()`, the entire I/O
layer). Adding a parallel structured channel would require changes to
`io.c`, `xec.c`, `jobs.c`, and the subshell mechanism.

ksh93's compound variables already provide structured data *within* the
shell. Using compound variables for completion results (§4.2) demonstrates
this: structured data stays within the language's existing facilities
rather than requiring a new pipeline mechanism.

### 5.2 zsh-scale completion framework

zsh's compsys is ~30,000 lines of zsh script on top of ~5,000 lines of C.
It's powerful but violates the minimalist principle. The `_arguments` DSL,
the `zstyle` context system, and the completer stack are each individually
complex and together form an edifice that few users understand fully.

The alternative: a simple registration mechanism (§4.5) that maps commands
to completion functions, with structured results (§4.2) for display. The
completion functions themselves can be as sophisticated as needed, but the
framework is minimal. Heavy lifting (parsing man pages, understanding
option syntax) is delegated to external tools like carapace.

### 5.3 Sigil changes or syntax-breaking innovations

ion's `$`/`@` distinction, oils/ysh's expression mode, and nushell's
`def` with typed parameters all require changes to the shell language that
would break backward compatibility. ksh93's syntax is stable and well-
understood. Changes to it should be avoided unless the benefit is
extraordinary and the migration path is clear.

ksh93 already has `typeset -a` for arrays, `typeset -A` for associative
arrays, and `typeset -C` for compound variables. The type system is
adequate for structured completion results and widget communication.

### 5.4 Premature syntax highlighting

Syntax highlighting is high-appeal but low-payoff architecturally. It
requires changes to the display path, integration with the lexer, and
careful handling of terminal compatibility. It should not drive architecture
decisions.

If the widget system (§4.1) and the rendering engine (§4.7 Phase 1) exist,
syntax highlighting becomes a widget function that can be added later
without further C changes — the widget returns SGR-coded text and the
display path passes it through.

### 5.5 Overengineered coprocess infrastructure

The coprocess mechanism works for what it was designed for (persistent
bidirectional pipes to background processes). Don't extend or modify it
for interactive tool integration. carapace is per-invocation (`$()`), fzf
needs foreground terminal access (`$()`), and no persistent completion
daemon exists today. See §3.4 for the full analysis.


## Part 6: Priority ordering

Ranked by the ratio of architectural payoff to implementation cost:

| Priority | Proposal | Payoff | Cost | Dependencies |
|----------|----------|--------|------|--------------|
| 1 | §4.9 Language refinements | 3 footgun fixes, ~40 lines total | ~40 lines C | None |
| 2 | §4.3 Editor lifecycle events | Eliminates 3 hacks | ~30 lines C | None |
| 3 | §4.1 Editor widget system | Enables all interactive features | ~400 lines C | None (subsumes §4.3) |
| 4 | §4.4 Ghost text rendering | Autosuggestions, completion preview | ~100 lines C | None |
| 5 | §4.2 Structured completion results | Descriptions, grouping, carapace | ~100 lines C | §4.1 |
| 6 | §4.5 `complete` builtin | Per-command completion registration | ~150 lines C | §4.1 |
| 7 | §4.7 Inline rendering engine | Completion menus, status bar | ~30-500 lines C (phased) | §4.4 (Phase 2) |
| 8 | §4.8 POSIX compatibility mode | Portability boundary | ~50 lines C | None |
| 9 | §4.6 History search widget | Incremental search | ~0 lines C | §4.1 |

§4.9 (language refinements) is first because `errreturn`, `forlocal`, and
`notifyle` are tiny changes that fix real usability problems. They don't
depend on anything and don't require new infrastructure.

§4.3 (lifecycle events) is second because it eliminates real workarounds in
sane.ksh/pure.ksh/hist.ksh with ~30 lines of C.

§4.1 (widget system) is third because it subsumes §4.3 and enables
everything else. If §4.1 is implemented, §4.3 is unnecessary as a separate
mechanism — lifecycle events become widgets.

The practical build order is either:

**Path A** (incremental): §4.9 → §4.3 → §4.4 → §4.1 → §4.2 → §4.5 → §4.7

Start with the cheapest wins, add the widget system when the foundation
is proven. §4.3 gets replaced by §4.1 eventually, but provides value
immediately.

**Path B** (keystone-first): §4.9 → §4.1 → §4.4 → §4.2 → §4.5 → §4.7

Skip §4.3 entirely, go straight to the widget system. More upfront work
but no throwaway code.

Either way, §4.9 is first and §4.7 is last (each phase is independently
deployable).


## Part 7: Source references

### ksh93 editor internals (ksh26 branch)

| File | Key functions/structures |
|------|------------------------|
| `src/cmd/ksh26/edit/edit.c` | `ed_getchar` (char intake + KEYBD dispatch), `keytrap` (trap invocation), `putstack` (lookahead buffer), `ed_read` (raw tty read), `ed_setup` (prompt handling) |
| `src/cmd/ksh26/edit/edit.h` | `Edit_t` struct (shared editor state), `LOOKAHEAD` (80-entry ring buffer) |
| `src/cmd/ksh26/edit/vi.c` | `ed_viread` (entry), `getline` (insert loop), `cntlmode` (command loop), `textmod` (text modification dispatch) |
| `src/cmd/ksh26/edit/emacs.c` | `ed_emacsread` (entry + dispatch switch), `escape` (ESC sequence handler) |
| `src/cmd/ksh26/edit/completion.c` | `ed_expand` (filename/variable completion), `ed_macro` (alias-based macro expansion), `find_begin` (word boundary detection) |
| `src/cmd/ksh26/edit/history.c` | `hist_locate`, `hist_word`, `hist_copy` (history access) |
| `src/cmd/ksh26/sh/io.c:1987` | `slowread` — Sfio discipline that selects `ed_viread`/`ed_emacsread`/`ed_read` |

### ksh93 discipline internals

| File | Key functions/structures |
|------|------------------------|
| `src/cmd/ksh26/include/nval.h` | `Namdisc_t` (vtable), `Namfun_t` (chain node), `Namval_t` (variable node) |
| `src/cmd/ksh26/sh/nvdisc.c` | `nv_disc` (stack push/pop), `nv_setdisc` (discipline registration), `assign`/`lookup` (`.set`/`.get` dispatch), `nv_adddisc` (custom event names), `nv_bfsearch` (dot-path resolution) |
| `src/cmd/ksh26/sh/nvtree.c` | `treedisc` (compound variable discipline), `create_tree` (dot-path child creation) |
| `src/cmd/ksh26/sh/init.c` | `nv_init` (wires C disciplines to `.sh.*` nodes), `stat_disc` / `create_stat` (`.sh.stats.*` template) |
| `src/cmd/ksh26/data/variables.c` | `shtab_variables[]` (variable table), `nv_discnames[]` (get/set/append/unset/getn) |
| `src/cmd/ksh26/include/variables.h` | `ED_CHRNOD`..`ED_MODENOD` index macros for `.sh.edchar`..`.sh.edmode` |

### ksh93 coprocess internals

| File | Key functions/structures |
|------|------------------------|
| `src/cmd/ksh26/sh/xec.c:3383` | `coproc_init()` — pipe setup, fd assignment |
| `src/cmd/ksh26/sh/xec.c` | `TFORK` handler — `|&` creates coprocess via `coproc_init` |
| `src/cmd/ksh26/sh/io.c` | `sh_coaccept()` — accept coproc connection, fd management |
| `src/cmd/ksh26/include/shell.h` | `sh.cpipe[]`, `sh.coutpipe`, `sh.cpid` — single-slot state |

### ksh26 polarity frame infrastructure

| File | Key functions/structures |
|------|------------------------|
| `src/cmd/ksh26/include/shell.h` | `struct sh_polarity`, `struct sh_polarity_lite`, `struct sh_prefix_guard` |
| `src/cmd/ksh26/sh/xec.c` | `sh_polarity_enter`/`sh_polarity_leave`, `sh_polarity_lite_enter`/`_leave`, `sh_debug`, `sh_fun` |
| `src/cmd/ksh26/sh/name.c` | `sh_prefix_enter`/`sh_prefix_leave`, `sh_scope_acquire`/`sh_scope_release` (scope pool) |
| `src/cmd/ksh26/sh/fault.c` | `sh_trap` (with polarity frame) |

### Shell comparison sources

| Shell | Version/source consulted | Key features referenced |
|-------|-------------------------|------------------------|
| bash | 5.2 (GNU readline integration) | `complete`/`compgen`/`COMPREPLY`, `bind -x`, `PROMPT_COMMAND`, `READLINE_LINE`/`READLINE_POINT` |
| zsh | 5.9 (ZLE + compsys) | ZLE widgets, `compadd`, `_arguments`, `zstyle`, `precmd`/`preexec`, `zle-keymap-select` |
| fish | 3.7 (event-driven editor, `src/screen.cpp` delta rendering) | `complete` command, autosuggestions, syntax highlighting, `commandline`, `bind --mode`, background highlight thread |
| elvish | 0.21 (`pkg/cli/term/` Buffer rendering) | `edit:completion:arg-completer`, `edit:complex-candidate`, modal editor, navigation mode, `ExtendDown`/`ExtendRight` composition, delta rendering |
| nushell | 0.101 (reedline, typed signatures) | Command signatures with `@completer`, completion options records, structured pipelines |
| PowerShell | 7.4 (PSReadLine) | `Set-PSReadLineKeyHandler`, `ICommandPredictor`, 20ms prediction deadline |
| yash | 2.57 (manual + source) | `errreturn`, `forlocal`, `notifyle`, POSIX mode, completion descriptions, `PS1R`, `POST_PROMPT_COMMAND`, array-valued hooks |
| oils/ysh | 0.25 (exterior-first) | Gradual upgrade from bash, expression mode |
| ion | 1.0-alpha (Redox) | `$`/`@` sigil distinction, method syntax |
| murex | 6.3 (MIME pipes) | Arrow pipe `->`, MIME-type-aware filtering |
| carapace | 1.1 (external completer) | JSON/bash output formats, bridge mode, 1600+ command specs |
| fzf | 0.57 (fuzzy finder) | 4-channel I/O architecture, foreground terminal takeover |


## Part 8: Relationship to existing ksh26 work

The proposals in Part 4 are designed to build on ksh26's completed
directions (REDESIGN.md §Direction status), not to compete with them.

### What the polarity frame enables for interactive features

The polarity frame API (`sh_polarity_enter`/`sh_polarity_leave`) was
designed for non-interactive correctness: ensuring that trap handlers
and discipline functions don't corrupt interpreter state during compound
assignment, name resolution, and other value-mode operations.

The same API directly enables safe interactive extensibility:

1. **Widget dispatch goes through `sh_fun()`**, which already uses
   `sh_polarity_enter`/`sh_polarity_leave`. Every widget invocation
   gets correct state isolation automatically.

2. **The `keytrap()` function in edit.c has weaker isolation** — it
   saves `sh.savexit` and the lex state but nothing else. Widget dispatch
   via the polarity frame is strictly safer.

3. **Completion widgets can run arbitrary shell code** (command
   substitutions, `nv_open`, function calls) without risk of corrupting
   the editor or interpreter state, because the polarity frame isolates
   the entire `sh.st`, `sh.prefix`, and `sh.namespace`.

4. **The sh_polarity_lite optimization** (REDESIGN.md §7b) demonstrates
   that nested polarity frames can be lightweight when the inner frame
   already provides full protection. Widget dispatch inside the editor
   could use the same pattern: a lite frame at the editor dispatch point,
   relying on `sh_fun()`'s full frame for the heavy isolation.

### What compound variables enable for structured results

ksh93's compound variable infrastructure — `typeset -C`, associative
arrays, the `treedisc` discipline in nvtree.c — was designed for
structured data within the shell language. Using it for completion
results (§4.2) is a natural extension:

- Compound arrays already serialize/deserialize via `nv_getvtree` /
  `put_tree`.
- The `createf` discipline slot handles dot-path navigation, so
  `.sh.value[0].description` just works.
- No new data structure, no new parser, no new serialization format.

### What the scope pool enables for widget performance

The scope dictionary pool (REDESIGN.md §7c) reduces malloc/free overhead
for function calls. Widget functions are called frequently (at least once
per Tab press, potentially per character for autosuggestions), so the pool
directly benefits interactive responsiveness.

### Continuation stack and editor events

The continuation stack (`sh_pushcontext`/`sh_popcontext`) and the polarity
frame nest in a defined order (REDESIGN.md §Direction 6): stk (outermost)
→ polarity (middle) → continuation (innermost). Editor widget dispatch
fits this pattern: the editor freezes stk, enters a polarity frame, and
the widget function may push its own continuation frame internally.

The editor events (§4.3) do not need continuation frames — they fire and
return. This makes them cheaper than full widget calls and appropriate for
high-frequency events like `precmd`.

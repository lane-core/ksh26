SHELL(3)

# NAME

shell - a ksh library interface

# SYNOPSIS

## HEADERS/LIBRARIES

```
#include        <shell.h>
libshell.a      -lshell
```

## DATA TYPES

```
Shell_t;
Shopt_t;
Shscope_t;
Shbltin_t;
Shbltin_f;
Shinit_f;
Shwait_f;
```

## FUNCTIONS

```
noreturn void   sh_main(int argc, char *argv[], Sh_init fn);
Shell_t         *sh_init(int argc, char *argv[]);
Shell_t         *sh_getinterp(void);

Namval_t        *sh_addbuiltin(const char *name, Sh_bltin_f fn, void *arg);

uint64_t        sh_isoption(int option);
uint64_t        sh_onoption(int option);
uint64_t        sh_offoption(int option);

void            *sh_parse(Sfio_t *sp, int flags);
int             sh_trap(const char *string, int mode);
int             sh_run(int argc, char *argv[]);
int             sh_eval(Sfio_t *sp, int mode);
int             sh_fun(Namval_t *funnode, Namval_t *varnode, char *argv[]);
int             sh_funscope(int argc, char *argv[], int(*fn)(void*), void *arg, int flags);
Shscope_t       *sh_getscope(int index, int whence);
Shscope_t       *sh_setscope(Shscope_t *scope);

int             (*sh_fdnotify(int(*fn)(int,int)))(int,int);
char            *sh_fmtq(const char *string);
Shwait_f        *sh_waitnotify(Shwait_f fn);
void            sh_delay(double sec, int sflag);
Sfio_t          *sh_iogetiop(int fd, int mode);
int             sh_sigcheck(void);
```

# DESCRIPTION

The Shell library is a set of functions for writing extensions to *ksh*
or writing commands that embed shell command processing. The include file
*<shell.h>* contains the type definitions, function prototypes, and
symbolic constants defined by this interface. It also defines replacement
definitions for the standard library functions *access()*, *close()*,
*dup()*, *exit()*, *fcntl()*, *lseek()*, *open()*, *pipe()*, *read()*,
and *write()* that must be used with all code intended to be compiled as
built-in commands.

The *<shell.h>* header includes *<ast.h>* which in turn includes the
standard headers *<stddef.h>*, *<stdlib.h>*, *<stdarg.h>*, *<limits.h>*,
*<stdio.h>*, *<string.h>*, *<unistd.h>*, *<sys/types.h>*, *<fcntl.h>*,
and *<locale.h>*. The *<shell.h>* header also includes *<cdt.h>*,
*<cmd.h>*, *<sfio.h>*, *<nval.h>*, *<stk.h>*, and *<error.h>*, so in
most cases programs only require the single header *<shell.h>*.

Programs can use this library in one of the following ways:

. To write builtin commands and/or other code that will be loaded into
  the shell by loading dynamic libraries at run time using the
  *builtin*(1) command. The shell will look for a function named
  *lib_init* in your library and, if found, will execute this function
  with two arguments. The first argument will be an *int* with value *0*
  when the library is loaded. The second argument will contain a pointer
  to a structure of type *Shbltin_t*. In addition, for each argument
  named on the *builtin* command line, it will look for a function named
  *b_name()* in your library and will add _name_ as a built-in.

. To build a separate command that uses the shell as a library at compile
  or run time. In this case *sh_init()* must be called to initialize
  this library before any other functions in this library are invoked.
  The arguments _argc_ and _argv_ are the number of arguments and the
  vector of arguments as supplied by the shell. It returns a pointer to
  the *sh* shell state structure which is of type *Shell_t*. Since only
  one shell interpreter per process is supported, there is only one
  instance of *sh*, so it does not matter whether it is accessed directly
  or via a pointer.

. To build a new version of *ksh* with extended capabilities, for
  example *tksh*(1). In this case, the user writes a *main()* function
  that calls *sh_main()* with the _argc_ and _argv_ arguments from
  *main* and a pointer to function _fn_ as a third argument. The
  function _fn_ will be invoked with argument *0* after *ksh* has done
  initialization, but before *ksh* has processed any start up files or
  executed any commands. The function _fn_ will be invoked with an
  argument of *1* before *ksh* begins to execute a script that has been
  invoked by name since *ksh* cleans up memory and long jumps back to
  the beginning of the shell in this case. The function _fn_ will be
  called with argument *-1* before the shell exits.

The *Shell_t* structure contains the following public members:

```
Shopt_t   options;     /* set -o options */
Dt_t      *var_tree;   /* shell variable dictionary */
Dt_t      *fun_tree;   /* shell function dictionary */
Dt_t      *alias_tree; /* shell alias dictionary */
Dt_t      *bltin_tree; /* shell built-in command dictionary */
Dt_t      *track_tree; /* shell hash table (tracked aliases) */
Shscope_t *topscope;   /* pointer to top-level scope */
int       inlineno;    /* line number of current input file */
int       exitval;     /* exit status of the current command */
int       savexit;     /* exit status of the last command */
```

As of ksh 93u+m, it is officially supported to access this structure
directly as *sh*. In addition, a pointer to this structure is returned
by *sh_init()* but can also be retrieved by a call to
*sh_getinterp()*.

All built-in commands to the shell are invoked with three arguments.
The first two arguments give the number of arguments and the argument
list and use the same conventions as the *main()* function of a
program. The third argument is a pointer to a structure of type
*Shbltin_t*. This structure contains *shp* which is a pointer to the
shell interpreter, and *ptr* which is a pointer that can be associated
with each built-in.

The *sh_addbuiltin()* function is used to add, replace, or delete
built-in commands. It takes the name of the built-in _name_, a pointer
to the function that implements the built-in _fn_, and a pointer that
will be passed to the function in the *ptr* field when it is invoked. If
_fn_ is non-NULL the built-in command is added or replaced. Otherwise,
*sh_addbuiltin()* will return a pointer to the built-in if it exists or
NULL otherwise. If _arg_ is *(void\*)1* the built-in will be deleted.
The _name_ argument can be in the format of a pathname. It cannot be the
name of any of the special built-in commands. If _name_ contains a */*,
the built-in is the basename of the pathname and the built-in will only
be executed if the given pathname is encountered when performing a path
search. When adding or replacing a built-in, *sh_addbuiltin()* returns a
pointer to the name-value pair corresponding to the built-in on success
and NULL if it is unable to add or replace the built-in. When deleting a
built-in, NULL is returned on success or if not found, and the
name-value pair pointer is returned if the built-in cannot be deleted.

The functions *sh_onoption()*, *sh_offoption()*, *sh_isoption()* are
used to set, unset, and test for shell options respectively. The
_option_ argument can be any one of the following:

- *SH_ALLEXPORT*
	The *NV_EXPORT* attribute is given to each variable whose name is
	an identifier when a value is assigned.
- *SH_BGNICE*
	Each background process is run at a lower priority.
- *SH_ERREXIT*
	Causes a non-interactive shell to exit when a command, other than
	a conditional command, returns non-zero.
- *SH_EMACS*
	The emacs editing mode.
- *SH_GMACS*
	Same as the emacs editing mode except for the behavior of
	CONTROL-T.
- *SH_HISTORY*
	Indicates that the history file has been created and that commands
	can be logged.
- *SH_IGNOREEOF*
	Do not treat end-of-file as exit.
- *SH_INTERACTIVE*
	Set for interactive shells. Do not set or unset this option.
- *SH_MARKDIRS*
	A */* is added to the end of each directory generated by pathname
	expansion.
- *SH_MONITOR*
	Indicates that the monitor option is enabled for job control.
- *SH_NOCLOBBER*
	The *>* redirection will fail if the file exists. Each file
	created with *>* will have the *O_EXCL* bit set as described in
	*<fcntl.h>*.
- *SH_NOGLOB*
	Do not perform pathname expansion.
- *SH_NOLOG*
	Do not save function definitions in the history file.
- *SH_NOTIFY*
	Cause a message to be generated as soon as each background job
	completes.
- *SH_NOUNSET*
	Cause the shell to fail with an error if an unset variable is
	referenced.
- *SH_PRIVILEGED*
	This mode is on whenever the effective UID (GID) is not equal to
	the real UID (GID). Turning this off causes the effective UID and
	GID to be set to the real UID and GID.
- *SH_VERBOSE*
	Cause each line to be echoed as it is read by the parser.
- *SH_XTRACE*
	Cause each command to be displayed after all expansions, but
	before execution.
- *SH_VI*
	The vi edit mode.

The *sh_trap()* function can be used to compile and execute a string or
file. A value of *0* for _mode_ indicates that _name_ refers to a
string. A value of *1* for _mode_ indicates that _name_ is an
*Sfio_t\** to an open stream. A value of *2* for _mode_ indicates that
_name_ points to a parse tree that has been returned by *sh_parse()*.
The complete file associated with the string or file is compiled and then
executed so that aliases defined within the string or file will not take
effect until the next command is executed. The shell's *$?* special
parameter is made local to the string or file executed so that it is not
affected for subsequent commands. The return value of *sh_trap()* is the
exit status of the last command executed by the string or file.

The *sh_run()* function will run the command given by the argument list
_argv_ containing _argc_ elements. If _argv_*[0]* does not contain a
*/*, it will be checked to see if it is a built-in or function before
performing a path search.

The *sh_eval()* function executes a string or file stream _sp_. If
_mode_ is non-zero and the history file has been created, the stream
defined by _sp_ will be appended to the history file as a command.

The *sh_parse()* function takes a pointer to a string or file stream
_sp_, and compilation flags, and returns a pointer to a parse tree of the
compiled stream. This pointer can be used in subsequent calls to
*sh_trap()*. The compilation flags can be zero or more of the following:

- *SH_NL*
	Treat new-lines as *;*.
- *SH_EOF*
	An end of file causes syntax error. By default it will be treated
	as a new-line.

*ksh* executes each function defined with the *function* reserved word
in a separate scope. The *Shscope_t* type provides an interface to some
of the information that is available on each scope. The structure
contains the following public members:

```
Shscope_t *par_scope; /* pointer to parent scope */
int       argc;       /* number of arguments */
char      **argv;     /* array of arguments */
char      *cmdname;   /* command name */
char      *filename;  /* file name */
char      *funname;   /* function name */
int       lineno;     /* current script line number */
Dt_t      *var_tree;  /* function's variables dictionary */
Shscope_t *self;      /* pointer to copy of this scope */
```

The *sh_getscope()* function can be used to get the scope information
associated with an existing scope. Scopes are numbered from *0* for the
global scope up to the current scope level. The _whence_ argument uses
the symbolic constants associated with *lseek()* to indicate whether
the _scope_ argument is absolute, relative to the current scope, or
relative to the topmost scope.

The *sh_setscope()* function can be used to make a known scope the
current scope. It returns a pointer to the old current scope.

The *sh_funscope()* function can be used to run a function in a new
scope. The arguments _argc_ and _argv_ are the number of arguments and
the list of arguments respectively. If _fn_ is non-NULL, then this
function is invoked with _argc_, _argv_, and _arg_ as arguments.

The *sh_fun()* function can be called within a discipline function or
built-in extension to execute a discipline function script. The argument
_funnode_ is a pointer to the shell function or built-in to execute. The
argument _varnode_ is a pointer to the name-value pair that has defined
this discipline. The array _argv_ is a NULL terminated list of arguments
that are passed to the function.

By default, *ksh* only records but does not act on signals when running a
built-in command. If a built-in takes a substantial amount of time to
execute, then it should check for interrupts periodically by calling
*sh_sigcheck()*. If a signal is pending, *sh_sigcheck()* will exit the
function you are calling and return to the point where the most recent
built-in was invoked, or where *sh_eval()* or *sh_trap()* was called.

The *sh_delay()* function causes the shell to sleep for the fractional
number of seconds defined by _sec_. If _sec_ is *inf*, the shell sleeps
forever. If _sec_ is *nan*, the behavior is undefined. If _sflag_ is
true, the shell will stop sleeping when any signal is received; otherwise
signals such as *SIGCONT* and *SIGINFO* are treated normally.

The *sh_fmtq()* function can be used to convert a string into a string
that is quoted so that it can be reinput to the shell. The quoted string
returned by *sh_fmtq* may be returned on the current stack, so it must
be saved or copied.

The *sh_fdnotify()* function causes the function _fn_ to be called
whenever the shell duplicates or closes a file. It is provided for
extensions that need to keep track of file descriptors that could be
changed by shell commands. The function _fn_ is called with two
arguments. The first argument is the original file descriptor. The
second argument is the new file descriptor for duplicating files, and
*SH_FDCLOSE* when a file has been closed. The previously installed
*sh_fdnotify()* function pointer is returned.

The *sh_waitnotify()* function causes the function _fn_ to be called
whenever the shell is waiting for input from a slow device or waiting
for a process to complete. This function can process events and run
shell commands until there is input, the timer is reached, or a signal
arises. It is called with three arguments. The first is the file
descriptor from which the shell is trying to read, or *-1* if the shell
is waiting for a process to complete. The second is a timeout in
milliseconds. A value of *-1* for the timeout means that no timeout
should be set. The third argument is 0 for input file descriptors and 1
for output file descriptors. The function needs to return a value *>0*
if there is input on the file descriptor, and a value *<0* if the
timeout is reached or a signal has occurred. A value of *0* indicates
that the function has returned without processing and that the shell
should wait for input or process completion. The previously installed
*sh_waitnotify()* function pointer is returned.

The *sh_iogetiop()* function returns a pointer to the Sfio stream
corresponding to file descriptor number _fd_ and the given _mode_. The
mode can be either *SFIO_READ* or *SFIO_WRITE*. The _fd_ argument can
be the number of an open file descriptor or one of the following
symbolic constants:

- *SH_IOCOPROCESS*
	The stream corresponding to the most recent co-process.
- *SH_IOHISTFILE*
	The stream corresponding to the history file. If no stream exists
	corresponding to _fd_ or the stream cannot be accessed in the
	specified mode, NULL is returned.

# SEE ALSO

*builtin*(1), *cdt*(3), *error*(3), *nval*(3), *sfio*(3), *stk*(3),
*tksh*(1)

# AUTHOR

David G. Korn (dgk@research.att.com).

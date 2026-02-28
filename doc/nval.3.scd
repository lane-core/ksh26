NVAL(3)

# NAME

nval - the ksh name/value library

# SYNOPSIS

## HEADERS/LIBRARIES

```
#include    <nval.h>
libshell.a  -lshell
```

## DATA TYPES

```
Namval_t;
Namfun_t;
Namarr_t;
Namdisc_t;
```

## OPENING/CLOSING

```
Namval_t    *nv_open(const char *name, Dt_t *dict, int flags);
Namval_t    *nv_create(const char *name, Dt_t *dict, int flags, Namfun_t *fp);
Namval_t    *nv_namptr(void *ptr, int indx);
void        nv_delete(Namval_t *np, Dt_t *dict, int nofree);
```

## GETTING AND SETTING VALUES

```
char        *nv_getval(Namval_t *np);
Sfdouble_t  nv_getnum(Namval_t *np);
char        *nv_name(Namval_t *np);
void        nv_putval(Namval_t *np, const char *val, int flags);
void        nv_unset(Namval_t *np, int flags);
int         nv_clone(Namval_t *src, Namval_t *dest, int flags);
```

## ATTRIBUTES AND SIZE

```
int         nv_isnull(Namval_t *np);
int         nv_setsize(Namval_t *np, int size);
int         nv_size(Namval_t *np);
unsigned    nv_isattr(Namval_t *np, unsigned flags);
Namfun_t    *nv_isvtree(Namval_t *np);
unsigned    nv_onattr(Namval_t *np, unsigned flags);
unsigned    nv_offattr(Namval_t *np, unsigned flags);
void        nv_newattr(Namval_t *np, unsigned flags, int size);
```

## ARRAY HANDLING

```
unsigned    nv_isarray(Namval_t *np);
Namarr_t    *nv_setarray(Namval_t *np, void*(*fun)(Namval_t*, const char*, int));
Namarr_t    *nv_arrayptr(Namval_t *np);
Namval_t    *nv_putsub(Namval_t *np, char *name, long mode);
Namval_t    *nv_opensub(Namval_t *np);
void        nv_setvec(Namval_t *np, int append, int argc, char *argv[]);
char        *nv_getsub(Namval_t *np);
int         nv_nextsub(Namval_t *np);
int         nv_aindex(Namval_t *np);
```

## DISCIPLINES

```
Namfun_t    *nv_disc(Namval_t *np, Namfun_t *fp, int flags);
Namfun_t    *nv_hasdisc(Namval_t *np, const Namdisc_t *dp);
char        *nv_getv(Namval_t *np, Namfun_t *fp);
Sfdouble_t  nv_getn(Namval_t *np, Namfun_t *fp);
void        nv_putv(Namval_t *np, const char *val, int flags, Namfun_t *fp);
char        *nv_setdisc(Namval_t *np, const char *a, Namval_t *f, Namfun_t *fp);
char        *nv_adddisc(Namval_t *np, const char **names);
const Namdisc_t *nv_discfun(int which);
```

## TYPES

```
Namval_t    *nv_type(Namval_t *np);
int         *nv_settype(Namval_t *np, Namval_t *tp, int flags);
Namval_t    *nv_mkinttype(char *name, size_t sz, int us, const char *str, Namdisc_t *dp);
void        nv_addtype(Namval_t *np, const char *str, Optdisc_t *op, size_t sz);
```

## MISCELLANEOUS FUNCTIONS

```
int         nv_scan(Dt_t *dict, void(*fn)(Namval_t*,void*), void *data, int mask, int flags);
Dt_t        *nv_dict(Namval_t *np);
void        nv_setvtree(Namval_t *np);
void        nv_setref(Namval_t *np, Dt_t *dp, int flags);
Namval_t    *nv_lastdict(void);
```

# DESCRIPTION

Nval is a library of functions for interacting with name-value pairs as
used in *ksh*. It is built on top of the container dictionary type
library facility in *libcdt* (see *cdt*(3)). Each name-value pair is
represented by a type named *Namval_t*. A *Namval_t* contains the name,
value, and attributes of a variable. Some attributes can have an
associated number that represents the field width, arithmetic base, or
precision. Additionally, each name-value pair can be associated with one
or more processing disciplines that affect its behavior.

The function *nv_open()* returns a pointer to a name-value pair
corresponding to the given _name_. It can also assign a value and give
attributes to a name-value pair. The argument _dict_ defines the
dictionary to search. A NULL value causes the shell global variable
dictionary to be searched.

The _flags_ argument consists of the bitwise-or of zero or more of the
attributes listed later and zero or more of the following:

- *NV_VARNAME*
	An invalid variable name causes an error.
- *NV_IDENTIFIER*
	A variable name that is not an identifier causes an error.
- *NV_ASSIGN*
	The _name_ argument can contain an assignment.
- *NV_NOARRAY*
	The _name_ argument cannot contain a subscript.
- *NV_NOREF*
	Do not follow references when finding the name-value pair.
- *NV_NOADD*
	The name-value pair will not be added if it doesn't exist. Instead,
	a NULL pointer will be returned.
- *NV_NOSCOPE*
	Only the top level scope is used.
- *NV_NOFAIL*
	Just return NULL when an error occurs. By default an error message
	is displayed and the current command is aborted.

If a name-value pair by this name does not already exist, it is created
unless _flags_ contains the *NV_NOADD* flag. If *NV_VARNAME*,
*NV_IDENTIFIER*, and *NV_ASSIGN* are all not specified, then no validity
check is performed on the _name_ argument and no further processing is
performed. Otherwise, if *NV_ASSIGN* is specified, then the characters
up to the first *=* or *+=* are used to find the name-value pair, and
the characters after the *=* are used to define the value that will be
assigned to this name-value pair. If _name_ does not contain an *=*,
then no assignment will be made. If the first identifier in _name_ is a
reference and is not preceded by a *.*, it will be replaced by the value
of the reference to find the name of a variable. Unless _flags_ contains
the *NV_NOREF* flag, if the name-value pair given by _name_ has the
*NV_REF* attribute, it will be replaced by the variable whose name is
the value of this name-value pair. If *NV_ASSIGN* is set in the _flags_
argument, the _name_ variable can contain an *=* and a value that will
be assigned to the name-value pair. Any attributes appearing in the
_flags_ argument will be applied to the name-value pair after any value
is assigned.

It is possible for an application to create additional dictionaries with
the cdt library and associate them with name-value pairs. The
*nv_dict()* function returns the dictionary associated with the
specified name-value pair, or if no dictionary was specified, NULL is
returned. The *nv_lastdict()* function returns a pointer to the
name-value pair that contains the last dictionary searched on the
previous *nv_open()*.

Name-value pairs can also be allocated without belonging to a
dictionary. They will typically be looked up by a _create_ discipline
associated with a parent node. In this case the node size will be
*NV_MINSZ* and _n_ nodes can be allocated via *calloc(NV_MINSZ, n)*.
The *nv_namptr()* function can be used on the pointer returned by
*calloc* along with the element number to return the corresponding
node. Each of these nodes must be given the *NV_MINIMAL* attribute.

The *nv_delete()* function will remove the node _np_ from the dictionary
_dict_. Unless _nofree_ is non-zero, the node _np_ will also be freed.

The *nv_name()* function returns the name of the given name-value pair
_np_. The *nv_setsize()* function returns the size of the field for
justified variables, the arithmetic base for integer variables, and the
precision or number of places after the decimal point for floating point
variables. If _size_ is greater than or equal to zero, the current size
is changed to this value. The *nv_size()* function is equivalent to
*nv_setsize()* with the second argument negative.

The *nv_getval()* function returns the value of the given name-value
pair as a string. A NULL return value indicates that the name-value pair
is unset. The *nv_getnum()* function returns the value of the given
name-value pair as a double precision number using the Sfio library (see
*sfio*(3)) type *Sfdouble_t*. For name-value pairs without the
*NV_INTEGER* attribute, the string value is evaluated as an arithmetic
expression to arrive at a numerical value.

The *nv_putval()* function is used to assign a _value_ to the name-value
pair _np_. The _flags_ argument consists of zero or more of the
bitwise-or of *NV_LONG*, *NV_SHORT*, *NV_DOUBLE*, *NV_INTEGER*,
*NV_RDONLY*, *NV_REF*, *NV_BINARY*, and *NV_NOFREE*. The presence of
*NV_RDONLY* allows the assignment to occur even if the name-value pair
has the *NV_RDONLY* attribute. The presence of *NV_INTEGER* indicates
that the _value_ argument is actually a pointer to a numerical type. By
default this type is *long*, but can be modified with *NV_LONG*,
*NV_SHORT*, and *NV_DOUBLE* to represent *long long*, *short*, *double*,
*long double*, and *float*. The presence of *NV_REF* indicates that the
_value_ argument is actually a pointer to a name-value pair and _np_
should become a reference to this name-value pair. If *NV_NOFREE* is
specified, _value_ itself becomes the value of the name-value pair _np_.
Otherwise, a copy of the value is stored as the value for _np_.

The *nv_unset()* function clears out the value and attributes of the
given name-value pair but does not free it. If called from the *putval*
discipline function, use the _flags_ argument as the _flags_ to
*nv_unset()*. Otherwise, use 0.

The following attributes can be associated with a name-value pair:

- *NV_EXPORT*
	The export attribute.
- *NV_RDONLY*
	The readonly attribute.
- *NV_LTOU*
	Lower case characters are converted to upper case characters.
- *NV_UTOL*
	Upper case characters are converted to lower case characters.
- *NV_RJUST*
	Right justify and blank fill. This attribute has an associated
	size that defines the string length of the value.
- *NV_LJUST*
	Left justify and blank fill. This attribute has an associated size
	that defines the string length of the value.
- *NV_ZFILL*
	Without *NV_LJUST*, right justify and fill with leading zeros.
	With *NV_LJUST*, left justify and strip leading zeros. This
	attribute has an associated size that defines the string length of
	the value.
- *NV_TAGGED*
	Indicates the tagged attribute.
- *NV_INTEGER*
	Causes value to be represented by a number. This attribute has an
	associated number that defines the arithmetic base to be used when
	the value is expanded as a string.
- *NV_DOUBLE*
	Used in conjunction with *NV_INTEGER* to cause value to be stored
	as a double precision floating point number. This attribute has an
	associated number that defines the number of places after the
	decimal point to be used when the value is expanded as a string.
- *NV_EXPNOTE*
	Used in conjunction with *NV_INTEGER* and *NV_DOUBLE* to cause the
	value to be represented in scientific notation when expanded as a
	string. This attribute has an associated number that defines the
	precision of the mantissa.
- *NV_HEXFLOAT*
	Used in conjunction with *NV_INTEGER* and *NV_DOUBLE* to cause the
	value to be represented in C99 %a format when expanded as a
	string.
- *NV_BINARY*
	The name-value pair contains a buffer of binary data and
	*nv_size()* is the number of bytes for this data. By default the
	value will be represented by the base64 encoding of the buffer.
	The *NV_LJUST* flag may also be specified and causes the buffer
	size to be fixed and data either truncated or filled with zero
	bytes.
- *NV_REF*
	The name-value pair is a name reference variable.
- *NV_MINIMAL*
	The name-value pair node is not embedded in a dictionary and is
	minimal size, *NV_MINSZ*.
- *NV_NODISC*
	All discipline functions are ignored when performing assignments
	and lookups.

The *nv_isattr()* function can test whether or not any of the attributes
given by _flags_ is set. The *nv_onattr()* and *nv_offattr()* functions
turn attributes on or off respectively. Only attributes that do not
affect the value can be set in this way. The *nv_newattr()* function can
be used to change the attributes and size of the given name-value pair
which may result in the value being changed to conform to the new
attributes and size. The _size_ argument is needed for attributes that
require an additional argument such as justified variables. Changing the
attribute may require changing the value to agree with the new
attributes. For an array variable, the values for each of the subscripts
will be changed.

The *nv_isvtree()* function returns a pointer to the compound variable
discipline if the node _np_ is a compound variable, or NULL otherwise.

The *nv_isarray()* function returns a non-zero value if the specified
name-value pair is an array.

The *nv_scan()* function is used to walk through all name-value pairs in
the dictionary given by _dict_. If the _flags_ variable contains the
*NV_NOSCOPE* flag, then only the top scope will be examined. The
remaining flags will be used in conjunction with _mask_ to further
restrict the walk. If _mask_ is non-zero, only the nodes for which
*nv_isattr(node, mask)* is equal to _flags_ will be visited. If _fn_ is
non-zero, then this function will be executed for each name-value pair
in the walk. The arguments to _fn_ will be a pointer to the name-value
pair and the _data_ pointer passed to *nv_scan()*. The number of
elements visited will be returned.

The *nv_clone()* function is used to make a copy of the contents of
name-value pair _src_ to another name-value pair _dest_.

## Disciplines

Disciplines provide a way to intercept the lookup and assignment
operations, to manage the creation of sub-variables, and to extend the
operations permitted on a name-value pair. A discipline consists of a
set of one or more functions and related data that are used to override
and extend the operations on a name-value pair. A discipline is defined
by the types *Namfun_t* and *Namdisc_t*. The *Namdisc_t* is not modified
by any of these functions and can therefore be shared by several
name-value pairs. It contains the following public fields in the order
listed:

```
size_t      dsize;
void        (*putval)(Namval_t*, const char*, int, Namfun_t*);
char        *(*getval)(Namval_t*, Namfun_t*);
double      (*getnum)(Namval_t*, Namfun_t*);
char        *(*setdisc)(Namval_t*, const char*, Namval_t*, Namfun_t*);
Namval_t    *(*createf)(Namval_t*, const char*, Namfun_t*);
Namfun_t    *(*clonef)(Namval_t*, Namval_t*, int, Namfun_t*);
char        *(*namef)(Namval_t*, Namfun_t*);
Namval_t    *(*nextf)(Namval_t*, Dt_t*, Namfun_t*);
Namval_t    *(*typef)(Namval_t*, Namfun_t*);
```

The *Namfun_t* type contains a member named *disc* which points to a
*Namdisc_t* structure. To create a discipline with additional user data,
define a structure with an instance of *Namfun_t* as the first element.
An application must initialize the *Namfun_t* portion of the structure
to zero and then set the _disc_ field to point to the *Namdisc_t*
structure. The *dsize* field of the *Namdisc_t* structure must be the
size of this structure. A value of 0 indicates that there are no
additional fields and is equivalent to *sizeof(Namfun_t)*. If different
instances of this structure use different sizes, then the *size* field
in the *Namfun_t* must be set to this size and overrides the value in
the *Namdisc_t* structure.

When a variable is referenced by calling the *nv_getval()* function, and
the *NV_NODISC* attribute is not set, the *getval()* discipline function
is called with a pointer to the name-value pair _np_ and a pointer to
the discipline _fp_. Inside the *getval()* function, the *nv_getv()*
function can be called to get the value of the name-value pair that
would have resulted if the discipline were not used. The *getnum()*
discipline is called whenever a numerical value is needed for the
name-value pair _np_ and the *NV_NODISC* attribute is not set. The
*nv_getn()* function can be called from within the *getnum()* discipline
to get the value that would have resulted if there were no *getnum()*
discipline.

The *putval()* discipline function is used to override the assignment of
values to a name-value pair. It is called whenever a value is assigned
with *nv_putval()* and the *NV_NODISC* attribute is not set, or when a
name-value pair is unset with *nv_unset()*. When a name-value pair is
unset, *putval()* is called with _value_ set to NULL. The *nv_putv()*
function is used within the *putval()* to perform the assignment or
unset that would have occurred if the discipline had not been installed.

The *createf()* discipline function is called from *nv_open()* or
*nv_create()* when the name-value pair preceding a *.* is found. This
function is passed the name-value pointer plus the remaining string and
the current _flags_ argument. The *createf()* discipline function must
return the created name-value pair, otherwise the default action will be
taken. If the name-value pair that is returned is the same as the one
given, then the behavior will be the same as if an invalid name had been
given to *nv_open()*. The *nv_create()* function may be called within
the *createf()* discipline function to perform the action that would
have occurred by an earlier *nv_open()* function.

The *setdisc()* discipline function is used to extend the set of
available shell level discipline functions associated with a name-value
pair by allowing builtins or functions whose name is of the form
_varname_*.*_action_ to be defined. By default, each name-value pair
can have a *get*, *set*, and *unset* discipline associated with it.
Whenever a builtin or function whose name is of the form
_varname_*.*_action_ is defined or is unset, and _action_ is not *get*,
*set*, or *unset*, the *setdisc()* function is invoked with the same
argument format as *nv_setdisc()*. The argument _f_ points to the
name-value pair associated with the function being defined, or NULL if
the function is being unset. If the given action _a_ is not known by
this discipline, it should return the value returned by calling
*nv_setdisc(np, a, f, fp)* so that it can be searched for in previously
stacked disciplines. Otherwise, the *setdisc()* function should save the
function name-value pair pointer, and return a non-NULL value. The
name-value pointer to the function can be used to invoke the function at
an application defined point. If the action _a_ is NULL, then _f_ points
to an action name instead of a name-value pair pointer. The *setdisc()*
must return the name of the action that follows the action name given by
_f_. If _f_ is also NULL, the name of the first action must be returned.
This allows an application to get the list of valid discipline action
names allowed by a given name-value pair.

The *nv_adddisc()* function is a higher level function that adds a
_setdisc_ discipline to the name-value pair that allows shell level
disciplines to be created for each of the names specified in _names_.

The *nv_discfun()* function can be used to get a pointer to discipline
functions that are provided by the library. Currently, the only one
provided is the one used to implement *nv_adddisc()* which can be
returned with an argument of *NV_DCADD*.

The *clonef()* discipline function is called by *nv_clone()* when making
a copy of the *Namfun_t* discipline to the new node. The first argument
is the original node, the second argument is the new node, and the third
argument is the flags that were passed down to *nv_clone()*. It must
return a new instance of the *Namfun_t\** _fp_. If omitted, then memory
whose size is determined by the *size* field of _fp_, if non-zero, or
_fp->disc_, will be allocated and copied from _fp_.

The *namef()* discipline function returns the name for this name-value
pair.

The *nextf()* is used for walking through the list of sub-variables
associated with this name-value pair. If the dictionary argument is
NULL, it must return the first sub-variable. Otherwise, it must return
the next sub-variable, or NULL if there are no more variables.

A discipline is installed or removed with the *nv_disc()* function. The
following flags can be specified:

- *NV_FIRST*
	If _fp_ is non-NULL, the discipline is moved to the top of the
	stack or pushed onto the top of the stack of disciplines
	associated with the given name-value pair _np_ if not already
	present. Otherwise, the top of the discipline stack is returned.
- *NV_LAST*
	If _fp_ is non-NULL, the discipline is moved to the bottom of the
	stack or pushed onto the bottom of the stack of disciplines
	associated with the given name-value pair _np_ if not already
	present. Otherwise, the bottom of the discipline stack is
	returned.
- *NV_POP*
	If _fp_ is non-NULL and it is on the stack, it is removed and _fp_
	is returned. If _fp_ is non-NULL and is not on the stack, NULL is
	returned. Otherwise, the top discipline is popped and returned.
- *NV_CLONE*
	If _fp_ is non-NULL and it is on the stack, it is replaced by a
	copy created by *malloc*(3). The *nofree* field is set to *0*. The
	new discipline is returned. Otherwise, NULL is returned.
- *0*
	If _fp_ is non-NULL then it is equivalent to *NV_FIRST*. Otherwise,
	it is equivalent to *NV_POP*.

The *nv_hasdisc()* function can be used to tell whether a discipline
whose discipline functions are those defined in _dp_ is installed. A
pointer to this discipline is returned.

## Arrays

The *nv_aindex()* function returns the current index for the indexed
array given by the name-value pair pointer _np_. The return value is
negative if _np_ refers to an associative array.

The *nv_setarray()* function is used to create an associative array from
a name-value pair node. The function _fun_ defines the semantics of the
associative array. Using _fun_ equal to *nv_associative()* implements
the default associative array semantics that are used with *typeset -A*.
The function _fun_ will be called with the third argument as follows:

- *NV_AINIT*
	Called at initialization. The function must return a pointer to a
	structure that contains the type *Namarr_t* as the first element.
	All other calls receive this value as an argument.
- *NV_AFREE*
	Called after all elements of the name-value pair have been deleted
	and the array is to be freed.
- *NV_ADELETE*
	The current element should be deleted.
- *NV_ANEXT*
	The array subscript should be advanced to the next subscript. A
	NULL return indicates that there are no more subscripts.
- *NV_ANAME*
	The name of the current subscript must be returned.
- *NV_ACURRENT*
	Returns a pointer to a name-value pair corresponding to the
	current subscript, or NULL if this array type doesn't represent
	each element as a name-value pair.
- *NV_ASETSUB*
	Set the current subscript to the name-value pair passed in as the
	second argument.

If _np_ refers to an array, *nv_arrayptr()* returns a pointer to the
array discipline structure *Namarr_t*. Otherwise *nv_arrayptr()* returns
NULL.

If _np_ refers to an array, *nv_getsub()* returns a pointer to the name
of the current subscript. Otherwise, *nv_getsub()* returns NULL.

The *nv_opensub()* function returns a pointer to the name-value pair
corresponding to the current subscript in an associative array.

The *nv_putsub()* function is used to set the subscript for the next
reference to _np_. If the _name_ argument is not NULL, it defines the
value of the next subscript. The _mode_ argument can contain one or more
of the following flags:

- *ARRAY_ADD*
	Add the subscript if not found. Otherwise, *nv_putsub()* returns
	NULL if the given subscript is not found.
- *ARRAY_SCAN*
	Begin a walk through the subscripts starting at the subscript
	given by _name_. If _name_ is NULL the walk is started from the
	beginning.
- *ARRAY_UNDEF*
	This causes any current scan to terminate and leaves the
	subscript in an undefined state.

If *ARRAY_ADD* is not given and the subscript does not exist, a NULL
value is returned.

The *nv_nextsub()* function is used to advance to the next subscript. It
returns 0 if there are no more subscripts or if called when not in a
scan.

## Types and References

The *nv_setref()* function makes the name-value pair _np_ into a
reference to the variable whose name is given by the value of _np_. The
*nv_open()* function is called with this name, the dictionary given by
_dp_, and the _flags_ argument. A NULL value causes the shell global
variable dictionary to be searched.

The *nv_setvtree()* function makes the name-value pair _np_ into a tree
structured variable so that *nv_getval()* will return a string
containing all the names and values of children nodes in a format that
can be used in a shell compound assignment.

The *nv_type()* function returns a name-value pair pointer that contains
the type definition for the specified name-value pair. The _nvname_
field contains the name for the type.

The *nv_settype()* function converts the name-value pair given by _np_
into the type given by _tp_.

The *nv_addtype()* function adds the name of the type given by _np_ to
the list of declaration built-ins. The _str_ argument contains the
string used by *optget*(3) to generate the man page and process the
options. The _op_ argument specifies the callback discipline used by
*optget*(3) and _sz_ specifies the size of the callback information so
that the *optget*(3) discipline can be extended with private data used
by the callback function.

The *nv_mkinttype()* function creates named integer types of the
specified _name_. The _size_ parameter is the size in bytes of the
integer variable and _us_ is non-zero for unsigned integer types. If
_dp_ is specified then integer variables of this type will all use this
discipline.

# SEE ALSO

*calloc*(3), *cdt*(3), *shell*(3), *optget*(3)

# AUTHOR

David G. Korn (dgk@research.att.com).

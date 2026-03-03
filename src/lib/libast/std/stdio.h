/*
 * std/stdio.h — pass through to system <stdio.h>
 *
 * This file previously redirected to ast_stdio.h which intercepted
 * all stdio symbols and routed them through sfio. That interception
 * layer has been retired (sfio retirement).
 */
#include_next <stdio.h>

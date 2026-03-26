/* probe: ksh26-locale — wctrans/towctrans functional test (output) */
#include <stdio.h>
#include <wchar.h>
#include <wctype.h>
int main(void)
{
	wctrans_t toupper_t = wctrans("toupper");
	wctrans_t tolower_t = wctrans("tolower");
	int r = towctrans('q', toupper_t) == 'Q' && towctrans('Q', tolower_t) == 'q';
	printf("#define _lib_wctrans\t%d\n", r);
	printf("#define _lib_towctrans\t%d\n", r);
	printf("#define _typ_wctrans_t\t%d\n", r);
	return !r;
}

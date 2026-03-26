/* probe: ast-common — integer type sizing
 * Compile+link+run, capture output.
 * Emits: _ast_int{1,2,4,8}_t, _ast_intmax_t, _ast_intmax_long, _ast_intswap
 * Requires: -D_ast_LL=1 (C23: always 1)
 */
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#define _ast_int8_t long
#define _ast_int8_str "long"
#define elementsof(x) (sizeof(x)/sizeof(x[0]))
static char i_char = 1;
static short i_short = 1;
static int i_int = 1;
static long i_long = 1L;
#if _ast_LL
static _ast_int8_t i_long_long = 1LL;
static unsigned _ast_int8_t u_long_long = 18446744073709551615ULL;
#else
static _ast_int8_t i_long_long = 1;
static unsigned _ast_int8_t u_long_long = 18446744073709551615;
#endif
static struct { char* name; int size; char* swap; } int_type[] = {
	"char", sizeof(char), (char*)&i_char,
	"short", sizeof(short), (char*)&i_short,
	"int", sizeof(int), (char*)&i_int,
	"long", sizeof(long), (char*)&i_long,
	_ast_int8_str, sizeof(_ast_int8_t), (char*)&i_long_long,
};
static int int_size[] = { 1, 2, 4, 8 };
int main(void) {
	int t, s, m = 1, b = 1, w = 0;
	unsigned _ast_int8_t p;
	char buf[64];
	if (int_type[elementsof(int_type)-1].size <= 4) return 1;
	p = 0x12345678;
	p <<= 32;
	p |= 0x9abcdef0;
	sprintf(buf, "0x%016llx", p);
	if (strcmp(buf, "0x123456789abcdef0")) return 1;
	for (s = 0; s < elementsof(int_size); s++) {
		for (t = 0; t < elementsof(int_type) && int_type[t].size < int_size[s]; t++);
		if (t < elementsof(int_type)) {
			m = int_size[s];
			printf("#define _ast_int%d_t\t\t%s\n", m, int_type[t].name);
			if (m > 1) { if (*int_type[t].swap) w |= b; b <<= 1; }
		}
	}
	printf("#define _ast_intmax_t\t\t_ast_int%d_t\n", m);
	if (m == sizeof(long)) printf("#define _ast_intmax_long\t\t1\n");
	printf("#define _ast_intswap\t\t%d\n", w);
	printf("\n");
	return 0;
}

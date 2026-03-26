/* probe: ast-standards — GNU (glibc) or Android platform test (compile-only)
 * Requires: -D_typ_u_long=0 or -D_typ_u_long=1 */
#define _GNU_SOURCE	1
#define _FILE_OFFSET_BITS 64
#define _TIME_BITS 64
#include <limits.h>
#include <unistd.h>
#include <features.h>
#include <sys/types.h>
#include <wchar.h>
#if !__GLIBC__ && !__ANDROID_API__
#error not GNU or Android
#endif
int _do_these_compile_ = _POSIX_PATH_MAX & _SC_PAGESIZE;
#if _typ_u_long
u_long _test_dummy_;
#endif
int main(void)
{
	wchar_t _wchar_dummy_ = 0;
	wcwidth(_wchar_dummy_);
	return 0;
}

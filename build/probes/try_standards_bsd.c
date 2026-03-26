/* probe: ast-standards — BSD (Free, Net, Open) platform test (compile-only)
 * Requires: -D_typ_u_long=0 or -D_typ_u_long=1 */
#include <limits.h>
#include <unistd.h>
#include <sys/param.h>
#include <sys/types.h>
#include <wchar.h>
#if !(BSD && !__APPLE__ && !__MACH__ && !NeXTBSD)
#error not BSD
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

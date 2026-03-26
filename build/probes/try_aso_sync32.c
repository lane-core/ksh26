/* probe: ast-aso — GCC __sync atomics 32-bit model (compile+link)
 * Fallback when 64-bit model fails.
 * Requires: -I for FEATURE/common (workdir with FEATURE/ symlink)
 */
#include "FEATURE/common"
int main(void)
{
	uint32_t i = 0;
	uint16_t j = 0;
	uint8_t  l = 0;
	return __sync_fetch_and_add(&i,7)+__sync_fetch_and_add(&j,7)+__sync_fetch_and_add(&l,7);
}

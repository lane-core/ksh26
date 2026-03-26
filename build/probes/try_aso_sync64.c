/* probe: ast-aso — GCC __sync atomics 64-bit model (compile+link)
 * Requires: -I for FEATURE/common (workdir with FEATURE/ symlink)
 */
#include "FEATURE/common"
int main(void)
{
	uint64_t i = 0;
	uint32_t j = 0;
	uint16_t l = 0;
	uint8_t  m = 0;
	return __sync_fetch_and_add(&i,7)+__sync_fetch_and_add(&j,7)+__sync_fetch_and_add(&l,7)+__sync_fetch_and_add(&m,7);
}

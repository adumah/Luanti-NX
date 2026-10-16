/* newlib's getentropy() calls _getentropy_r(), which nothing on Horizon
 * implements. LuaJIT seeds its PRNG with getentropy(), so this object is
 * added to the LuaJIT archive (build.sh) and uses libnx's hardware CSPRNG. */
#include <errno.h>
#include <reent.h>
#include <stddef.h>

void randomGet(void *buf, size_t len); /* libnx; avoid <switch.h> here */

int _getentropy_r(struct _reent *r, void *buf, size_t len)
{
	if (len > 256) { /* POSIX limit for getentropy() */
		r->_errno = EIO;
		return -1;
	}
	randomGet(buf, len);
	return 0;
}

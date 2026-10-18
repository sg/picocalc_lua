#include <errno.h>

// SDK 2.3.0 no longer links nosys.specs, so the syscalls Lua's os.remove and os.rename reach through newlib need stubs here
int _unlink(const char* path) {
	(void)path;
	errno = ENOSYS;
	return -1;
}

int _link(const char* oldpath, const char* newpath) {
	(void)oldpath;
	(void)newpath;
	errno = ENOSYS;
	return -1;
}

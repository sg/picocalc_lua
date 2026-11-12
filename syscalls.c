#include <errno.h>

#include "cstack.h"

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

extern char __StackLimit, __StackOneTop;

char* lua_cstack_bottom(void) {
	return &__StackLimit - LUA_CSTACK_BELOW_SCRATCH;
}

char* lua_cstack_top(void) {
	return &__StackOneTop;
}

// the SDK's version lets the heap grow to __StackLimit, into memory Lua's stack writes to
void* _sbrk(int incr) {
	extern char end;
	static char* heap_end;

	if (!heap_end) heap_end = &end;
	if (heap_end + incr > lua_cstack_bottom()) return (void*)-1;

	char* previous = heap_end;
	heap_end += incr;
	return previous;
}

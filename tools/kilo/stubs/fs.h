#pragma once
#include "ff.h"
extern char *fs_error_strings[20];
int fs_exists(const char *path);
FRESULT fs_readline(FIL *fp, char **buffer, UINT *read);

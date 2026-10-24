#pragma once
#include <stdbool.h>
#include "ff.h"

extern char* fs_error_strings[20];

void fs_init();
void fs_poll();
int fs_mount();
bool fs_crc_checked();
int fs_exists(const char* path);
FRESULT fs_readline(FIL* fp, char** buffer, UINT* read);
FRESULT fs_writeline(FIL* fp, const char* line, UINT to_write, UINT* written);
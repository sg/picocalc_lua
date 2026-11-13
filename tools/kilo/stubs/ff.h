#pragma once
#include <stdio.h>
typedef unsigned int UINT;
typedef unsigned char BYTE;
typedef enum {
	FR_OK = 0, FR_DISK_ERR, FR_INT_ERR, FR_NOT_READY, FR_NO_FILE, FR_NO_PATH, FR_INVALID_NAME, FR_DENIED,
	FR_EXIST, FR_INVALID_OBJECT, FR_WRITE_PROTECTED, FR_INVALID_DRIVE, FR_NOT_ENABLED, FR_NO_FILESYSTEM,
	FR_MKFS_ABORTED, FR_TIMEOUT, FR_LOCKED, FR_NOT_ENOUGH_CORE, FR_TOO_MANY_OPEN_FILES, FR_INVALID_PARAMETER
} FRESULT;
typedef struct { FILE *f; long size; long written; } FIL;
#define FA_READ 0x01
#define FA_WRITE 0x02
#define FA_CREATE_ALWAYS 0x08
FRESULT f_open(FIL *fp, const char *path, BYTE mode);
FRESULT f_close(FIL *fp);
FRESULT f_write(FIL *fp, const void *buf, UINT len, UINT *written);
int f_eof(FIL *fp);
FRESULT f_unlink(const char *path);
FRESULT f_rename(const char *from, const char *to);
#define FF_MAX_LFN 255

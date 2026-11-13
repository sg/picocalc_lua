// Runs the firmware's editor (submodules/kilo/kilo.c) on the host: keys come from a script, the card is
// the host's files, the screen is kept as a grid, and its heap can be limited or made to fail.
//
//   kilo_host FILE KEYS
//
// FILE is edited in place, and "" starts the editor with no file name. KEYS is text typed as it stands,
// with newlines ignored and these in angle brackets: F1-F5 UP DOWN LEFT RIGHT S-LEFT S-RIGHT HOME END PGUP
// PGDN ENTER BS DEL ESC TAB C-TAB LT (a literal <), C-x for Ctrl with a letter, WAIT (six seconds pass)
// and NAME*count to repeat one.
//
// Environment:
//   KILO_HEAP=n         allocations fail once n bytes are held
//   KILO_FAIL_AT=n      the nth allocation fails, and KILO_FAIL_COUNT (default 2) in a row from there
//   KILO_DISK=n         a file takes n bytes and then the card is full
//   KILO_NORENAME=1     the card refuses to rename a file
//   KILO_SCREEN=path    the screen before the last key is written there as text, then as its colours
//   KILO_RAW=path       everything sent to the terminal is written there
//
// It prints the heap's peak, and exits 0, or 2 if the editor would not start, 3 if it would not quit
// (when the keys run out the harness presses ESC, then F2), 4 if it left memory allocated.

#include <ctype.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <time.h>

#include "keyboard.h"
#include "term.h"
#include "fs.h"
#include "kilo.h"

#define COLS 53
#define ROWS 40

/*** heap ***/

static size_t heap_used, heap_peak, heap_limit = SIZE_MAX;
static long alloc_calls, fail_at = -1, fail_count = 2;

// what newlib charges for a block: a 4 byte header, 8 byte alignment, 16 bytes at least
static size_t cost(size_t size) {
	size_t c = (size + 4 + 7) & ~(size_t)7;
	return c < 16 ? 16 : c;
}

void *test_realloc(void *p, size_t size) {
	size_t *old = p ? (size_t *)p - 2 : NULL;
	size_t had = old ? old[1] : 0;
	alloc_calls++;
	if (fail_at >= 0 && alloc_calls >= fail_at && alloc_calls < fail_at + fail_count) return NULL;
	if (heap_used - had + cost(size) > heap_limit) return NULL;
	size_t *now = malloc(size + 2 * sizeof(size_t));
	if (!now) abort();
	if (old) {
		memcpy(now + 2, old + 2, old[0] < size ? old[0] : size);
		free(old);
	}
	now[0] = size;
	now[1] = cost(size);
	heap_used += now[1] - had;
	if (heap_used > heap_peak) heap_peak = heap_used;
	return now + 2;
}

void *test_malloc(size_t size) {
	return test_realloc(NULL, size);
}

void test_free(void *p) {
	if (!p) return;
	size_t *old = (size_t *)p - 2;
	heap_used -= old[1];
	free(old);
}

/*** keys ***/

static char *keys;
static size_t key_pos;
static int repeat_left;
static input_event_t repeat_event;
static time_t now = 1000;
static int keys_ran_out;
static void snapshot(void);

static const struct { const char *name; int code; int mod; } named[] = {
	{"F1", KEY_F1, 0}, {"F2", KEY_F2, 0}, {"F3", KEY_F3, 0}, {"F4", KEY_F4, 0}, {"F5", KEY_F5, 0},
	{"UP", KEY_UP, 0}, {"DOWN", KEY_DOWN, 0}, {"LEFT", KEY_LEFT, 0}, {"RIGHT", KEY_RIGHT, 0},
	{"S-LEFT", KEY_LEFT, MOD_SHIFT}, {"S-RIGHT", KEY_RIGHT, MOD_SHIFT},
	{"HOME", KEY_HOME, 0}, {"END", KEY_END, 0}, {"PGUP", KEY_PAGEUP, 0}, {"PGDN", KEY_PAGEDOWN, 0},
	{"ENTER", KEY_ENTER, 0}, {"BS", KEY_BACKSPACE, 0}, {"DEL", KEY_DELETE, 0}, {"ESC", KEY_ESC, 0},
	{"TAB", KEY_TAB, 0}, {"C-TAB", KEY_TAB, MOD_CONTROL}, {"LT", '<', 0},
};

static int parse_named(const char *name, input_event_t *ev) {
	ev->state = KEY_STATE_PRESSED;
	for (size_t i = 0; i < sizeof named / sizeof named[0]; i++) {
		if (!strcmp(name, named[i].name)) {
			ev->code = named[i].code;
			ev->modifiers = named[i].mod;
			return 1;
		}
	}
	if (!strncmp(name, "C-", 2) && isalpha((unsigned char)name[2]) && !name[3]) {
		ev->code = name[2];
		ev->modifiers = MOD_CONTROL;
		return 1;
	}
	return 0;
}

input_event_t keyboard_wait_ex(bool nomod, bool onlypressed) {
	input_event_t ev = {KEY_STATE_PRESSED, 0, 0};
	(void)nomod;
	(void)onlypressed;
	snapshot();
	if (repeat_left > 0) {
		repeat_left--;
		return repeat_event;
	}
	for (;;) {
		char c = keys[key_pos];
		if (!c) {
			// a failed allocation can leave a script short of its own quit, in a prompt or in mark mode
			if (++keys_ran_out > 8) {
				fprintf(stderr, "the editor would not quit\n");
				exit(3);
			}
			ev.code = (keys_ran_out == 1) ? KEY_ESC : KEY_F2;
			return ev;
		}
		key_pos++;
		if (c == '\n' || c == '\r') continue;
		if (c != '<') {
			ev.code = (unsigned char)c;
			return ev;
		}
		char name[32];
		size_t n = 0;
		while (keys[key_pos] && keys[key_pos] != '>' && n < sizeof name - 1) name[n++] = keys[key_pos++];
		name[n] = '\0';
		if (keys[key_pos] == '>') key_pos++;
		int count = 1;
		char *star = strchr(name, '*');
		if (star) {
			*star = '\0';
			count = atoi(star + 1);
		}
		if (!strcmp(name, "WAIT")) {
			now += 6 * count;
			continue;
		}
		if (!parse_named(name, &ev)) {
			fprintf(stderr, "unknown key <%s>\n", name);
			exit(1);
		}
		if (count < 1) continue;
		repeat_event = ev;
		repeat_left = count - 1;
		return ev;
	}
}

void keyboard_flush() {}
int get_battery(bool *charging) { (void)charging; return 87; }
time_t test_time(time_t *t) { (void)t; return now; }

/*** screen ***/

static char cell[ROWS][COLS];
static char tint[ROWS][COLS];
static char shot[2][ROWS][COLS];
static int cur_x, cur_y, fg = 39, inverse;
static int esc_state;
static char esc_buf[32];
static int esc_len;
static FILE *raw;

static char tint_of(void) {
	char t = '.';
	switch (fg) {
		case 36: t = 'c'; break;
		case 90: t = 'k'; break;
		case 91: t = 'r'; break;
		case 92: t = 'g'; break;
		case 93: t = 'y'; break;
		case 94: t = 'b'; break;
		case 95: t = 'm'; break;
		case 37: case 39: t = '.'; break;
		default: t = '?';
	}
	if (inverse) t = (t == '.') ? '#' : toupper(t);
	return t;
}

static void clear_from(int y, int x) {
	for (; x < COLS; x++) {
		cell[y][x] = ' ';
		tint[y][x] = '.';
	}
}

static void put(char c) {
	if (cur_x >= COLS) {
		cur_x = 0;
		cur_y++;
	}
	if (cur_y >= ROWS) return;
	cell[cur_y][cur_x] = c;
	tint[cur_y][cur_x] = tint_of();
	cur_x++;
}

static void csi(char final) {
	esc_buf[esc_len] = '\0';
	if (final == 'H') {
		int r = 1, c = 1;
		sscanf(esc_buf, "%d;%d", &r, &c);
		cur_y = r - 1;
		cur_x = c - 1;
	} else if (final == 'K') {
		if (cur_y < ROWS) clear_from(cur_y, cur_x);
	} else if (final == 'J') {
		for (int y = 0; y < ROWS; y++) clear_from(y, 0);
	} else if (final == 'm') {
		char *p = esc_buf;
		if (!*p) { fg = 39; inverse = 0; }
		while (*p) {
			int a = strtol(p, &p, 10);
			if (a == 0) { fg = 39; inverse = 0; }
			else if (a == 7) inverse = 1;
			else if (a == 27) inverse = 0;
			else if ((a >= 30 && a <= 39) || (a >= 90 && a <= 97)) fg = a;
			if (*p == ';') p++;
		}
	}
}

ssize_t test_write(int fd, const void *buf, size_t len) {
	(void)fd;
	if (raw) fwrite(buf, 1, len, raw);
	for (size_t i = 0; i < len; i++) {
		char c = ((const char *)buf)[i];
		if (esc_state == 0) {
			if (c == 27) esc_state = 1;
			else if (c == '\n') { cur_x = 0; cur_y++; }
			else if (c == '\t') { put(' '); put(' '); }
			else if (c >= 32 && c < 127) put(c);
		} else if (esc_state == 1) {
			esc_state = (c == '[') ? 2 : 0;
			esc_len = 0;
		} else if (isalpha((unsigned char)c)) {
			csi(c);
			esc_state = 0;
		} else if (esc_len < (int)sizeof esc_buf - 1) {
			esc_buf[esc_len++] = c;
		}
	}
	return len;
}

// the editor clears the screen as it leaves, so what is kept is the screen as each key was awaited
static void snapshot(void) {
	memcpy(shot[0], cell, sizeof cell);
	memcpy(shot[1], tint, sizeof tint);
}

static void dump_screen(const char *path) {
	FILE *f = fopen(path, "w");
	if (!f) return;
	for (int pass = 0; pass < 2; pass++) {
		for (int y = 0; y < ROWS; y++) {
			const char *line = shot[pass][y];
			int end = COLS;
			while (end > 0 && line[end - 1] == (pass ? '.' : ' ')) end--;
			fwrite(line, 1, end, f);
			fputc('\n', f);
		}
	}
	fclose(f);
}

void term_clear() { test_write(1, "\x1b[2J\x1b[H", 7); }
int term_get_width() { return COLS; }
int term_get_height() { return ROWS; }
int term_get_x() { return cur_x; }
int term_get_y() { return cur_y; }
void term_set_blinking_cursor(bool enabled) { (void)enabled; }

/*** card ***/

static long disk_limit = -1;
static int no_rename;

char *fs_error_strings[20] = {
	"Succeeded", "disk error", "assertion failed", "not ready", "no file", "no path", "invalid name",
	"denied", "exists", "invalid object", "write protected", "invalid drive", "not enabled",
	"no filesystem", "mkfs aborted", "timeout", "locked", "Not enough memory", "too many open files",
	"invalid parameter",
};

int fs_exists(const char *path) {
	return access(path, F_OK) == 0;
}

FRESULT f_open(FIL *fp, const char *path, BYTE mode) {
	fp->f = fopen(path, (mode & FA_CREATE_ALWAYS) ? "w+b" : "rb");
	if (!fp->f) return FR_NO_FILE;
	struct stat st;
	fstat(fileno(fp->f), &st);
	fp->size = st.st_size;
	fp->written = 0;
	return FR_OK;
}

FRESULT f_close(FIL *fp) {
	fclose(fp->f);
	return FR_OK;
}

FRESULT f_write(FIL *fp, const void *buf, UINT len, UINT *written) {
	UINT n = len;
	if (disk_limit >= 0 && fp->written + (long)n > disk_limit) n = disk_limit - fp->written;
	*written = fwrite(buf, 1, n, fp->f);
	fp->written += *written;
	return FR_OK;
}

int f_eof(FIL *fp) {
	return ftell(fp->f) >= fp->size;
}

FRESULT f_unlink(const char *path) {
	if (remove(path) == 0) return FR_OK;
	return errno == ENOENT ? FR_NO_FILE : FR_DENIED;
}

// as FatFs has it, a file is not renamed over another
FRESULT f_rename(const char *from, const char *to) {
	if (no_rename) return FR_DENIED;
	if (access(to, F_OK) == 0) return FR_EXIST;
	return rename(from, to) == 0 ? FR_OK : FR_NO_FILE;
}

// as drivers/fs.c has it: the line is measured, then read into a block of exactly its size
FRESULT fs_readline(FIL *fp, char **buffer, UINT *read) {
	if (*buffer) {
		test_free(*buffer);
		*buffer = NULL;
	}
	*read = 0;
	if (f_eof(fp)) return FR_OK;

	long start = ftell(fp->f);
	int c = 0;
	while (c != '\n' && !f_eof(fp)) c = fgetc(fp->f);
	UINT len = ftell(fp->f) - start;
	if (c == '\n') len--;
	fseek(fp->f, start, SEEK_SET);

	*buffer = test_malloc(len + 1);
	if (!*buffer) return FR_NOT_ENOUGH_CORE;
	*read = fread(*buffer, 1, len, fp->f);
	(*buffer)[*read] = '\0';
	if (c == '\n') fgetc(fp->f);
	return FR_OK;
}

/*** lua ***/

struct lua_State { int unused; };

int lua_gc(lua_State *L, int what, ...) { (void)L; (void)what; return 0; }
int lua_getglobal(lua_State *L, const char *name) { (void)L; (void)name; return 0; }
int lua_pcall(lua_State *L, int nargs, int nresults, int msgh) { (void)L; (void)nargs; (void)nresults; (void)msgh; return 0; }
const char *lua_tostring(lua_State *L, int idx) { (void)L; (void)idx; return ""; }
int luaL_dofile(lua_State *L, const char *filename) { (void)L; (void)filename; return 0; }
void lua_pre_script(lua_State *L) { (void)L; }
void lua_post_script(lua_State *L) { (void)L; }

/*** main ***/

static long env_long(const char *name, long fallback) {
	const char *v = getenv(name);
	return v ? atol(v) : fallback;
}

int main(int argc, char **argv) {
	if (argc != 3) {
		fprintf(stderr, "usage: %s FILE KEYS\n", argv[0]);
		return 1;
	}
	FILE *f = fopen(argv[2], "rb");
	if (!f) {
		perror(argv[2]);
		return 1;
	}
	fseek(f, 0, SEEK_END);
	long size = ftell(f);
	rewind(f);
	keys = calloc(size + 1, 1);
	if (fread(keys, 1, size, f) != (size_t)size) return 1;
	fclose(f);

	long heap = env_long("KILO_HEAP", -1);
	if (heap >= 0) heap_limit = heap;
	fail_at = env_long("KILO_FAIL_AT", -1);
	fail_count = env_long("KILO_FAIL_COUNT", 2);
	disk_limit = env_long("KILO_DISK", -1);
	no_rename = getenv("KILO_NORENAME") != NULL;
	if (getenv("KILO_RAW")) raw = fopen(getenv("KILO_RAW"), "wb");
	setvbuf(stdout, NULL, _IONBF, 0);
	for (int y = 0; y < ROWS; y++) clear_from(y, 0);

	struct lua_State L;
	int status = 0;
#ifdef KILO_OLD
	start_editor(&L, argv[1]);
#else
	const char *err = start_editor(&L, argv[1]);
	if (err) {
		fprintf(stderr, "cannot edit: %s\n", err);
		status = 2;
	}
#endif
	if (raw) fclose(raw);
	if (getenv("KILO_SCREEN")) dump_screen(getenv("KILO_SCREEN"));
	fprintf(stderr, "heap peak %zu bytes in %ld allocations\n", heap_peak, alloc_calls);
	if (keys_ran_out) fprintf(stderr, "the keys ran out, so the harness pressed ESC and F2\n");
	if (heap_used) {
		fprintf(stderr, "%zu bytes were left allocated\n", heap_used);
		status = 4;
	}
	free(keys);
	return status;
}

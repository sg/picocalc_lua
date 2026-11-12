#include "term.h"

#include "pico/stdlib.h"
#include "pico/stdio.h"
#include "pico/stdio/driver.h"
#include <stdlib.h>
#include <string.h>

#include "lcd.h"
#include "keyboard.h"

stdio_driver_t stdio_picocalc;
static void (*chars_available_callback)(void *) = NULL;
static void *chars_available_param = NULL;
static repeating_timer_t cursor_timer;

static void set_chars_available_callback(void (*fn)(void *), void *param) {
	chars_available_callback = fn;
	chars_available_param = param;
}

// Function to be called when characters become available
void chars_available_notify(void) {
	if (chars_available_callback) {
		chars_available_callback(chars_available_param);
	}
}

void stdio_picocalc_init() {
	keyboard_set_key_available_callback(chars_available_notify);
	stdio_set_driver_enabled(&stdio_picocalc, true);
}

void stdio_picocalc_deinit() {
	stdio_set_driver_enabled(&stdio_picocalc, false);
}

const static unsigned short palette[16] = {
	RGB(  0,   0,   0), // 0 black
	RGB(194,  54,  33), // 1 red
	RGB( 37, 188,  36), // 2 green
	RGB(173, 173,  39), // 3 yellow
	RGB( 73,  46, 225), // 4 blue
	RGB(211,  56, 211), // 5 magenta
	RGB( 51, 187, 200), // 6 cyan
	RGB(203, 204, 205), // 7 white
	// high intensity
	RGB( 85,  85,  85), // 8 black
	RGB(255,  85,  85), // 9 red
	RGB( 85, 255,  85), // a green
	RGB(255, 255,  85), // b yellow
	RGB(85,   85, 255), // c blue
	RGB(255,  85, 255), // d magenta
	RGB( 85, 255, 255), // e cyan
	RGB(255, 255, 255), // f white
};

enum {
	AnsiNone,
	AnsiEscape,
	AnsiBracket,
};

typedef struct {
	int state;
	int x, y, len;
	int ccol, crow;
	u16 fg, bg;
	char stack[ANSI_STACK_SIZE];
	int stack_size;
	int scroll;
	bool cursor_enabled;
	bool cursor_visible;
	bool cursor_manual;
	bool c_inverse;
	bool c_bold;
} ansi_t;

static ansi_t ansi = {
	.state=AnsiNone,
	.x=0, .y=0,
	.fg=palette[DEFAULT_FG],
	.bg=palette[DEFAULT_BG],
	.stack={0},
	.stack_size=0,
	.cursor_enabled=false,
	.c_inverse=false,
	.c_bold=false,
};

static int ansi_len_to_col(int len) {
	return (ansi.x + len) % font.term_width;
}

static int ansi_len_to_row(int len) {
	return ansi.y + (len + ansi.x) / font.term_width;
}

// Shadow of every visible cell: direct LCD mode cannot read pixels back, so this is the only
// way to erase the cursor without destroying the glyph underneath it.
typedef struct __attribute__((packed)) {
	char c;
	u16 fg, bg;
} cell_t;

static cell_t* shadow = NULL;
static int shadow_cols = 0, shadow_rows = 0;
static volatile bool blink_pending = false;

static void shadow_blank(int row, int count, int col_from) {
	for (int r = row; r < row + count; r++) {
		if (r < 0 || r >= shadow_rows) continue;
		cell_t* line = shadow + r * shadow_cols;
		for (int c = col_from; c < shadow_cols; c++) line[c] = (cell_t){ ' ', ansi.fg, ansi.bg };
	}
}

// Sized from the font, so it is (re)allocated lazily whenever the font changes
static bool shadow_ready() {
	if (font.term_width == 0 || font.term_height == 0) return false;
	if (shadow && shadow_cols == font.term_width && shadow_rows == font.term_height) return true;
	free(shadow);
	shadow_cols = font.term_width;
	shadow_rows = font.term_height;
	shadow = malloc(sizeof(cell_t) * shadow_cols * shadow_rows);
	if (shadow) shadow_blank(0, shadow_rows, 0);
	return shadow != NULL;
}

static void shadow_set(int col, int abs_row, u16 fg, u16 bg, char c) {
	int row = abs_row - ansi.scroll;
	if (!shadow_ready() || col < 0 || col >= shadow_cols || row < 0 || row >= shadow_rows) return;
	shadow[row * shadow_cols + col] = (cell_t){ c, fg, bg };
}

static void shadow_blank_span(int abs_row, int col_from) {
	if (shadow_ready()) shadow_blank(abs_row - ansi.scroll, 1, col_from < 0 ? 0 : col_from);
}

// Viewport moved down by delta rows, so the shadow must follow what is on screen
static void shadow_shift(int delta) {
	if (!shadow_ready()) return;
	if (delta >= shadow_rows || -delta >= shadow_rows) { shadow_blank(0, shadow_rows, 0); return; }
	size_t line = sizeof(cell_t) * shadow_cols;
	if (delta > 0) {
		memmove(shadow, shadow + delta * shadow_cols, (shadow_rows - delta) * line);
		shadow_blank(shadow_rows - delta, delta, 0);
	} else if (delta < 0) {
		memmove(shadow + (-delta) * shadow_cols, shadow, (shadow_rows + delta) * line);
		shadow_blank(0, -delta, 0);
	}
}

void term_scroll(int lines) {
	if (lines != ansi.scroll) {
		int scroll_delta = lines - ansi.scroll;
		int buffer_mode = lcd_get_buffer_mode();
		if (buffer_mode != LCD_BUFFERMODE_DIRECT) {
			// Buffer mode: software scroll actually shifts pixels,
			// so we need to adjust ansi.y to stay in valid range
			lcd_scroll(scroll_delta * font.glyph_height);
			// Adjust Y position since content has been shifted
			ansi.y -= scroll_delta;
			ansi.crow -= scroll_delta;
			// Reset scroll tracking since content is actually shifted
			ansi.scroll = 0;
		} else {
			// Direct mode: use hardware scroll (virtual scroll)
			ansi.scroll = lines;
			term_erase_line(lines + font.term_height);
			lcd_scroll(lines * font.glyph_height);
		}
		shadow_shift(scroll_delta);
	}
}

void term_clear() {
	ansi.x = ansi.y = ansi.len = 0;
	lcd_clear();
	lcd_scroll(0);
	ansi.scroll = 0;
	if (shadow_ready()) shadow_blank(0, shadow_rows, 0);
	// nothing is left on screen to erase, so the next blink simply draws at the new position
	ansi.cursor_visible = false;
}

static void term_draw_char(int x, int y, u16 fg, u16 bg, char c) {
	y %= lcd_current_height;
	lcd_draw_char(x, y, fg, bg, c);
	if (y > lcd_current_height - font.glyph_height)
		lcd_draw_char(x, y - lcd_current_height, fg, bg, c);
}

static void term_erase_char(int x, int y, u16 bg) {
	y %= lcd_current_height;
	lcd_fill(bg, x, y, font.glyph_width, font.glyph_height);
	if (y > lcd_current_height - font.glyph_height)
		lcd_fill(bg, x, y - lcd_current_height, font.glyph_width, font.glyph_height);
}

static void term_put_cell(int col, int abs_row, u16 fg, u16 bg, char c) {
	term_draw_char(col * font.glyph_width, abs_row * font.glyph_height, fg, bg, c);
	shadow_set(col, abs_row, fg, bg, c);
}

static void term_blank_cell(int col, int abs_row, u16 bg) {
	term_erase_char(col * font.glyph_width, abs_row * font.glyph_height, bg);
	shadow_set(col, abs_row, ansi.fg, bg, ' ');
}

void term_erase_line(int y) {
	shadow_blank_span(y, 0);
	y = (y * font.glyph_height) % lcd_current_height;
	lcd_fill(ansi.bg, 0, y, LCD_WIDTH, font.glyph_height);
	if (y > lcd_current_height - font.glyph_height)
		lcd_fill(ansi.bg, 0, y - lcd_current_height, LCD_WIDTH, font.glyph_height);
}

void term_erase_current_line() {
	shadow_blank_span(ansi.y, 0);
	int y = (ansi.y * font.glyph_height) % lcd_current_height;
	lcd_fill(ansi.bg, 0, y, LCD_WIDTH, font.glyph_height);
	if (y > lcd_current_height - font.glyph_height)
		lcd_fill(ansi.bg, 0, y - lcd_current_height, LCD_WIDTH, font.glyph_height);
}

void term_erase_from_cursor() {
	shadow_blank_span(ansi.y, ansi.x);
	int x = ansi.x * font.glyph_width;
	int y = (ansi.y * font.glyph_height) % lcd_current_height;
	lcd_fill(ansi.bg, x, y, LCD_WIDTH - x, font.glyph_height);
	if (y > lcd_current_height - font.glyph_height)
		lcd_fill(ansi.bg, x, y - lcd_current_height, LCD_WIDTH - x, font.glyph_height);
}

// The panel cannot be read back, so this is how a screen drawn in direct mode gets
// reproduced inside a freshly enabled framebuffer.
bool term_redraw() {
	if (!shadow_ready()) return false;
	// the shadow follows the viewport, which sits at the hardware scroll offset only in direct mode
	int base = lcd_get_buffer_mode() == LCD_BUFFERMODE_DIRECT ? ansi.scroll : 0;
	for (int row = 0; row < shadow_rows; row++) {
		cell_t* line = shadow + row * shadow_cols;
		int y = (base + row) * font.glyph_height;
		for (int col = 0; col < shadow_cols; col++) {
			term_draw_char(col * font.glyph_width, y, line[col].fg, line[col].bg, line[col].c);
		}
	}
	return true;
}

// Redraws the cursor cell from the shadow (inverted while on) so the glyph survives every blink;
// without a shadow it falls back to the old one-pixel bar.
static void cursor_paint(bool on) {
	int x = ansi.ccol * font.glyph_width, y = ansi.crow * font.glyph_height;
	int row = ansi.crow - ansi.scroll;
	if (!shadow_ready()) {
		lcd_fill(on ? ansi.fg : ansi.bg, x, y, 1, font.glyph_height - 1);
		return;
	}
	if (ansi.ccol < 0 || ansi.ccol >= shadow_cols || row < 0 || row >= shadow_rows) return;
	cell_t cell = shadow[row * shadow_cols + ansi.ccol];
	if (on) term_draw_char(x, y, cell.bg, cell.fg, cell.c);
	else term_draw_char(x, y, cell.fg, cell.bg, cell.c);
}

static void draw_cursor() {
	if (ansi.cursor_enabled && !ansi.cursor_visible) {
		ansi.ccol = ansi_len_to_col(ansi.len);
		ansi.crow = ansi_len_to_row(ansi.len);
		cursor_paint(true);
		ansi.cursor_visible = true;
	}
}

static void erase_cursor() {
	if (ansi.cursor_enabled && ansi.cursor_visible) {
		cursor_paint(false);
		ansi.cursor_visible = false;
	}
}

// Fires in the core 0 timer IRQ, so it only flags the blink; the Lua core draws it from
// term_cursor_service() to keep cursor traffic ordered with everything else the terminal draws.
static bool on_cursor_timer(repeating_timer_t *rt) {
	blink_pending = true;
	return true;
}

void term_cursor_service() {
	if (!blink_pending) return;
	blink_pending = false;
	if (!ansi.cursor_enabled) return;
	if (!ansi.cursor_manual && ansi.cursor_visible) {
		erase_cursor();
	} else {
		ansi.cursor_manual = false;
		draw_cursor();
	}
}

bool term_get_blinking_cursor() {
	return ansi.cursor_enabled;
}

void term_set_blinking_cursor(bool enabled) {
	if (enabled && !ansi.cursor_enabled) {
		ansi.cursor_manual = true;
		ansi.cursor_enabled = true;
		draw_cursor();
		add_repeating_timer_ms(CURSOR_BLINK_MS, on_cursor_timer, NULL, &cursor_timer);
	} else if (!enabled && ansi.cursor_enabled) {
		erase_cursor();
		ansi.cursor_enabled = false;
		cancel_repeating_timer(&cursor_timer);
		blink_pending = false;
	}
}

int term_get_x() {
	return ansi.x;
}
int term_get_y() {
	// return viewport-relative Y 
	// (subtract scroll offset)
	return ansi.y - ansi.scroll;
}

int term_get_width() {
	return font.term_width;
}

int term_get_height() {
	return font.term_height;
}

void term_set_pos(int x, int y) {
	ansi.cursor_manual = true;
	erase_cursor();
	if (x >= 0 && x < font.term_width) ansi.x = x;
	// convert viewport-relative Y to absolute Y 
	// (add scroll offset)
	if (y >= 0 && y < font.term_height) ansi.y = y + ansi.scroll;
	draw_cursor();
}

u16 term_get_fg() {
	return ansi.fg;
}
u16 term_get_bg() {
	return ansi.bg;
}

void term_set_fg(u16 color) {
	ansi.fg = color;
}
void term_set_bg(u16 color) {
	ansi.bg = color;
}

void term_blit(const char* text, const char* fg, const char* bg) {
	u16 pfg = ansi.fg, pbg = ansi.bg;
	const char *lfg = fg, *lbg = bg;
	while(*text) {
		if (*lfg >= '0' && *lfg <= '9') pfg = palette[*lfg - '0'];
		else if (*lfg >= 'a' && *lfg <= 'f') pfg = palette[*lfg - 'a' + 10];
		else if (*lfg >= 'A' && *lfg <= 'F') pfg = palette[*lfg - 'A' + 10];
		if (*lbg >= '0' && *lbg <= '9') pbg = palette[*lbg - '0'];
		else if (*lbg >= 'a' && *lbg <= 'f') pbg = palette[*lbg - 'a' + 10];
		else if (*lbg >= 'A' && *lbg <= 'F') pbg = palette[*lbg - 'A' + 10];
		term_put_cell(ansi.x, ansi.y, pfg, pbg, *text);
		ansi.x += 1;
		if (ansi.x > font.term_width) return;
		text ++;
		lfg ++; if (!*lfg) lfg = fg;
		lbg ++; if (!*lbg) lbg = bg;
	}
}

static inline void should_scroll() {
	if (ansi.x >= font.term_width) {
		ansi.x = 0;
		ansi.y += 1;
	}
	// ansi.y counts from the top of everything scrolled so far, so only its row within the viewport
	// tells whether the cursor has run off the bottom; testing ansi.y itself moved the view to any row written to
	if (ansi.y - ansi.scroll >= font.term_height) {
		term_scroll(ansi.y - (font.term_height - 1));
	}
}

static void out_char(char c) {
	u16 fg, bg;
	if (ansi.c_inverse) {
		fg = ansi.bg;
		bg = ansi.fg;
	} else {
		fg = ansi.fg;
		bg = ansi.bg;
	}
	
	if (c == '\n') {
		ansi.x = 0;
		ansi.y += 1;
		//term_erase_line(ansi.y);
		should_scroll();
	} else if (c == '\b') ansi.x -= 1;
	//else if (c == '\r') ansi.x = 0;
	else {
		if (c == '\t') c = ' ';
		if (c >= 32 && c < 127) {
			should_scroll();
			term_put_cell(ansi.x, ansi.y, fg, bg, c);
			ansi.x += 1;
		}
	}
}

void stdio_picocalc_out_chars(const char *buf, int length) {
	while (length > 0) {
		if (ansi.state == AnsiNone) {
			if (*buf == 27 || *buf == '\x1b') ansi.state = AnsiEscape;
			else if (*buf == '\t') {
				out_char(*buf); out_char(*buf);
			}
			else out_char(*buf);
		} else if (ansi.state == AnsiEscape) {
			if (*buf == '[') ansi.state = AnsiBracket;
			else ansi.state = AnsiNone;
			ansi.stack_size = 0;
		} else if (ansi.state == AnsiBracket) {
			ansi.stack[ansi.stack_size] = 0;
			int a = 0, b = 0, semicolon = 0;
			//lcd_printf(0, 39 * 8, 0xffff, 0, "buf = '%c' stack = %s         ", *buf, ansi.stack);
			//keyboard_wait();
			switch (*buf) {
				case 'A': ansi.y -= atoi(ansi.stack); ansi.state = AnsiNone; break; // cursor up
				case 'B': ansi.y += atoi(ansi.stack); ansi.state = AnsiNone; break; // cursor down
				case 'C': ansi.x += atoi(ansi.stack); ansi.state = AnsiNone; break; // cursor right
				case 'D': ansi.x -= atoi(ansi.stack); ansi.state = AnsiNone; break; // cursor left
				case 'J': term_clear(); ansi.state = AnsiNone; break; // erase display
				case 'K':	term_erase_from_cursor(); ansi.state = AnsiNone; break;
				case 'm':
					if (ansi.stack_size == 0) {
						ansi.fg = palette[DEFAULT_FG];
						ansi.bg = palette[DEFAULT_BG];
						ansi.c_inverse = false;
						ansi.c_bold = false;
					} else {
						while (semicolon <= ansi.stack_size-1) {
							a = atoi(ansi.stack + semicolon);
							b = a % 10;
							if (a == 0) { // reset all
								ansi.fg = palette[DEFAULT_FG];
								ansi.bg = palette[DEFAULT_BG];
								ansi.c_inverse = false;
								ansi.c_bold = false;
							}
							else if (a == 7)  ansi.c_inverse = true;
							else if (a == 27) ansi.c_inverse = false;
							else if (a == 1)  ansi.c_bold = true;
							else if (a == 22) ansi.c_bold = false;
							else if (a >= 30 && a <= 39) { // dim foreground
								if (b == 9) ansi.fg = palette[DEFAULT_FG];
								else if (b <= 7) ansi.fg = palette[b + ansi.c_bold * 8];
							}
							else if (a >= 40 && a <= 49) { // dim background
								if (b == 9) ansi.bg = palette[DEFAULT_BG];
								else if (b <= 7) ansi.bg = palette[b + ansi.c_bold * 8];
							}
							else if (a >= 90 && a <= 97) { // bright foreground
								ansi.fg = palette[b + 8];
							}
							else if (a >= 100 && a <= 107) { // bright background
								ansi.bg = palette[b + 8];
							}
							while (semicolon < ansi.stack_size-1 && ansi.stack[semicolon] != ';') semicolon++;
							semicolon++;
						}
					}
					ansi.state = AnsiNone;
					break;
				case 'H':
					if (ansi.stack_size == 0) {
						term_scroll(0);
						term_set_pos(0, 0);
					} else {
						a = atoi(ansi.stack);
						while (semicolon < ansi.stack_size && ansi.stack[semicolon] != ';') semicolon++;
						if (semicolon < ansi.stack_size - 1) b = atoi(ansi.stack + semicolon + 1);
						if (a > 0 && b > 0) {
							term_set_pos(b-1, a-1);
						}
					}
					ansi.state = AnsiNone;
					break;
				case 'l':
				case 'h':
					if (strncmp(ansi.stack, "?25", 3) == 0) {
						if (*buf == 'l') term_set_blinking_cursor(false);
						if (*buf == 'h') term_set_blinking_cursor(true);
					}
					ansi.state = AnsiNone;
					break;
				default:
					if (ansi.stack_size < ANSI_STACK_SIZE) ansi.stack[ansi.stack_size++] = *buf;
					else ansi.state = AnsiNone;
			}
		}
		buf++;
		length--;
	}
}

static int stdio_picocalc_in_chars(char *buf, int length) {
	term_cursor_service();
	input_event_t event = keyboard_poll(false);
	if (event.state == KEY_STATE_PRESSED && event.code > 0) {
		if (event.modifiers & MOD_CONTROL && event.code >= 'a' && event.code < 'z') {
			*buf = event.code - 'a' + 1;
		} else {
			*buf = event.code;
		}
		//stdio_picocalc_out_chars(buf, 1);
		return 1;
	}
	return 0;
}

stdio_driver_t stdio_picocalc = {
	.out_chars = stdio_picocalc_out_chars,
	.in_chars = stdio_picocalc_in_chars,
	.set_chars_available_callback = set_chars_available_callback,
#if PICO_STDIO_ENABLE_CRLF_SUPPORT
	.crlf_enabled = true,
#endif
};

static void term_erase_input(int size) {
	for (int i = 0; i < size + 1; i++) term_blank_cell(ansi_len_to_col(i), ansi_len_to_row(i), ansi.bg);
}

// TODO: this should be less specialized
static void term_draw_input(char* buffer, int size, int cursor) {
	int last_row = ansi.y + (size + ansi.x) / font.term_width;
	if (last_row - ansi.scroll >= font.term_height) term_scroll(last_row - (font.term_height-1));
	for (int i = 0; i < size + 1; i++) {
		int col = ansi_len_to_col(i), row = ansi_len_to_row(i);
		if (i < size) term_put_cell(col, row, ansi.fg, ansi.bg, buffer[i]);
		else term_blank_cell(col, row, ansi.bg);
	}
}

static void history_save(history_t* history, int entry, char* text, int size) {
	if (entry >= 0 && entry < HISTORY_MAX) {
		if (history->buffer[entry] != NULL) free(history->buffer[entry]);
		history->buffer[entry] = strndup(text, size);
	}
}

// an entry is NULL where saving it ran out of memory, and then reads as empty
static int history_load(history_t* history, char* buffer) {
	const char* entry = history->buffer[history->current];
	int size = entry ? strlen(entry) : 0;
	if (entry) memcpy(buffer, entry, size);
	return size;
}

int term_readline(const char* prompt, char* buffer, int max_length, history_t* history) {
	int cursor = 0;
	int size = 0;

	buffer[size] = '\0';

	if (history) {
		history->current = 0;
		if (history->buffer[0] != NULL && history->buffer[0][0] != '\0') memmove(history->buffer + 1, history->buffer, 31 * sizeof(char*));
		history->buffer[0] = strdup(buffer);
	}

	stdio_picocalc_out_chars(prompt, strlen(prompt));

	bool cursor_was_enabled = ansi.cursor_enabled;
	term_set_blinking_cursor(true);

	while (true) {
		input_event_t event = keyboard_wait();
		if (event.state == KEY_STATE_PRESSED) {
			if (event.code == 'c' && event.modifiers & MOD_CONTROL) {
				term_erase_input(size);
				size = cursor = 0;
			} else if (event.code == 'l' && event.modifiers & MOD_CONTROL) {
				term_clear();
				stdio_picocalc_out_chars(prompt, strlen(prompt));
			} else if (event.code == KEY_ENTER) {
				term_draw_input(buffer, size, -1);
				buffer[size] = '\0';
				ansi.x += size % font.term_width;
				ansi.y += size / font.term_width;
				stdio_picocalc_out_chars("\n", 1);
				if (history) history_save(history, 0, buffer, size);
				ansi.len = 0;
				term_set_blinking_cursor(cursor_was_enabled);
				return size;
			} else if (history && event.code == KEY_UP && history->current < 31 && history->buffer[history->current + 1] != NULL) {
				term_erase_input(size);
				history_save(history, history->current, buffer, size);
				history->current++;
				size = cursor = history_load(history, buffer);
			} else if (history && event.code == KEY_DOWN && history->current > 0) {
				term_erase_input(size);
				history_save(history, history->current, buffer, size);
				history->current--;
				size = cursor = history_load(history, buffer);
			} else if (event.code == KEY_LEFT) {
				if (event.modifiers & MOD_CONTROL) {
					while (cursor > 0 && buffer[cursor] != ' ') cursor--;
				} else if (cursor > 0) cursor -= 1;
			} else if (event.code == KEY_RIGHT) {
				if (event.modifiers & MOD_CONTROL) {
					while (cursor < size && buffer[cursor] != ' ') cursor++;
				} else if (cursor < size) cursor += 1;
			} else if (event.code == KEY_HOME) {
				cursor = 0;
			} else if (event.code == KEY_END) {
				cursor = size;
			} else if ((event.code == KEY_BACKSPACE && cursor > 0) || (event.code == KEY_DELETE && cursor < size)) {
				if (event.code == KEY_DELETE) cursor++;
				term_erase_input(size);
				cursor -= 1;
				size -= 1;
				memmove(buffer + cursor, buffer + cursor + 1, size - cursor);
			} else if (event.code >= 32 && event.code < 127) {
				if (size < max_length - 1) {
					if (cursor < size) {
						memmove(buffer + cursor + 1, buffer + cursor, size - cursor);
					}
					buffer[cursor] = event.code;
					size += 1;
					cursor += 1;
				}
			}
			if (cursor != ansi.len) {
				ansi.cursor_manual = true;
				erase_cursor();
			}
			term_draw_input(buffer, size, cursor);
			if (cursor != ansi.len) {
				ansi.len = cursor;
				draw_cursor();
			}
		}
	}
	term_set_blinking_cursor(cursor_was_enabled);
	return 0;
}

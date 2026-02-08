#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

#include "pico/stdlib.h"
#include "pico/multicore.h"
#include "pico/time.h"

#include "hardware/gpio.h"
#include "hardware/pio.h"
#include "hardware/clocks.h"
#include "st7789_lcd.pio.h"
#include "psram_spi.h"

#include "lcd.h"
#include "lcd_lut.h"
#include "default_font.h"
#include "fs.h"
#include "../pico_fatfs/fatfs/ff.h"

#define LCD_SCK 10
#define LCD_TX  11
#define LCD_RX  12
#define LCD_CS  13
#define LCD_DC  14
#define LCD_RST 15
#define LCD_PIO pio1
#define SERIAL_CLK_DIV 1.f

void(*lcd_draw_ptr) (u16*,int,int,int,int);
void(*lcd_fill_ptr) (u16,int,int,int,int);
void(*lcd_point_ptr) (u16,int,int);
void(*lcd_clear_ptr) (void);

psram_spi_inst_t psram_spi;
psram_spi_inst_t* async_spi_inst;

uint lcd_sm = 0;
uint lcd_offset;

uint8_t* framebuffer;
int framebuffer_mode;
int lcd_current_height;

#define LCD_TMPBUF_SIZE LCD_WIDTH*2
uint16_t lcd_tmpbuf[LCD_TMPBUF_SIZE];

static inline void lcd_set_dc_cs(bool dc, bool cs) {
	gpio_put_masked((1u << LCD_DC) | (1u << LCD_CS), !!dc << LCD_DC | !!cs << LCD_CS);
}

static inline void lcd_write_cmd(const uint8_t *cmd, size_t count) {
	st7789_lcd_wait_idle(LCD_PIO, lcd_sm);
	lcd_set_dc_cs(0, 0);
	st7789_lcd_put(LCD_PIO, lcd_sm, *cmd++);
	if (count >= 2) {
		st7789_lcd_wait_idle(LCD_PIO, lcd_sm);
		lcd_set_dc_cs(1, 0);
		for (size_t i = 0; i < count - 1; ++i)
			st7789_lcd_put(LCD_PIO, lcd_sm, *cmd++);
	}
	st7789_lcd_wait_idle(LCD_PIO, lcd_sm);
	lcd_set_dc_cs(0, 1);
}

static inline void lcd_write16(const uint16_t *data, size_t count) {
	uint16_t color;
	for (size_t i = 0; i < count; ++i) {
		color = *data++;
		st7789_lcd_put(LCD_PIO, lcd_sm, color >> 8);
		st7789_lcd_put(LCD_PIO, lcd_sm, color & 0xff);
	}
}

static inline void lcd_initcmd(const uint8_t *init_seq) {
	const uint8_t *cmd = init_seq;
	while (*cmd) {
		lcd_write_cmd(cmd + 2, *cmd);
		sleep_ms(*(cmd + 1) * 5);
		cmd += *cmd + 2;
	}
}

static void lcd_set_region(int x1, int y1, int x2, int y2) {
	lcd_set_dc_cs(0, 0);
	const uint8_t cmd1[] = {0x2A, (x1 >> 8), (x1 & 0xFF), (x2 >> 8), (x2 & 0xFF)};
	const uint8_t cmd2[] = {0x2B, (y1 >> 8), (y1 & 0xFF), (y2 >> 8), (y2 & 0xFF)};
	lcd_write_cmd(cmd1, 5);
	lcd_write_cmd(cmd2, 5);
	uint8_t cmd = 0x2c; // RAMWR
	lcd_write_cmd(&cmd, 1);
	busy_wait_us(1);
	lcd_set_dc_cs(1, 0);
}

void lcd_blank() {
	// Enter Sleep
	uint8_t cmd = 0x10;
	lcd_write_cmd(&cmd, 1);
}

void lcd_unblank() {
	// Exit Sleep
	uint8_t cmd = 0x11;
	lcd_write_cmd(&cmd, 1);
}

void lcd_on() {
	// Display on
	uint8_t cmd = 0x29;
	lcd_write_cmd(&cmd, 1);
}

void lcd_off() {
	// Display off
	uint8_t cmd = 0x29;
	lcd_write_cmd(&cmd, 1);
}

static inline void normalize_coords(int* x, int* y, int* width, int* height) {
	if (*y < 0) { *height += *y; *y = 0; }
	*y %= lcd_current_height;
	*x = (*x < 0 ? 0 : (*x >= LCD_WIDTH ? LCD_WIDTH : *x));
	*width = (*width < 0 ? 0 : (*x + *width >= LCD_WIDTH ? LCD_WIDTH - *x : *width));
	*height = (*height < 0 ? 0 : (*y + *height >= lcd_current_height ? lcd_current_height - *y : *height));
}

static void lcd_direct_draw(u16* pixels, int x, int y, int width, int height) {
	if (y < 0) { pixels -= y * width; height += y; y = 0; }
	// TODO: clip negative X as well
	normalize_coords(&x, &y, &width, &height);
	lcd_set_region(x, y, x + width - 1, y + height - 1);

	lcd_write16(pixels, width * height);

	st7789_lcd_wait_idle(LCD_PIO, lcd_sm);
	lcd_set_dc_cs(0, 1);
}

static void lcd_direct_fill(u16 color, int x, int y, int width, int height) {
	normalize_coords(&x, &y, &width, &height);
	lcd_set_region(x, y, x + width - 1, y + height - 1);
	
	for (size_t i = 0; i < width * height; ++i) {
		st7789_lcd_put(LCD_PIO, lcd_sm, color >> 8);
		st7789_lcd_put(LCD_PIO, lcd_sm, color & 0xff);
	}

	st7789_lcd_wait_idle(LCD_PIO, lcd_sm);
	lcd_set_dc_cs(0, 1);
}

static void lcd_direct_point(u16 color, int x, int y) {
	lcd_direct_fill(color, x, y, 1, 1);
}

static void lcd_direct_clear() {
	lcd_direct_fill(0, 0, 0, LCD_WIDTH, MEM_HEIGHT);
}

static void lcd_psram_draw(u16* pixels, int x, int y, int width, int height) {
	normalize_coords(&x, &y, &width, &height);

	int remain;
	for (uint32_t iy = y * LCD_WIDTH; iy < (y + height) * LCD_WIDTH; iy += LCD_WIDTH) {
		remain = width;
		for (uint32_t ix = x; ix < (x + width); ix+=10) {
			psram_write(&psram_spi, (iy + ix)<<1, (uint8_t*)pixels, (remain < 10 ? remain<<1 : 20));
			pixels += (remain < 10 ? remain : 10);
			remain -= 10;
		}
	}
}

static void lcd_psram_fill(u16 color, int x, int y, int width, int height) {
	normalize_coords(&x, &y, &width, &height);

	int remain;
	for (int i = 0; i < 10; i++) lcd_tmpbuf[i] = color;
	for (uint32_t iy = y * LCD_WIDTH; iy < (y + height) * LCD_WIDTH; iy += LCD_WIDTH) {
		remain = width;
		for (uint32_t ix = x; ix < (x + width); ix+=10) {
			psram_write(&psram_spi, (iy + ix)<<1, (uint8_t*)lcd_tmpbuf, (remain < 10 ? remain<<1 : 20));
			remain -= 10;
		}
	}
}

static void lcd_psram_point(u16 color, int x, int y) {
	if (x >= 0 && y >= 0 && x < LCD_WIDTH && y < LCD_HEIGHT)
		psram_write16(&psram_spi, (x + y * LCD_WIDTH)<<1, color);
}

static void lcd_psram_clear() {
	lcd_psram_fill(0, 0, 0, LCD_WIDTH, LCD_HEIGHT);
}

static void lcd_ram_draw(u16* pixels, int x, int y, int width, int height) {
	normalize_coords(&x, &y, &width, &height);

	for (uint32_t iy = y * LCD_WIDTH; iy < (y + height) * LCD_WIDTH; iy += LCD_WIDTH) {
		for (uint32_t ix = x; ix < (x + width); ix++) {
			framebuffer[iy+ix] = lcd_to8[*pixels++];
		}
	}
}

static void lcd_ram_fill(u16 color, int x, int y, int width, int height) {
	normalize_coords(&x, &y, &width, &height);

	for (uint32_t iy = y * LCD_WIDTH; iy < (y + height) * LCD_WIDTH; iy += LCD_WIDTH) {
		memset(framebuffer + x + iy, lcd_to8[color], width);
	}
}

static void lcd_ram_point(u16 color, int x, int y) {
	if (x >= 0 && y >= 0 && x < LCD_WIDTH && y < LCD_HEIGHT)
		framebuffer[(x + y * LCD_WIDTH)] = lcd_to8[color];
}

static void lcd_ram_clear() {
	memset(framebuffer, 0, LCD_WIDTH * LCD_HEIGHT);
}

void lcd_buffer_blit_local() {
	if (framebuffer_mode == LCD_BUFFERMODE_DIRECT) return;
	
	lcd_set_region(0, 0, 319, 319);

	if (framebuffer_mode == LCD_BUFFERMODE_PSRAM) {
		for (int y = 0; y < LCD_HEIGHT * LCD_WIDTH; y += LCD_TMPBUF_SIZE) {
			for (int x = 0; x < LCD_TMPBUF_SIZE; x+=10) {
				psram_read(&psram_spi, (x+y)<<1, (uint8_t*)(lcd_tmpbuf + x), 20);
			}
			lcd_write16(lcd_tmpbuf, LCD_TMPBUF_SIZE);
		}
	} else if (framebuffer_mode == LCD_BUFFERMODE_RAM) {
		uint16_t color;
		for (size_t count = 0; count < LCD_WIDTH * LCD_HEIGHT; count++) {
			color = lcd_to16[framebuffer[count]];
			st7789_lcd_put(LCD_PIO, lcd_sm, color >> 8);
			st7789_lcd_put(LCD_PIO, lcd_sm, color & 0xff);
		}
	}

	st7789_lcd_wait_idle(LCD_PIO, lcd_sm);
	lcd_set_dc_cs(0, 1);
}

void lcd_draw_local(u16* pixels, int x, int y, int width, int height) {
	lcd_draw_ptr(pixels, x, y, width, height);
}

void lcd_fill_local(u16 color, int x, int y, int width, int height) {
	lcd_fill_ptr(color, x, y, width, height);
}

void lcd_point_local(u16 color, int x, int y) {
	lcd_point_ptr(color, x, y);
}

void lcd_clear_local() {
	lcd_clear_ptr();
}

int lcd_get_buffer_mode(void) {
	return framebuffer_mode;
}

bool lcd_buffer_enable_local(int mode) {
	if (mode != LCD_BUFFERMODE_RAM) {
		if (framebuffer) {
			free(framebuffer);
			framebuffer = NULL;
		}
	}

	if (mode == LCD_BUFFERMODE_DIRECT) {
		lcd_draw_ptr = &lcd_direct_draw;
		lcd_fill_ptr = &lcd_direct_fill;
		lcd_point_ptr = &lcd_direct_point;
		lcd_clear_ptr = &lcd_direct_clear;
		framebuffer_mode = mode;
		lcd_current_height = MEM_HEIGHT;
		return true;
	} else if (mode == LCD_BUFFERMODE_PSRAM) {
		lcd_draw_ptr = &lcd_psram_draw;
		lcd_fill_ptr = &lcd_psram_fill;
		lcd_point_ptr = &lcd_psram_point;
		lcd_clear_ptr = &lcd_psram_clear;
		framebuffer_mode = mode;
		lcd_current_height = LCD_HEIGHT;
		return true;
	} else if (mode == LCD_BUFFERMODE_RAM) {
		if (!framebuffer) {
			framebuffer = malloc(LCD_WIDTH * LCD_HEIGHT);
			if (framebuffer) {
				lcd_draw_ptr = &lcd_ram_draw;
				lcd_fill_ptr = &lcd_ram_fill;
				lcd_point_ptr = &lcd_ram_point;
				lcd_clear_ptr = &lcd_ram_clear;
				framebuffer_mode = mode;
				lcd_current_height = LCD_HEIGHT;
				return true;
			}
		}
	}

	return false;
}

void lcd_scroll_local(int lines) {
	if (framebuffer_mode == LCD_BUFFERMODE_PSRAM) {
		// Software scroll for PSRAM mode
		// In buffer mode, 'lines' is the actual pixel delta to scroll (not cumulative)
		if (lines > 0 && lines < LCD_HEIGHT) {
			// Shift rows up: copy from [lines..319] to [0..319-lines]
			// Read and write row by row to avoid needing large buffer
			for (int y = 0; y < LCD_HEIGHT - lines; y++) {
				// Read row from position y + lines
				for (int x = 0; x < LCD_WIDTH; x += 10) {
					psram_read(&psram_spi, ((x + (y + lines) * LCD_WIDTH) << 1), (uint8_t*)(lcd_tmpbuf + x), 20);
				}
				// Write to position y
				for (int x = 0; x < LCD_WIDTH; x += 10) {
					psram_write(&psram_spi, ((x + y * LCD_WIDTH) << 1), (uint8_t*)(lcd_tmpbuf + x), 20);
				}
			}
			// Clear the bottom rows
			for (int i = 0; i < 10; i++) lcd_tmpbuf[i] = 0;  // Black
			for (int y = LCD_HEIGHT - lines; y < LCD_HEIGHT; y++) {
				for (int x = 0; x < LCD_WIDTH; x += 10) {
					psram_write(&psram_spi, ((x + y * LCD_WIDTH) << 1), (uint8_t*)lcd_tmpbuf, 20);
				}
			}
		} else if (lines >= LCD_HEIGHT) {
			// Scrolling more than screen height, just clear
			lcd_psram_clear();
		}
	} else if (framebuffer_mode == LCD_BUFFERMODE_RAM) {
		// Software scroll for RAM mode
		// In buffer mode, 'lines' is the actual pixel delta to scroll (not cumulative)
		if (lines > 0 && lines < LCD_HEIGHT) {
			// Shift rows up using memmove
			memmove(framebuffer, framebuffer + lines * LCD_WIDTH,
			        (LCD_HEIGHT - lines) * LCD_WIDTH);
			// Clear bottom rows
			memset(framebuffer + (LCD_HEIGHT - lines) * LCD_WIDTH, 0,
			       lines * LCD_WIDTH);
		} else if (lines >= LCD_HEIGHT) {
			lcd_ram_clear();
		}
	} else {
		// Direct mode: use hardware scroll (cumulative position)
		lines %= MEM_HEIGHT;
		uint8_t cmd[] = {0x37, (lines >> 8), (lines & 0xFF)};
		lcd_write_cmd(cmd, 3);
	}
}

void lcd_setup_scrolling(int top_fixed_lines, int bottom_fixed_lines) {
	int vertical_scrolling_area = LCD_HEIGHT - (top_fixed_lines + bottom_fixed_lines);
	const uint8_t cmd[] = {0x33,
		(top_fixed_lines >> 8), (top_fixed_lines & 0xFF),
		(vertical_scrolling_area >> 8), (vertical_scrolling_area & 0xFF),
		(bottom_fixed_lines >> 8), (bottom_fixed_lines & 0xff)
	};
	lcd_write_cmd(cmd, 7);
}

font_t font = {
	.glyphs = NULL,
	.glyph_width = 0,
	.glyph_height = 0,
	.glyph_colorbuf = NULL
};

int lcd_load_font(const char* filename) {
	if (font.glyphs) { free(font.glyphs); font.glyphs = NULL; }
	if (font.glyph_colorbuf) { free(font.glyph_colorbuf); font.glyph_colorbuf = NULL; }
	if (font.font_file) { free(font.font_file); font.font_file = NULL; }

	if (!filename || filename[0] == '\0') {
		font.glyphs = malloc(2049 * sizeof(u8));
		memcpy(font.glyphs, (u8*)DEFAULT_GLYPHS, 2049);
		font.glyph_count = 255;
		font.glyph_width = DEFAULT_GLYPH_WIDTH;
		font.glyph_height = DEFAULT_GLYPH_HEIGHT;
		font.firstcode = 0;
	} else {
		FRESULT res;
		FIL fp;
		uint8_t bytesize;
		res = f_open(&fp, filename, FA_READ);
		if (res != FR_OK) { lcd_load_font(NULL); return res; }
		res = f_lseek(&fp, 2); // skip length
		if (res != FR_OK) { lcd_load_font(NULL); return res; }
		res = f_read(&fp, &font.glyph_count, 1, NULL);
		if (res != FR_OK) { lcd_load_font(NULL); return res; }
		res = f_read(&fp, &font.firstcode, 1, NULL);
		if (res != FR_OK) { lcd_load_font(NULL); return res; }
		res = f_read(&fp, &font.glyph_width, 1, NULL);
		if (res != FR_OK) { lcd_load_font(NULL); return res; }
		res = f_read(&fp, &font.glyph_height, 1, NULL);
		if (res != FR_OK) { lcd_load_font(NULL); return res; }
		res = f_read(&fp, &bytesize, 1, NULL);
		if (res != FR_OK) { lcd_load_font(NULL); return res; }
		font.glyphs = malloc(font.glyph_count * bytesize * sizeof(u8));
		res = f_read(&fp, font.glyphs, font.glyph_count * bytesize, NULL);
		if (res != FR_OK) return res;
		f_close(&fp);

		font.font_file = strdup(filename);
	}

	font.bytewidth = font.glyph_width/8 + (font.glyph_width % 8 != 0);
	font.glyph_colorbuf = malloc(font.glyph_height * font.glyph_width * sizeof(u16));
	font.term_width = LCD_WIDTH / font.glyph_width;
	font.term_height = LCD_HEIGHT / font.glyph_height;
	return FR_OK;
}

void lcd_draw_char_local(int x, int y, u16 fg, u16 bg, char c) {
	if (c > font.glyph_count + font.firstcode) c = 0;
	int offset = ((u8)(c - font.firstcode)) * font.bytewidth * font.glyph_height;
	for (int j = 0; j < font.glyph_height; j++) {
		for (int i = 0; i < font.glyph_width; i++) {
			int mask = (1 << (7 - i%8));
			font.glyph_colorbuf[i + j * font.glyph_width] = (font.glyphs[offset + i / 8] & mask) ? fg : bg;
		}
		offset+=font.bytewidth;
	}

	lcd_draw(font.glyph_colorbuf, x, y, font.glyph_width, font.glyph_height);
}

void lcd_draw_text_local(int x, int y, u16 fg, u16 bg, const char* text, size_t len, u8 align) {
	//if (y <= -font.glyph_height || y >= HEIGHT) return;
	if (align == LCD_ALIGN_CENTER) x -= len * font.glyph_width / 2;
	else if (align == LCD_ALIGN_RIGHT) x -= len * font.glyph_width;
	for (int i = 0; i < len; i++) {
		lcd_draw_char(x, y, fg, bg, *text);
		x += font.glyph_width;
		if (x > LCD_WIDTH) return;
		text ++;
	}
}

void lcd_printf(int x, int y, u16 fg, u16 bg, const char* format, ...) {
	char buffer[512];
	va_list list;
	va_start(list, format);
	int result = vsnprintf(buffer, 512, format, list);
	if (result > -1) {
		lcd_draw_text(x, y, fg, bg, buffer, result, LCD_ALIGN_LEFT);
	}
}

static const uint8_t st7789_init_seq[] = {
	// Positive Gamma Control
	16, 0, 0xE0, 0x00, 0x03, 0x09, 0x08, 0x16, 0x0A, 0x3F, 0x78, 0x4C, 0x09, 0x0A, 0x08, 0x16, 0x1A, 0x0F,
	// Negative Gamma Control
	16, 0, 0xE1, 0x00, 0x16, 0x19, 0x03, 0x0F, 0x05, 0x32, 0x45, 0x46, 0x04, 0x0E, 0x0D, 0x35, 0x37, 0x0F,
	// Power Control 1
	3, 0, 0xC0, 0x17, 0x15,
	// Power Control 2
	2, 0, 0xC1, 0x41,
	// VCOM Control
	4, 0, 0xC5, 0x00, 0x12, 0x80,
	// Memory Access Control (0x48=BGR, 0x40=RGB)
	2, 0, 0x36, 0x48,
	// Pixel Interface Format  16 bit colour for SPI
	2, 0, 0x3A, 0x55,
	// Interface Mode Control
	2, 0, 0xB0, 0x00,
	// 60Hz
	3, 0, 0xB1, 0xD0, 0x11,
	// Invert colors on
	1, 0, 0x21,
	// Display Inversion Control
	2, 0, 0xB4, 0x02,
	// Display Function Control
	4, 0, 0xB6, 0x02, 0x02, 0x3B,
	// Entry Mode Set
	2, 0, 0xB7, 0xC6,
	2, 0, 0xE9, 0x00,
	// Adjust Control 3
	5, 0, 0xF7, 0xA9, 0x51, 0x2C, 0x82,
	// Exit Sleep
	1, 0, 0x11,
	// Terminate list
	0
};

void lcd_reset_pio() {
	int cpu_khz = frequency_count_khz(CLOCKS_FC0_SRC_VALUE_CLK_SYS);
	float clkdiv = 1.f;
	if (cpu_khz > 200000) {
		clkdiv = 1.5f;
	}
	st7789_lcd_program_init(LCD_PIO, lcd_sm, lcd_offset, LCD_TX, LCD_SCK, clkdiv);
	psram_spi = psram_spi_init_clkdiv(pio0, 0, clkdiv, true);
}

void lcd_init() {
	// Init GPIO
	gpio_init(LCD_SCK);
	gpio_init(LCD_TX);
	//gpio_init(LCD_RX);
	gpio_init(LCD_CS);
	gpio_init(LCD_DC);
	gpio_init(LCD_RST);

	gpio_set_dir(LCD_SCK, GPIO_OUT);
	gpio_set_dir(LCD_TX, GPIO_OUT);
	//gpio_set_dir(LCD_RX, GPIO_IN);
	gpio_set_dir(LCD_CS, GPIO_OUT);
	gpio_set_dir(LCD_DC, GPIO_OUT);
	gpio_set_dir(LCD_RST, GPIO_OUT);

	// Init PIO
	lcd_offset = pio_add_program(LCD_PIO, &st7789_lcd_program);
	lcd_reset_pio();

	lcd_set_dc_cs(0, 1);
	gpio_put(LCD_RST, 1);

	// Reset controller
	gpio_put(LCD_RST, 0);
	busy_wait_us(20); // 20µs reset pulse (10µs minimum)
	gpio_put(LCD_RST, 1);
	busy_wait_us(120000); // 5ms required after reset, but 120ms needed before sleep out command

	// Setup LCD
	lcd_initcmd(st7789_init_seq);
	lcd_set_dc_cs(0, 1);

	lcd_buffer_enable(0);

	lcd_load_font(NULL);

	lcd_clear();
	lcd_on();
}

// Screenshot - save framebuffer to BMP file
// Returns: 0 success, -1 wrong mode, -2 file error, -3 write error
int lcd_screenshot(const char* filename) {
	if (framebuffer_mode == LCD_BUFFERMODE_DIRECT) {
		return -1;  // No readable framebuffer in direct mode
	}

	FIL file;
	FRESULT res;
	UINT bw;

	res = f_open(&file, filename, FA_CREATE_ALWAYS | FA_WRITE);
	if (res != FR_OK) {
		return -2;
	}

	// BMP file header (14 bytes)
	uint8_t bmp_header[14] = {
		'B', 'M',           // Signature
		0x42, 0x20, 0x03, 0x00,  // File size: 66 + 204800 = 204866 (0x00032042)
		0x00, 0x00,         // Reserved
		0x00, 0x00,         // Reserved
		0x42, 0x00, 0x00, 0x00   // Pixel data offset: 66 (0x42)
	};

	// BMP info header (40 bytes)
	uint8_t bmp_info[40] = {
		0x28, 0x00, 0x00, 0x00,  // Info header size: 40
		0x40, 0x01, 0x00, 0x00,  // Width: 320 (0x140)
		0x40, 0x01, 0x00, 0x00,  // Height: 320 (positive = bottom-up)
		0x01, 0x00,              // Planes: 1
		0x10, 0x00,              // Bits per pixel: 16
		0x03, 0x00, 0x00, 0x00,  // Compression: 3 (BI_BITFIELDS)
		0x00, 0x20, 0x03, 0x00,  // Image size: 204800 (0x00032000)
		0x00, 0x00, 0x00, 0x00,  // X pixels per meter
		0x00, 0x00, 0x00, 0x00,  // Y pixels per meter
		0x00, 0x00, 0x00, 0x00,  // Colors used
		0x00, 0x00, 0x00, 0x00   // Important colors
	};

	// RGB565 color masks (12 bytes)
	uint8_t color_masks[12] = {
		0x00, 0xF8, 0x00, 0x00,  // Red mask: 0xF800
		0xE0, 0x07, 0x00, 0x00,  // Green mask: 0x07E0
		0x1F, 0x00, 0x00, 0x00   // Blue mask: 0x001F
	};

	// Write headers
	res = f_write(&file, bmp_header, 14, &bw);
	if (res != FR_OK || bw != 14) { f_close(&file); return -3; }

	res = f_write(&file, bmp_info, 40, &bw);
	if (res != FR_OK || bw != 40) { f_close(&file); return -3; }

	res = f_write(&file, color_masks, 12, &bw);
	if (res != FR_OK || bw != 12) { f_close(&file); return -3; }

	// Write pixel data row by row, bottom to top (BMP format)
	uint16_t row_buf[LCD_WIDTH];

	for (int y = LCD_HEIGHT - 1; y >= 0; y--) {
		if (framebuffer_mode == LCD_BUFFERMODE_PSRAM) {
			// Read row from PSRAM (10 pixels at a time like existing code)
			for (int x = 0; x < LCD_WIDTH; x += 10) {
				psram_read(&psram_spi, (x + y * LCD_WIDTH) << 1, (uint8_t*)(row_buf + x), 20);
			}
		} else if (framebuffer_mode == LCD_BUFFERMODE_RAM) {
			// Convert 8-bit indexed to 16-bit RGB565
			for (int x = 0; x < LCD_WIDTH; x++) {
				row_buf[x] = lcd_to16[framebuffer[x + y * LCD_WIDTH]];
			}
		}

		res = f_write(&file, row_buf, LCD_WIDTH * 2, &bw);
		if (res != FR_OK || bw != LCD_WIDTH * 2) {
			f_close(&file);
			return -3;
		}
	}

	f_close(&file);
	return 0;
}

// Display BMP file directly to screen at position (x, y)
// Streams row-by-row for minimal memory usage (~2KB)
// Supports 16-bit RGB565, 24-bit BGR, and 32-bit BGRA formats
// Returns: 0 success, -1 file error, -2 invalid format, -3 read error
int lcd_show_bmp(const char* filename, int x, int y) {
	FIL file;
	FRESULT res;
	UINT br;

	// BMP headers
	uint8_t file_header[14];
	uint8_t info_header[40];

	res = f_open(&file, filename, FA_READ);
	if (res != FR_OK) return -1;

	// Read file header (14 bytes)
	res = f_read(&file, file_header, 14, &br);
	if (res != FR_OK || br != 14) { f_close(&file); return -3; }

	// Check BMP signature
	if (file_header[0] != 'B' || file_header[1] != 'M') {
		f_close(&file);
		return -2;
	}

	// Read info header (40 bytes)
	res = f_read(&file, info_header, 40, &br);
	if (res != FR_OK || br != 40) { f_close(&file); return -3; }

	// Parse header fields
	uint32_t data_offset = file_header[10] | (file_header[11] << 8) |
	                       (file_header[12] << 16) | (file_header[13] << 24);
	int32_t width = info_header[4] | (info_header[5] << 8) |
	                (info_header[6] << 16) | (info_header[7] << 24);
	int32_t height = info_header[8] | (info_header[9] << 8) |
	                 (info_header[10] << 16) | (info_header[11] << 24);
	uint16_t bit_depth = info_header[14] | (info_header[15] << 8);
	uint32_t compression = info_header[16] | (info_header[17] << 8) |
	                       (info_header[18] << 16) | (info_header[19] << 24);

	// Validate bit depth (16, 24, or 32)
	if (bit_depth != 16 && bit_depth != 24 && bit_depth != 32) {
		f_close(&file);
		return -2;
	}

	// For 16-bit, verify it's RGB565 (compression = BI_BITFIELDS = 3)
	int is_rgb565 = 0;
	if (bit_depth == 16) {
		if (compression == 3) {
			// Read color masks to verify RGB565
			uint32_t r_mask, g_mask, b_mask;
			res = f_read(&file, &r_mask, 4, &br);
			res = f_read(&file, &g_mask, 4, &br);
			res = f_read(&file, &b_mask, 4, &br);
			if (r_mask == 0xF800 && g_mask == 0x07E0 && b_mask == 0x001F) {
				is_rgb565 = 1;
			} else {
				f_close(&file);
				return -2;  // Unsupported 16-bit format
			}
		} else {
			f_close(&file);
			return -2;  // 16-bit without bitfields not supported
		}
	}

	// Handle negative height (top-down BMP)
	int top_down = (height < 0);
	if (top_down) height = -height;

	// Calculate row size with padding (rows are padded to 4-byte boundaries)
	int bytes_per_pixel = bit_depth / 8;
	int row_size = ((width * bytes_per_pixel) + 3) & ~3;

	// Allocate row buffer for reading (max 32-bit = 4 bytes per pixel)
	uint8_t* read_buf = malloc(row_size);
	if (!read_buf) { f_close(&file); return -3; }

	// Allocate RGB565 output buffer for one row
	uint16_t* row_buf = malloc(width * 2);
	if (!row_buf) { free(read_buf); f_close(&file); return -3; }

	// Process each row
	for (int row = 0; row < height; row++) {
		// Calculate screen Y position
		int screen_y;
		if (top_down) {
			screen_y = y + row;
		} else {
			screen_y = y + (height - 1 - row);
		}

		// Skip rows outside screen
		if (screen_y < 0 || screen_y >= lcd_current_height) continue;

		// Seek to row in file
		uint32_t row_offset = data_offset + (uint32_t)row * row_size;
		res = f_lseek(&file, row_offset);
		if (res != FR_OK) { free(read_buf); free(row_buf); f_close(&file); return -3; }

		// Read row data
		res = f_read(&file, read_buf, row_size, &br);
		if (res != FR_OK || br != row_size) {
			free(read_buf); free(row_buf); f_close(&file);
			return -3;
		}

		// Convert to RGB565 if needed
		if (bit_depth == 16 && is_rgb565) {
			// Already RGB565, just copy
			memcpy(row_buf, read_buf, width * 2);
		} else if (bit_depth == 24) {
			// Convert BGR to RGB565
			for (int px = 0; px < width; px++) {
				uint8_t b = read_buf[px * 3];
				uint8_t g = read_buf[px * 3 + 1];
				uint8_t r = read_buf[px * 3 + 2];
				row_buf[px] = RGB(r, g, b);
			}
		} else if (bit_depth == 32) {
			// Convert BGRA to RGB565 (ignore alpha)
			for (int px = 0; px < width; px++) {
				uint8_t b = read_buf[px * 4];
				uint8_t g = read_buf[px * 4 + 1];
				uint8_t r = read_buf[px * 4 + 2];
				row_buf[px] = RGB(r, g, b);
			}
		}

		// Calculate how many pixels to draw (clip to screen width)
		int draw_x = x;
		int draw_width = width;
		int src_offset = 0;

		if (draw_x < 0) {
			src_offset = -draw_x;
			draw_width += draw_x;
			draw_x = 0;
		}
		if (draw_x + draw_width > LCD_WIDTH) {
			draw_width = LCD_WIDTH - draw_x;
		}

		if (draw_width > 0) {
			lcd_draw(row_buf + src_offset, draw_x, screen_y, draw_width, 1);
		}
	}

	free(read_buf);
	free(row_buf);
	f_close(&file);
	return 0;
}

int lcd_fifo_receiver(uint32_t message) {
	uint32_t x, y, fg, bg, width, height, c;
	char* text;

	switch (message) {
		case FIFO_LCD_POINT:
			fg = multicore_fifo_pop_blocking_inline();
			x = multicore_fifo_pop_blocking_inline();
			y = multicore_fifo_pop_blocking_inline();
			lcd_point_local((u16)fg, (int)x, (int)y);
			return 1;

		case FIFO_LCD_DRAW:
			fg = multicore_fifo_pop_blocking_inline();
			x = multicore_fifo_pop_blocking_inline();
			y = multicore_fifo_pop_blocking_inline();
			width = multicore_fifo_pop_blocking_inline();
			height = multicore_fifo_pop_blocking_inline();
			lcd_draw_local((u16*)fg, (int)x, (int)y, (int)width, (int)height);
			return 1;

		case FIFO_LCD_FILL:
			fg = multicore_fifo_pop_blocking_inline();
			x = multicore_fifo_pop_blocking_inline();
			y = multicore_fifo_pop_blocking_inline();
			width = multicore_fifo_pop_blocking_inline();
			height = multicore_fifo_pop_blocking_inline();
			lcd_fill_local((u16)fg, (int)x, (int)y, (int)width, (int)height);
			return 1;

		case FIFO_LCD_CLEAR:
			lcd_clear_local();
			return 1;

		case FIFO_LCD_BUFEN:
			x = multicore_fifo_pop_blocking_inline();
			multicore_fifo_push_blocking_inline((uint32_t)lcd_buffer_enable_local((int)x));
			return 1;

		case FIFO_LCD_BUFBLIT:
			lcd_buffer_blit_local();
			return 1;

		case FIFO_LCD_CHAR:
			x = multicore_fifo_pop_blocking_inline();
			y = multicore_fifo_pop_blocking_inline();
			fg = multicore_fifo_pop_blocking_inline();
			bg = multicore_fifo_pop_blocking_inline();
			c = multicore_fifo_pop_blocking_inline();
			lcd_draw_char_local((int)x, (int)y, (u16)fg, (u16)bg, (char)c);
			return 1;

		case FIFO_LCD_TEXT:
			x = multicore_fifo_pop_blocking_inline();
			y = multicore_fifo_pop_blocking_inline();
			fg = multicore_fifo_pop_blocking_inline();
			bg = multicore_fifo_pop_blocking_inline();
			c = multicore_fifo_pop_blocking_inline();
			width = multicore_fifo_pop_string(&text);
			lcd_draw_text_local((int)x, (int)y, (u16)fg, (u16)bg, text, width, (u8)c);
			free(text);
			return 1;

		case FIFO_LCD_SCROLL:
			height = multicore_fifo_pop_blocking_inline();
			lcd_scroll_local((int)height);
			return 1;

		default:
			return 0;
	}
}

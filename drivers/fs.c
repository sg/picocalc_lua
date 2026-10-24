#include <stdlib.h>
#include <stdio.h>

#include "tf_card.h"
#include "pico/time.h"

#include "fs.h"

static FATFS global_fs;
static bool card_shown, card_changing;
static absolute_time_t card_settled_at;

#define SD_MISO   16
#define SD_MOSI   19
#define SD_CS     17
#define SD_SCK    18
#define SD_DETECT 22
// SPI-mode cards are only guaranteed 25 MHz; the 50 MHz default ran RP2350 boards at 37.5 MHz
#define SD_CLK_FAST (25 * MHZ)
#define DEBOUNCE_US 80 * 1000ull

char* fs_error_strings[20] = {
	"Succeeded",
	"A hard error occurred in the low level disk I/O layer",
	"Assertion failed",
	"The physical drive cannot work",
	"Could not find the file",
	"Could not find the path",
	"The path name format is invalid",
	"Access denied due to prohibited access or directory full",
	"Access denied due to prohibited access",
	"The file/directory object is invalid",
	"The physical drive is write protected",
	"The logical drive number is invalid",
	"The volume has no work area",
	"There is no valid FAT volume",
	"The f_mkfs() aborted due to any problem",
	"Could not get a grant to access the volume within defined period",
	"The operation is rejected according to the file sharing policy",
	"Not enough memory",
	"Number of open files > FF_FS_LOCK",
	"Given parameter is invalid",
};

static void sd_hotplug(uint gpio, uint32_t events) {
	// FatFs belongs to Lua on core 1, so this only has the driver
	// re-initialise the card, and FatFs remount it, on the next FatFs call
	if (gpio == SD_DETECT) pico_fatfs_media_changed();
}

void fs_init() {
	pico_fatfs_spi_config_t config = {
		.spi_inst = spi0,
		.clk_slow = CLK_SLOW_DEFAULT,
		.clk_fast = SD_CLK_FAST,
		.pin_miso = SD_MISO,
		.pin_cs = SD_CS,
		.pin_sck = SD_SCK,
		.pin_mosi = SD_MOSI,
		.pullup = true,
	};
	pico_fatfs_set_config(&config);
	gpio_init(SD_DETECT);
	card_shown = !gpio_get(SD_DETECT);
	gpio_set_irq_enabled_with_callback(SD_DETECT, GPIO_IRQ_EDGE_RISE | GPIO_IRQ_EDGE_FALL, true, &sd_hotplug);
}

// core 0's loop: reports a card coming or going once the switch has held
// still for DEBOUNCE_US, without touching FatFs
void fs_poll() {
	bool in = !gpio_get(SD_DETECT);

	if (in == card_shown) {
		card_changing = false;
		return;
	}
	if (!card_changing) {
		card_changing = true;
		card_settled_at = make_timeout_time_us(DEBOUNCE_US);
		return;
	}
	if (!time_reached(card_settled_at)) return;
	card_changing = false;
	card_shown = in;
	if (in) printf("\x1b[92mSD card inserted\x1b[m\n");
	else printf("\x1b[91mSD card removed\x1b[m\n");
}

int fs_mount() {
	// global_fs stays registered when this fails, so FatFs mounts a card
	// inserted later on the first call that needs it
	return f_mount(&global_fs, "", 1) == FR_OK;
}

bool fs_crc_checked() {
	return pico_fatfs_crc_enabled();
}

int fs_exists(const char* path) {
	FILINFO info;
	FRESULT result = f_stat(path, &info);
	return result == FR_OK && info.fname[0] != 0;
}

FRESULT fs_readline(FIL* fp, char** buffer, UINT* read) {
	FRESULT result;
	UINT got;

	if (*buffer) {
		free(*buffer);
		*buffer = NULL;
	}
	*read = 0;

	if (f_eof(fp)) return FR_OK;

	FSIZE_t old_fptr = fp->fptr;

	char c = 0;
	while (c != '\n' && !f_eof(fp)) {
		result = f_read(fp, &c, 1, &got);
		if (result != FR_OK) return result;
	}
	// length of file from old_fptr until newline, minus newline
	UINT to_read = fp->fptr - old_fptr;
	if (c == '\n') to_read--;
	f_lseek(fp, old_fptr);
	
	// room for a terminator, which also gives an empty line a buffer
	*buffer = malloc(to_read + 1);
	if (!*buffer) return FR_NOT_ENOUGH_CORE;
	result = f_read(fp, *buffer, to_read, read);
	if (result != FR_OK) return result;
	(*buffer)[*read] = '\0';

	// skip that newline
	if (c == '\n') f_lseek(fp, fp->fptr + 1);

	return result;
}

FRESULT fs_writeline(FIL* fp, const char* line, UINT to_write, UINT* written) {
	UINT add;
	
	FRESULT result = f_write (fp, line, to_write, written);
	if (result != FR_OK) return result;

	const char n = '\n';
	result = f_write (fp, &n, 1, &add);
	if (result != FR_OK) return result;

	*written += add;
	return result;
}
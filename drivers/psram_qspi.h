#pragma once

#include <stddef.h>
#include <stdbool.h>

#define PSRAM_QSPI_BASE 0x11000000u

size_t psram_qspi_init(void);         // Returns detected size, 0 if unavailable
size_t psram_qspi_get_size(void);
bool   psram_qspi_is_available(void);

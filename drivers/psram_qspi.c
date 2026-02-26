/*
 * QSPI PSRAM driver for Pimoroni Pico Plus 2 / 2W boards.
 * Ported from pcalc-lua/drivers/psram.c — initializes the RP2350 QMI controller
 * to memory-map the on-board APS6404L 8MB PSRAM at 0x11000000.
 *
 * Unlike the pcalc-lua version, this does NOT override _sbrk().
 * PSRAM is used explicitly via memcpy for the display buffer and Lua psram.* API.
 */

#include "psram_qspi.h"

#ifdef PICOCALC_QSPI_PSRAM

#include "pico/stdlib.h"

/*
 * Determine the PSRAM CS pin from the board header. Pimoroni boards define
 * either PIMORONI_PICO_PLUS2_W_PSRAM_CS_PIN or PIMORONI_PICO_PLUS2_PSRAM_CS_PIN.
 */
#if defined(PIMORONI_PICO_PLUS2_W_PSRAM_CS_PIN)
#define PSRAM_CS_PIN PIMORONI_PICO_PLUS2_W_PSRAM_CS_PIN
#elif defined(PIMORONI_PICO_PLUS2_PSRAM_CS_PIN)
#define PSRAM_CS_PIN PIMORONI_PICO_PLUS2_PSRAM_CS_PIN
#else
#error "PICOCALC_QSPI_PSRAM defined but no Pimoroni PSRAM CS pin found in board header"
#endif

#include <string.h>
#include "hardware/gpio.h"
#include "hardware/clocks.h"
#include "hardware/structs/qmi.h"
#include "hardware/structs/xip.h"
#include "hardware/sync.h"
#include "pico/platform/sections.h"

static size_t detected_psram_size = 0;

/*
 * Detect PSRAM by writing test patterns and checking for wrap-around.
 * Must be called after QMI is configured for PSRAM access.
 * Returns size in bytes (0 if no PSRAM found).
 */
static size_t __no_inline_not_in_flash_func(psram_detect)(void)
{
    volatile uint32_t *base = (volatile uint32_t *)PSRAM_QSPI_BASE;

    const uint32_t pattern_a = 0xDEADBEEF;
    const uint32_t pattern_b = 0xCAFEBABE;

    base[0] = pattern_a;
    __compiler_memory_barrier();
    if (base[0] != pattern_a) {
        return 0;
    }

    /* Determine size by checking for address wrap-around. */
    size_t size = 8 * 1024 * 1024;
    while (size > (512 * 1024)) {
        volatile uint32_t *probe = (volatile uint32_t *)(PSRAM_QSPI_BASE + size);
        base[0] = pattern_a;
        probe[0] = pattern_b;
        __compiler_memory_barrier();
        if (base[0] == pattern_a) {
            return size;
        }
        size >>= 1;
    }

    return size;
}

/*
 * Initialize QMI controller for PSRAM access.
 * Must run from SRAM (not flash) because it reconfigures the QMI.
 */
static size_t __no_inline_not_in_flash_func(psram_hw_init)(void)
{
    gpio_set_function(PSRAM_CS_PIN, GPIO_FUNC_XIP_CS1);

    uint32_t intr_stash = save_and_disable_interrupts();

    /* Enter QMI direct mode with slow clock for reset/init */
    qmi_hw->direct_csr = (10u << QMI_DIRECT_CSR_CLKDIV_LSB) |
                          QMI_DIRECT_CSR_EN_BITS |
                          QMI_DIRECT_CSR_AUTO_CS1N_BITS;
    while (qmi_hw->direct_csr & QMI_DIRECT_CSR_BUSY_BITS)
        ;

    /* Reset Enable (0x66) */
    qmi_hw->direct_tx = QMI_DIRECT_TX_NOPUSH_BITS | 0x66;
    while (qmi_hw->direct_csr & QMI_DIRECT_CSR_BUSY_BITS)
        ;

    /* Reset (0x99) */
    qmi_hw->direct_tx = QMI_DIRECT_TX_NOPUSH_BITS | 0x99;
    while (qmi_hw->direct_csr & QMI_DIRECT_CSR_BUSY_BITS)
        ;

    /* Brief delay for reset to complete */
    for (volatile int i = 0; i < 1000; i++)
        ;

    /* Enter QPI mode (0x35) */
    qmi_hw->direct_tx = QMI_DIRECT_TX_NOPUSH_BITS | 0x35;
    while (qmi_hw->direct_csr & QMI_DIRECT_CSR_BUSY_BITS)
        ;

    /* Exit direct mode */
    qmi_hw->direct_csr = 0;

    /* Configure QMI M1 for PSRAM access */

    /* APS6404L max frequency is 133 MHz */
    const int max_psram_freq = 133000000;
    const int clock_hz = clock_get_hz(clk_sys);
    int divisor = (clock_hz + max_psram_freq - 1) / max_psram_freq;
    if (divisor == 1 && clock_hz > 100000000) {
        divisor = 2;
    }

    int rxdelay = divisor;
    if (clock_hz / divisor > 100000000) {
        rxdelay += 1;
    }

    const int64_t clock_period_fs = 1000000000000000LL / clock_hz;
    const int max_select = (int)((125 * 1000000LL) / clock_period_fs);
    int min_deselect = (int)(((18 * 1000000LL) + (clock_period_fs - 1)) / clock_period_fs);
    min_deselect -= (divisor + 1) / 2;
    if (min_deselect < 1)
        min_deselect = 1;

    /* M1 timing register */
    qmi_hw->m[1].timing =
        (1u << QMI_M1_TIMING_COOLDOWN_LSB) |
        (QMI_M1_TIMING_PAGEBREAK_VALUE_1024 << QMI_M1_TIMING_PAGEBREAK_LSB) |
        ((uint32_t)max_select << QMI_M1_TIMING_MAX_SELECT_LSB) |
        ((uint32_t)min_deselect << QMI_M1_TIMING_MIN_DESELECT_LSB) |
        ((uint32_t)rxdelay << QMI_M1_TIMING_RXDELAY_LSB) |
        ((uint32_t)divisor << QMI_M1_TIMING_CLKDIV_LSB);

    /* Read format: QPI, Fast Read Quad (0xEB), 6 dummy cycles */
    qmi_hw->m[1].rfmt =
        (QMI_M0_RFMT_PREFIX_WIDTH_VALUE_Q << QMI_M0_RFMT_PREFIX_WIDTH_LSB) |
        (QMI_M0_RFMT_ADDR_WIDTH_VALUE_Q << QMI_M0_RFMT_ADDR_WIDTH_LSB) |
        (QMI_M0_RFMT_SUFFIX_WIDTH_VALUE_Q << QMI_M0_RFMT_SUFFIX_WIDTH_LSB) |
        (QMI_M0_RFMT_DUMMY_WIDTH_VALUE_Q << QMI_M0_RFMT_DUMMY_WIDTH_LSB) |
        (QMI_M0_RFMT_DATA_WIDTH_VALUE_Q << QMI_M0_RFMT_DATA_WIDTH_LSB) |
        (QMI_M0_RFMT_PREFIX_LEN_VALUE_8 << QMI_M0_RFMT_PREFIX_LEN_LSB) |
        (6u << QMI_M0_RFMT_DUMMY_LEN_LSB);

    qmi_hw->m[1].rcmd = 0xEB;

    /* Write format: QPI, Quad Write (0x38), no dummy */
    qmi_hw->m[1].wfmt =
        (QMI_M0_WFMT_PREFIX_WIDTH_VALUE_Q << QMI_M0_WFMT_PREFIX_WIDTH_LSB) |
        (QMI_M0_WFMT_ADDR_WIDTH_VALUE_Q << QMI_M0_WFMT_ADDR_WIDTH_LSB) |
        (QMI_M0_WFMT_SUFFIX_WIDTH_VALUE_Q << QMI_M0_WFMT_SUFFIX_WIDTH_LSB) |
        (QMI_M0_WFMT_DUMMY_WIDTH_VALUE_Q << QMI_M0_WFMT_DUMMY_WIDTH_LSB) |
        (QMI_M0_WFMT_DATA_WIDTH_VALUE_Q << QMI_M0_WFMT_DATA_WIDTH_LSB) |
        (QMI_M0_WFMT_PREFIX_LEN_VALUE_8 << QMI_M0_WFMT_PREFIX_LEN_LSB);

    qmi_hw->m[1].wcmd = 0x38;

    /* Enable writes to XIP memory window 1 (PSRAM) */
    hw_set_bits(&xip_ctrl_hw->ctrl, XIP_CTRL_WRITABLE_M1_BITS);

    size_t size = psram_detect();

    restore_interrupts(intr_stash);

    return size;
}

size_t psram_qspi_init(void)
{
    detected_psram_size = psram_hw_init();
    return detected_psram_size;
}

size_t psram_qspi_get_size(void)
{
    return detected_psram_size;
}

bool psram_qspi_is_available(void)
{
    return detected_psram_size > 0;
}

#else /* !PICOCALC_QSPI_PSRAM */

size_t psram_qspi_init(void)
{
    return 0;
}

size_t psram_qspi_get_size(void)
{
    return 0;
}

bool psram_qspi_is_available(void)
{
    return false;
}

#endif

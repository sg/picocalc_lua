# == DO NOT EDIT THE FOLLOWING LINES for the Raspberry Pi Pico VS Code Extension to work ==
if(WIN32)
    set(USERHOME $ENV{USERPROFILE})
else()
    set(USERHOME $ENV{HOME})
endif()
set(sdkVersion 2.3.1)
set(toolchainVersion 14_2_Rel1)
set(picotoolVersion 2.3.1)
set(picoVscode ${USERHOME}/.pico-sdk/cmake/pico-vscode.cmake)
if (EXISTS ${picoVscode})
    include(${picoVscode})
endif()
# ====================================================================================
if(NOT PICO_BOARD)
    set(PICO_BOARD pico2_w CACHE STRING "Board type")
endif()

cmake_minimum_required(VERSION 3.13)

# Add a custom command that produces version.cpp, plus
# a dummy output that's not actually produced, in order
# to force version.cmake to always be re-run before the build
ADD_CUSTOM_COMMAND(
	OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/version.c
					${CMAKE_CURRENT_BINARY_DIR}/_version.c
	COMMAND ${CMAKE_COMMAND} -P
					${CMAKE_CURRENT_SOURCE_DIR}/version.cmake)

set(PICO_SDK_FETCH_FROM_GIT on)
# without a tag the import fetches master, which is not what the release builds use
set(PICO_SDK_FETCH_FROM_GIT_TAG ${sdkVersion})
include(pico_sdk_import.cmake)

project(picolua)
pico_sdk_init()

add_subdirectory(submodules/lua-5.5.0/src)
# FatFs itself from the vendored pico_fatfs, but not its tf_card.c: sdcard/
# holds a copy that checks the card's CRCs
add_subdirectory(submodules/pico_fatfs/pio/spi pio_spi)
add_subdirectory(submodules/rp2040-psram)
add_subdirectory(submodules/kilo)
add_subdirectory(drivers)
add_subdirectory(picolua-api)

add_executable(picolua
	picolua.c
	corelua.c
	syscalls.c
	${CMAKE_CURRENT_BINARY_DIR}/version.c
	sdcard/tf_card.c
	submodules/pico_fatfs/fatfs/ff.c
	submodules/pico_fatfs/fatfs/ffsystem.c
	submodules/pico_fatfs/fatfs/ffunicode.c
	#lua_wrapper.c
	#fs_wrapper.c
	#main.c
)

pico_enable_stdio_usb(picolua 0)
pico_enable_stdio_uart(picolua 0)

target_link_libraries(picolua
	pico_stdlib
	hardware_irq
	hardware_pwm
	hardware_gpio
	hardware_i2c
	hardware_spi
	hardware_dma
	hardware_clocks
	#hardware_flash
	#hardware_adc
	#hardware_exception
	#hardware_pio
	pico_multicore
	lua
	drivers
	pio_spi
	kilo
	picolua-api
)

if(PICO_CYW43_SUPPORTED)
	message(STATUS "WiFi support enabled")
	target_link_libraries(picolua
		pico_cyw43_arch_lwip_threadsafe_background
		pico_lwip_mbedtls
		pico_mbedtls
	)
	target_compile_definitions(picolua PRIVATE PICOCALC_HAS_WIFI=1)
	# the Pico W's 264 KB cannot spare the 64 KB lwIP heap and the doubled
	# pbuf pool the RP2350 boards give TLS (see lwipopts.h, mbedtls_config.h)
	if(PICO_PLATFORM STREQUAL "rp2040")
		target_compile_definitions(picolua PRIVATE PICOCALC_SMALL_RAM=1)
	endif()
else()
	message(STATUS "WiFi support disabled")
endif()

if(PICO_BOARD MATCHES "pimoroni_pico_plus2")
	message(STATUS "Pimoroni QSPI PSRAM support enabled")
	target_compile_definitions(picolua PRIVATE PICOCALC_QSPI_PSRAM=1)
endif()

target_compile_definitions(picolua PRIVATE
	# rp2040-psram
	#PSRAM_MUTEX=1
	PSRAM_SPINLOCK=1
	PSRAM_ASYNC=1
	PSRAM_PIN_CS=20
	PSRAM_PIN_SCK=21
	PSRAM_PIN_MOSI=2
	PSRAM_PIN_MISO=3
)

# the project root for lwipopts.h, then FatFs with its local config and the
# card driver
target_include_directories(picolua PRIVATE
	${CMAKE_CURRENT_SOURCE_DIR}
	${CMAKE_CURRENT_SOURCE_DIR}/fatfs_conf
	${CMAKE_CURRENT_SOURCE_DIR}/sdcard
	${CMAKE_CURRENT_SOURCE_DIR}/submodules/pico_fatfs/fatfs
)

pico_add_extra_outputs(picolua)

add_custom_target(flash
		COMMAND cp picolua.uf2 /run/media/favre/RP2350/
		DEPENDS picolua
)

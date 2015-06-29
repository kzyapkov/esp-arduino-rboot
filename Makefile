TARGET = $(notdir $(realpath .))
-include local.mk

SERIAL_PORT ?= /dev/tty.nodemcu
SERIAL_BAUD ?= 230400
ESPTOOL_BAUD ?= 230400

# arduino installation and 3rd party hardware folder stuff
ARDUINO_HOME ?= $(wildcard ~/src/esp/Arduino/build/linux/work)
ARDUINO_BIN ?= $(ARDUINO_HOME)/arduino
ARDUINO_VENDOR = esp8266com
ARDUINO_ARCH = esp8266
ARDUINO_BOARD ?= ESP8266_ESP12
ARDUINO_VARIANT ?= nodemcu
ARDUINO_CORE ?= $(ARDUINO_HOME)/hardware/$(ARDUINO_VENDOR)/$(ARDUINO_ARCH)
ARDUINO_VERSION ?= 10605
F_CPU=80000000L

# sketch-specific
USER_LIBDIR = ./lib
#USER_LIBS = AQMath HTU21D IRremote RCSwitch
ARDUINO_LIBS = ESP8266WiFi
EXTRA_SRC =

XTENSA_TOOLCHAIN = $(ARDUINO_CORE)/tools/xtensa-lx106-elf/bin/
# XTENSA_TOOLCHAIN ?=
ESPRESSIF_SDK = $(ARDUINO_CORE)/tools/sdk
ESPTOOL = $(ARDUINO_CORE)/tools/esptool
ESPTOOL2 ?= $(shell which esptool2)
ESPTOOL_PY ?= $(shell which esptool.py)
BUILD_DIR = ./build
OUTPUT_DIR = ./firmware
RBOOTFW_DIR ?= $(OUTPUT_DIR)

CORE_SSRC = $(wildcard $(ARDUINO_CORE)/cores/$(ARDUINO_ARCH)/*.S)
CORE_SRC = $(wildcard $(ARDUINO_CORE)/cores/$(ARDUINO_ARCH)/*.c)
# spiffs files are in a subdirectory, don't know much about makefiles
CORE_SRC += $(wildcard $(ARDUINO_CORE)/cores/$(ARDUINO_ARCH)/*/*.c)
CORE_CXXSRC = $(wildcard $(ARDUINO_CORE)/cores/$(ARDUINO_ARCH)/*.cpp)
CORE_OBJS = $(addprefix $(BUILD_DIR)/, \
	$(notdir $(CORE_SSRC:.S=.S.o) $(CORE_SRC:.c=.c.o) $(CORE_CXXSRC:.cpp=.cpp.o)))

# arduino libraries
ALIBDIRS = $(sort $(dir $(wildcard \
	$(ARDUINO_LIBS:%=$(ARDUINO_HOME)/hardware/$(ARDUINO_VENDOR)/$(ARDUINO_ARCH)/libraries/%/*.c) \
	$(ARDUINO_LIBS:%=$(ARDUINO_HOME)/hardware/$(ARDUINO_VENDOR)/$(ARDUINO_ARCH)/libraries/%/*.cpp) \
	$(ARDUINO_LIBS:%=$(ARDUINO_HOME)/hardware/$(ARDUINO_VENDOR)/$(ARDUINO_ARCH)/libraries/%/src/*.c) \
	$(ARDUINO_LIBS:%=$(ARDUINO_HOME)/hardware/$(ARDUINO_VENDOR)/$(ARDUINO_ARCH)/libraries/%/src/*.cpp))))

# user libraries and sketch code
ULIBDIRS = . $(EXTRA_SRC) $(sort $(dir $(wildcard \
	$(USER_LIBS:%=$(USER_LIBDIR)/%/*.c) \
	$(USER_LIBS:%=$(USER_LIBDIR)/%/*.cpp) \
	$(USER_LIBS:%=$(USER_LIBDIR)/%/src/*.c) \
	$(USER_LIBS:%=$(USER_LIBDIR)/%/src/*.cpp))))

# all sources
LIB_SRC = $(wildcard $(addsuffix /*.c,$(ULIBDIRS))) \
	$(wildcard $(addsuffix /*.c,$(ALIBDIRS)))
LIB_CXXSRC = $(wildcard $(addsuffix /*.cpp,$(ULIBDIRS))) \
	$(wildcard $(addsuffix /*.cpp,$(ALIBDIRS)))

# object files
OBJ_FILES = $(addprefix $(BUILD_DIR)/,$(notdir $(LIB_SRC:.c=.c.o) $(LIB_CXXSRC:.cpp=.cpp.o)))

DEFINES = -D__ets__ -DICACHE_FLASH -U__STRICT_ANSI__ \
	-DF_CPU=$(F_CPU) -DARDUINO=$(ARDUINO_VERSION) \
	-DARDUINO_$(ARDUINO_BOARD) -DESP8266 \
	-DARDUINO_ARCH_$(shell echo "$(ARDUINO_ARCH)" | tr '[:lower:]' '[:upper:]') \
	-DDEBUG_BAUD=$(SERIAL_BAUD) \
	-I$(ESPRESSIF_SDK)/include

CORE_INC = $(ARDUINO_CORE)/cores/$(ARDUINO_ARCH) \
	$(ARDUINO_CORE)/variants/$(ARDUINO_VARIANT) \
# can't figure this out
CORE_INC += $(ARDUINO_CORE)/cores/$(ARDUINO_ARCH)/spiffs

INCLUDES = $(CORE_INC:%=-I%) $(ALIBDIRS:%=-I%) $(ULIBDIRS:%=-I%)
VPATH = . $(CORE_INC) $(ALIBDIRS) $(ULIBDIRS)

ASFLAGS = -c -g -x assembler-with-cpp -MMD $(DEFINES)
CFLAGS = -c -Os -g -Wpointer-arith -Wno-implicit-function-declaration -Wl,-EL \
	-fno-inline-functions -nostdlib -mlongcalls -mtext-section-literals \
	-falign-functions=4 -MMD -std=gnu99 -Wfatal-errors
CXXFLAGS = -c -Os -mlongcalls -mtext-section-literals -fno-exceptions \
	-fno-rtti -falign-functions=4 -std=c++11 -MMD -Wfatal-errors
LDFLAGS = -g -Os -nostdlib -Wl,--no-check-sections -u call_user_start -Wl,-static \
	-Wl,-wrap,system_restart_local -Wl,-wrap,register_chipv6_phy

CC := $(XTENSA_TOOLCHAIN)xtensa-lx106-elf-gcc
CXX := $(XTENSA_TOOLCHAIN)xtensa-lx106-elf-g++
AR := $(XTENSA_TOOLCHAIN)xtensa-lx106-elf-ar
LD := $(XTENSA_TOOLCHAIN)xtensa-lx106-elf-gcc
OBJDUMP := $(XTENSA_TOOLCHAIN)xtensa-lx106-elf-objdump

.PHONY: all arduino dirs clean flash monitor

all: dirs core libs bin

arduino:
	@mkdir -p $(BUILD_DIR)/arduino
	$(ARDUINO_BIN) --verbose --upload \
		--board $(ARDUINO_VENDOR):$(ARDUINO_ARCH):$(ARDUINO_VARIANT) \
		--port $(SERIAL_PORT) \
		--pref build.path=$(BUILD_DIR)/arduino \
		--pref sketchbook.path=$(realpath ./) \
		$(TARGET).ino

dirs:
	@mkdir -p $(OUTPUT_DIR)
	@mkdir -p $(BUILD_DIR)
	@mkdir -p $(BUILD_DIR)/arduino

clean:
	rm -rf $(BUILD_DIR)/* || true
	rm $(OUTPUT_DIR)/rom0.bin $(OUTPUT_DIR)/rom1.bin || true

core: dirs build/core.a

libs: dirs $(OBJ_FILES)

bin: $(OUTPUT_DIR)/rom0.bin $(OUTPUT_DIR)/rom1.bin

ESPTOOL_PY_FLAGS = --port $(SERIAL_PORT) --baud $(ESPTOOL_BAUD)
ESPTOOL_PY_OLIMEX = -fs 16m -ff 40m -fm qio
ESPTOOL_PY_ESP12 = -fs 32m -ff 40m -fm qio
ESPTOOL_PY_ESP12E = -fs 32m -ff 40m -fm dio

ESPTOOL_PY_FLASHOPTS ?= $(ESPTOOL_PY_ESP12)

flash: $(OUTPUT_DIR)/rom0.bin $(OUTPUT_DIR)/rom1.bin
	$(ESPTOOL_PY) $(ESPTOOL_PY_FLAGS) write_flash \
		$(ESPTOOL_PY_FLASHOPTS) \
		0x02000 $(OUTPUT_DIR)/rom0.bin \
		0x82000 $(OUTPUT_DIR)/rom1.bin

flash_rboot:
	$(ESPTOOL_PY) $(ESPTOOL_PY_FLAGS) write_flash\
		$(ESPTOOL_PY_FLASHOPTS) \
		0x00000 $(RBOOTFW_DIR)/rboot.bin

monitor:
	./monitor.py --port $(SERIAL_PORT) --baud $(SERIAL_BAUD)

$(BUILD_DIR)/%.o: $(ARDUINO_CORE)/cores/$(ARDUINO_ARCH)/%.c
	$(CC) $(DEFINES) $(CORE_INC:%=-I%) $(CFLAGS) -o $@ $<

# ugly, someone fix this
$(BUILD_DIR)/%.o: $(ARDUINO_CORE)/cores/$(ARDUINO_ARCH)/spiffs/%.c
	$(CC) $(DEFINES) $(CORE_INC:%=-I%) $(CFLAGS) -o $@ $<

$(BUILD_DIR)/%.o: $(ARDUINO_CORE)/cores/$(ARDUINO_ARCH)/%.cpp
	$(CXX) $(DEFINES) $(CORE_INC:%=-I%) $(CXXFLAGS) -o $@ $<

$(BUILD_DIR)/%.S.o: $(ARDUINO_CORE)/cores/$(ARDUINO_ARCH)/%.S
	$(CC) $(ASFLAGS) -o $@ $<

$(BUILD_DIR)/core.a: $(CORE_OBJS)
	$(AR) cru $@ $(CORE_OBJS)

$(BUILD_DIR)/%.c.o: %.c
	$(CC) $(DEFINES) $(CFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/%.cpp.o: %.cpp
	$(CXX) $(DEFINES) $(CXXFLAGS) $(INCLUDES) $< -o $@

LDEXTRAFLAGS = -L$(ESPRESSIF_SDK)/lib -L$(BUILD_DIR) -L./ld
LD_LIBS = -lm -lgcc -lhal -lphy -lnet80211 -llwip -lwpa -lmain -lpp -lsmartconfig

$(BUILD_DIR)/$(TARGET)_%.elf: $(BUILD_DIR)/core.a $(OBJ_FILES)
	$(LD) $(LDFLAGS) $(LDEXTRAFLAGS) -Trom$*.ld \
		-o $@ -Wl,--start-group $(OBJ_FILES) $(BUILD_DIR)/core.a $(LD_LIBS) \
		-Wl,--end-group

$(OUTPUT_DIR)/rom%.bin: $(BUILD_DIR)/$(TARGET)_%.elf
	$(ESPTOOL2) -quiet -bin -boot2 $^ $@ .text .data .rodata

-include $(BUILD_DIR)/*.d

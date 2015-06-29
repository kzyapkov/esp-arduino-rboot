TARGET = $(notdir $(realpath .))
-include local.mk

SERIAL_PORT ?= /dev/tty.usbmodem-
SERIAL_BAUD ?= 74880
ESPTOOL_BAUD ?= 921600
ESPTOOL_RESET ?= ck

FLASH_FREQ ?= 40
FLASH_MODE ?= qio
FLASH_SIZE ?= 4096

F_CPU ?= 80000000L

# arduino installation and 3rd party hardware folder stuff
ARDUINO_HOME ?= /Users/ficeto/Desktop/ESP8266/Arduino-mine/build/macosx/work/Arduino.app/Contents/Java
ARDUINO_BIN ?= $(ARDUINO_HOME)/../../MacOS/Arduino
ARDUINO_VENDOR = esp8266com
ARDUINO_ARCH = esp8266
ARDUINO_BOARD ?= ESP8266_ESP12
ARDUINO_VARIANT ?= nodemcu
ARDUINO_CORE ?= $(ARDUINO_HOME)/hardware/$(ARDUINO_VENDOR)/$(ARDUINO_ARCH)
ARDUINO_VERSION ?= 10605

# sketch-specific
USER_LIBDIR = ./lib
#USER_LIBS = AQMath HTU21D IRremote RCSwitch
ARDUINO_LIBS = ESP8266WiFi
EXTRA_SRC =

XTENSA_TOOLCHAIN = $(ARDUINO_CORE)/tools/xtensa-lx106-elf/bin/
# XTENSA_TOOLCHAIN ?=
ESPRESSIF_SDK = $(ARDUINO_CORE)/tools/sdk
ESPTOOL = $(ARDUINO_CORE)/tools/esptool
ESPTOOL2 ?= /Users/ficeto/bin/esptool2
ESPTOOL_PY ?= /Users/ficeto/Desktop/ESP8266/espdev/bin/esptool.py
BUILD_DIR = ./build
OUTPUT_DIR = ./firmware
RBOOTFW_DIR ?= $(OUTPUT_DIR)

CORE_SSRC = $(wildcard $(ARDUINO_CORE)/cores/$(ARDUINO_ARCH)/*.S)
CORE_SRC = $(wildcard $(ARDUINO_CORE)/cores/$(ARDUINO_ARCH)/*.c) $(wildcard $(ARDUINO_CORE)/cores/$(ARDUINO_ARCH)/*/*.c)
CORE_CXXSRC = $(wildcard $(ARDUINO_CORE)/cores/$(ARDUINO_ARCH)/*.cpp)
CORE_OBJS = $(addprefix $(BUILD_DIR)/, $(notdir $(CORE_SSRC:.S=.S.o) $(CORE_SRC:.c=.c.o) $(CORE_CXXSRC:.cpp=.cpp.o)))

# arduino libraries
ALIBDIRS = $(sort $(dir $(wildcard \
	$(ARDUINO_LIBS:%=$(ARDUINO_HOME)/hardware/$(ARDUINO_VENDOR)/$(ARDUINO_ARCH)/libraries/%/*.c) \
	$(ARDUINO_LIBS:%=$(ARDUINO_HOME)/hardware/$(ARDUINO_VENDOR)/$(ARDUINO_ARCH)/libraries/%/*.cpp) \
	$(ARDUINO_LIBS:%=$(ARDUINO_HOME)/hardware/$(ARDUINO_VENDOR)/$(ARDUINO_ARCH)/libraries/%/src/*.c) \
	$(ARDUINO_LIBS:%=$(ARDUINO_HOME)/hardware/$(ARDUINO_VENDOR)/$(ARDUINO_ARCH)/libraries/%/src/*.cpp))))

# user libraries and sketch code
ULIBDIRS = . $(EXTRA_SRC) $(sort $(dir $(wildcard $(USER_LIBS:%=$(USER_LIBDIR)/%/*.c) $(USER_LIBS:%=$(USER_LIBDIR)/%/*.cpp) $(USER_LIBS:%=$(USER_LIBDIR)/%/src/*.c) $(USER_LIBS:%=$(USER_LIBDIR)/%/src/*.cpp))))

# all sources
LIB_SRC = $(wildcard $(addsuffix /*.c,$(ULIBDIRS))) $(wildcard $(addsuffix /*.c,$(ALIBDIRS)))
LIB_CXXSRC = $(wildcard $(addsuffix /*.cpp,$(ULIBDIRS))) $(wildcard $(addsuffix /*.cpp,$(ALIBDIRS)))

# object files
OBJ_FILES = $(addprefix $(BUILD_DIR)/,$(notdir $(LIB_SRC:.c=.c.o) $(LIB_CXXSRC:.cpp=.cpp.o)))

DEFINES = -D__ets__ -DICACHE_FLASH -U__STRICT_ANSI__ \
	-DF_CPU=$(F_CPU) -DARDUINO=$(ARDUINO_VERSION) \
	-DARDUINO_$(ARDUINO_BOARD) -DESP8266 \
	-DARDUINO_ARCH_$(shell echo "$(ARDUINO_ARCH)" | tr '[:lower:]' '[:upper:]') \
	-DDEBUG_BAUD=$(SERIAL_BAUD) \
	-I$(ESPRESSIF_SDK)/include

CORE_INC = $(ARDUINO_CORE)/cores/$(ARDUINO_ARCH) $(ARDUINO_CORE)/variants/$(ARDUINO_VARIANT) $(ARDUINO_CORE)/cores/$(ARDUINO_ARCH)/spiffs

INCLUDES = $(CORE_INC:%=-I%) $(ALIBDIRS:%=-I%) $(ULIBDIRS:%=-I%)
VPATH = . $(CORE_INC) $(ALIBDIRS) $(ULIBDIRS)

ASFLAGS = -c -g -x assembler-with-cpp -MMD $(DEFINES)
CFLAGS = -c -Os -g -Wpointer-arith -Wno-implicit-function-declaration -Wl,-EL -fno-inline-functions -nostdlib -mlongcalls -mtext-section-literals -falign-functions=4 -MMD -std=gnu99 -Wfatal-errors
CXXFLAGS = -c -Os -mlongcalls -mtext-section-literals -fno-exceptions -fno-rtti -falign-functions=4 -std=c++11 -MMD -Wfatal-errors
LDFLAGS = -g -Os -nostdlib -Wl,--no-check-sections -u call_user_start -Wl,-static -Wl,-wrap,system_restart_local -Wl,-wrap,register_chipv6_phy

RBOOTCFLAGS = -Os -O3 -Wpointer-arith -Wundef -Werror -Wl,-EL -fno-inline-functions -nostdlib -mlongcalls -mtext-section-literals  -D__ets__ -DICACHE_FLASH
RBOOTLDFLAGS = -nostdlib -Wl,--no-check-sections -u call_user_start -Wl,-static

CC := $(XTENSA_TOOLCHAIN)xtensa-lx106-elf-gcc
CXX := $(XTENSA_TOOLCHAIN)xtensa-lx106-elf-g++
AR := $(XTENSA_TOOLCHAIN)xtensa-lx106-elf-ar
LD := $(XTENSA_TOOLCHAIN)xtensa-lx106-elf-gcc
OBJDUMP := $(XTENSA_TOOLCHAIN)xtensa-lx106-elf-objdump

.PHONY: all arduino dirs clean flash

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
	@rm -rf $(BUILD_DIR)/* || true
	@rm -rf $(OUTPUT_DIR)/* || true
	@rm -rf rboot/rboot-hex2a.h || true

core: dirs build/core.a

libs: dirs $(OBJ_FILES)

bin: $(OUTPUT_DIR)/rboot.bin $(OUTPUT_DIR)/rom0.bin $(OUTPUT_DIR)/rom1.bin

flash: all
	$(ESPTOOL) -vv -cd $(ESPTOOL_RESET) -cp $(SERIAL_PORT) -cb $(ESPTOOL_BAUD) -ca 0x00000 -cf $(RBOOTFW_DIR)/rboot.bin -ca 0x02000 -cf $(RBOOTFW_DIR)/rom0.bin -ca 0x82000 -cf $(RBOOTFW_DIR)/rom1.bin

$(BUILD_DIR)/%.o: $(ARDUINO_CORE)/cores/$(ARDUINO_ARCH)/%.c
	$(CC) $(DEFINES) $(CORE_INC:%=-I%) $(CFLAGS) -o $@ $<

# ugly, someone fix this
$(BUILD_DIR)/%.o: $(ARDUINO_CORE)/cores/$(ARDUINO_ARCH)/spiffs/%.c
	$(CC) $(DEFINES) $(CORE_INC:%=-I%) $(CFLAGS) -o $@ $<

$(BUILD_DIR)/%.o: $(ARDUINO_CORE)/cores/$(ARDUINO_ARCH)/%.cpp
	$(CXX) $(DEFINES) $(CORE_INC:%=-I%) $(CXXFLAGS) -o $@ $<

$(BUILD_DIR)/%.S.o: $(ARDUINO_CORE)/cores/$(ARDUINO_ARCH)/%.S
	$(CC) $(ASFLAGS) $(CORE_INC:%=-I%) -o $@ $<

$(BUILD_DIR)/core.a: $(CORE_OBJS)
	$(AR) cru $@ $(CORE_OBJS)

$(BUILD_DIR)/%.c.o: %.c
	$(CC) $(DEFINES) $(CFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/%.cpp.o: %.cpp
	$(CXX) $(DEFINES) $(CXXFLAGS) $(INCLUDES) $< -o $@

LDEXTRAFLAGS = -L$(ESPRESSIF_SDK)/lib -L$(BUILD_DIR) -L./ld
LD_LIBS = -lm -lgcc -lhal -lphy -lnet80211 -llwip -lwpa -lmain -lpp -lsmartconfig

$(BUILD_DIR)/$(TARGET)_%.elf: $(BUILD_DIR)/core.a $(OBJ_FILES)
	$(LD) $(LDFLAGS) $(LDEXTRAFLAGS) -Trom$*.ld -o $@ -Wl,--start-group $(OBJ_FILES) $(BUILD_DIR)/core.a $(LD_LIBS) -Wl,--end-group

$(OUTPUT_DIR)/rom%.bin: $(BUILD_DIR)/$(TARGET)_%.elf
	$(ESPTOOL2) -quiet -bin -boot2 -$(FLASH_SIZE) -$(FLASH_FREQ) -$(FLASH_MODE) $^ $@ .text .data .rodata

$(OUTPUT_DIR)/rboot.bin:
	$(CC) $(RBOOTCFLAGS) -c rboot/rboot-stage2a.c -o $(BUILD_DIR)/rboot-stage2a.o
	$(LD) -Trboot-stage2a.ld $(RBOOTLDFLAGS) -Wl,--start-group $(BUILD_DIR)/rboot-stage2a.o -Wl,--end-group -o $(BUILD_DIR)/rboot-stage2a.elf
	$(ESPTOOL2) -quiet -header $(BUILD_DIR)/rboot-stage2a.elf rboot/rboot-hex2a.h .text
	$(CC) $(RBOOTCFLAGS) -c rboot/rboot.c -o $(BUILD_DIR)/rboot.o
	$(LD) -Teagle.app.v6.rboot.ld $(RBOOTLDFLAGS) -Wl,--start-group $(BUILD_DIR)/rboot.o -Wl,--end-group -o $(BUILD_DIR)/rboot.elf
	$(ESPTOOL2) -quiet -bin -boot0 -$(FLASH_SIZE) -$(FLASH_FREQ) -$(FLASH_MODE) $(BUILD_DIR)/rboot.elf $(OUTPUT_DIR)/rboot.bin .text .rodata

-include $(BUILD_DIR)/*.d

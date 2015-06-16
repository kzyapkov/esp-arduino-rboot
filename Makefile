TARGET = $(notdir $(realpath .))
-include local.mk

SERIAL_PORT ?= /dev/tty.nodemcu
SERIAL_BAUD ?= 230400

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
ESPTOOL2 ?= $(wildcard ~/bin/esptool2)
ESPTOOL_PY ?= `which esptool.py`
BUILD_DIR = ./build
OUTPUT_DIR = ./firmware

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
	-DARDUINO_$(ARDUINO_BOARD) -DESP8266 -DLWIP_OPEN_SRC\
	-DARDUINO_ARCH_$(shell echo "$(ARDUINO_ARCH)" | tr '[:lower:]' '[:upper:]') \
	-I$(ESPRESSIF_SDK)/include

CORE_INC = $(ARDUINO_CORE)/cores/$(ARDUINO_ARCH) \
	$(ARDUINO_CORE)/variants/$(ARDUINO_VARIANT) \
# can't figure this out
CORE_INC += $(ARDUINO_CORE)/cores/$(ARDUINO_ARCH)/spiffs

INCLUDES = $(CORE_INC:%=-I%) $(ALIBDIRS:%=-I%) $(ULIBDIRS:%=-I%)
VPATH = . $(CORE_INC) $(ALIBDIRS) $(ULIBDIRS)

ASFLAGS = -c -g -x assembler-with-cpp -MMD $(DEFINES)
CFLAGS = -c -Os -Wpointer-arith -Wno-implicit-function-declaration -Wl,-EL \
	-fno-inline-functions -nostdlib -mlongcalls -mtext-section-literals \
	-falign-functions=4 -MMD -std=c99
CXXFLAGS = -c -Os -mlongcalls -mtext-section-literals -fno-exceptions \
	-fno-rtti -falign-functions=4 -std=c++11 -MMD
LDFLAGS = -nostdlib -Wl,--no-check-sections -u call_user_start -Wl,-static

CC := $(XTENSA_TOOLCHAIN)xtensa-lx106-elf-gcc
CXX := $(XTENSA_TOOLCHAIN)xtensa-lx106-elf-g++
AR := $(XTENSA_TOOLCHAIN)xtensa-lx106-elf-ar
LD := $(XTENSA_TOOLCHAIN)xtensa-lx106-elf-gcc
OBJDUMP := $(XTENSA_TOOLCHAIN)xtensa-lx106-elf-objdump

.PHONY: all arduino dirs clean flash flash_app1 flash_app2

all: dirs core libs bin

arduino:
	@mkdir -p $(BUILD_DIR)/arduino
	$(ARDUINO_BIN) --verbose --upload \
		--board $(ARDUINO_VENDOR):$(ARDUINO_ARCH):$(ARDUINO_VARIANT) \
		--port $(SERIAL_PORT) \
		--pref build.path=$(BUILD_DIR)/arduino \
		--pref sketchbook.path=$(realpath ./) \
		$(TARGET).ino

# use the leftovers of the arduino build for our own linking purposes
mylink: arduino
	$(LD) \
		-nostdlib -Wl,--no-check-sections -u call_user_start -Wl,-static \
		-L$(ESPRESSIF_SDK)/lib \
		-L./ld -T./ld/app1.ld \
		-o $(BUILD_DIR)/arduino/$(TARGET)_1.cpp.elf \
		-Wl,--start-group \
		$(BUILD_DIR)/arduino/main.cpp.o \
		$(BUILD_DIR)/arduino/esp-features.cpp.o \
		$(BUILD_DIR)/arduino/udplog.cpp.o \
		$(BUILD_DIR)/arduino/ESP8266WiFi/ESP8266WiFiMulti.cpp.o \
		$(BUILD_DIR)/arduino/ESP8266WiFi/WiFiClient.cpp.o \
		$(BUILD_DIR)/arduino/ESP8266WiFi/WiFiUdp.cpp.o \
		$(BUILD_DIR)/arduino/ESP8266WiFi/WiFiServer.cpp.o \
		$(BUILD_DIR)/arduino/ESP8266WiFi/ESP8266WiFi.cpp.o \
		$(BUILD_DIR)/arduino/core.a \
		-lm -lgcc -lhal -lphy -lnet80211 -llwip -lwpa -lmain -lpp -lsmartconfig \
		-Wl,--end-group \
		-L$(BUILD_DIR)/arduino

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

ESPTOOL_PY_FLAGS = --port $(SERIAL_PORT) --baud 230400

flash:
	$(ESPTOOL_PY) $(ESPTOOL_PY_FLAGS) write_flash -fs 16m \
		0x02000 $(OUTPUT_DIR)/rom0.bin \
		0x82000 $(OUTPUT_DIR)/rom1.bin

flash_rboot:
	$(ESPTOOL_PY) $(ESPTOOL_PY_FLAGS) write_flash -fs 32m \
		0x00000 $(OUTPUT_DIR)/rboot.bin

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
LD_LIBS = -lm -lgcc -lhal -lphy -lnet80211 -llwip -lwpa -lmain -lpp -lssl -lsmartconfig

$(BUILD_DIR)/$(TARGET)_%.elf: core libs
	$(LD) $(LDFLAGS) $(LDEXTRAFLAGS) -Trom$*.ld \
		-o $@ -Wl,--start-group $(OBJ_FILES) $(BUILD_DIR)/core.a $(LD_LIBS) \
		-Wl,--end-group

$(OUTPUT_DIR)/rom%.bin: $(BUILD_DIR)/$(TARGET)_%.elf
	$(ESPTOOL2) -quiet -bin -boot2 $^ $@ .text .data .rodata

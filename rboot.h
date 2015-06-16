#ifndef __RBOOT_H__
#define __RBOOT_H__

//////////////////////////////////////////////////
// rBoot open source boot loader for ESP8266.
// richardaburton@gmail.com
//////////////////////////////////////////////////

#define CHKSUM_INIT 0xef

#define SECTOR_SIZE 0x1000
#define BOOT_CONFIG_SECTOR 1

#define BOOT_CONFIG_MAGIC 0xe1
#define BOOT_CONFIG_VERSION 0x01

// uncomment to have a checksum on the boot config
//#define BOOT_CONFIG_CHKSUM

#define MODE_STANDARD 0x00
#define MODE_GPIO_ROM 0x01

// increase if required
#define MAX_ROMS 4

// boot config structure
// rom addresses must be multiples of 0x1000 (flash sector aligned)
// only the first 8Mbit of the chip will be memory mapped so rom
// slots containing .irom0.text sections must remain below 0x100000
// slots beyond this will only be accessible via spi read calls, so
// use these for stored resources, not code
typedef struct {
	uint8 magic;		   // our magic
	uint8 version;		   // config struct version
	uint8 mode;			   // boot loader mode
	uint8 current_rom;	   // currently selected rom
	uint8 gpio_rom;		   // rom to use for gpio boot
	uint8 count;		   // number of roms in use
	uint8 unused[2];	   // padding
	uint32 roms[MAX_ROMS]; // flash addresses of the roms
#ifdef BOOT_CONFIG_CHKSUM
	uint8 chksum;		   // config chksum
#endif
} rboot_config;

#endif

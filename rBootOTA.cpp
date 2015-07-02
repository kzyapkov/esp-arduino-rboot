//Add proper header

#include <Arduino.h>
#include <IPAddress.h>
#include <ESP8266WiFi.h>

#include "rBootOTA.h"
#include "flash_utils.h"
#include "debug.h"

#define DEBUG(...)
//#define DEBUG(fmt, ...)		os_printf(fmt "\r\n", ##__VA_ARGS__)

extern "C" {
  #include "c_types.h"
  #include "ets_sys.h"
  #include "os_type.h"
  #include "osapi.h"
  #include "mem.h"
  #include "ip_addr.h"
  #include "user_interface.h"
  #include "osapi.h"
  #include "rboot/rboot.h"

  //////////////////////////////////////////////////
  // API for OTA and rBoot config, for ESP8266.
  // Copyright 2015 Richard A Burton
  // richardaburton@gmail.com
  // See rboot/license.txt for license terms.
  // OTA code based on SDK sample from Espressif.
  //////////////////////////////////////////////////

  // get the rboot config
  rboot_config ICACHE_RAM_ATTR rboot_get_config() {
    rboot_config conf;
    WDT_FEED();
    noInterrupts();
    spi_flash_read(BOOT_CONFIG_SECTOR * SECTOR_SIZE, (uint32*)&conf, sizeof(rboot_config));
    interrupts();
    return conf;
  }

  // write the rboot config
  // preserves contents of rest of sector, so rest
  // of sector can be used to store user data
  // updates checksum automatically, if enabled
  bool ICACHE_FLASH_ATTR rboot_set_config(rboot_config *conf) {
    uint8 *buffer;
  #ifdef BOOT_CONFIG_CHKSUM
    uint8 chksum;
    uint8 *ptr;
  #endif

    buffer = (uint8*)os_malloc(SECTOR_SIZE);
    if (!buffer) {
      DEBUG("No ram!\r\n");
      return false;
    }

  #ifdef BOOT_CONFIG_CHKSUM
    chksum = CHKSUM_INIT;
    for (ptr = (uint8*)conf; ptr < &conf->chksum; ptr++) {
      chksum ^= *ptr;
    }
    conf->chksum = chksum;
  #endif

    WDT_FEED();
    noInterrupts();
    spi_flash_read(BOOT_CONFIG_SECTOR * SECTOR_SIZE, (uint32*)buffer, SECTOR_SIZE);
    interrupts();

    os_memcpy(buffer, conf, sizeof(rboot_config));

    noInterrupts();
    spi_flash_erase_sector(BOOT_CONFIG_SECTOR);
    interrupts();

    noInterrupts();
    spi_flash_write(BOOT_CONFIG_SECTOR * SECTOR_SIZE, (uint32*)buffer, SECTOR_SIZE);
    interrupts();

    os_free(buffer);
    return true;
  }

  // get current boot rom
  uint8 ICACHE_FLASH_ATTR rboot_get_current_rom() {
    rboot_config conf;
    conf = rboot_get_config();
    return conf.current_rom;
  }

  // set current boot rom
  bool ICACHE_FLASH_ATTR rboot_set_current_rom(uint8 rom) {
    rboot_config conf;
    conf = rboot_get_config();
    if (rom >= conf.count) return false;
    conf.current_rom = rom;
    return rboot_set_config(&conf);
  }

  void ICACHE_FLASH_ATTR rboot_dump_config(rboot_config* c) {
    rboot_config* conf = c;
    if(!c) {
      conf = (rboot_config*)os_malloc(sizeof(rboot_config));
      *conf = rboot_get_config();
    }
    //hexdump((uint8_t*)conf, sizeof(rboot_config));

    DEBUG("bootconf.magic: %d", conf->magic);
    DEBUG("bootconf.version: %d", conf->version);
    DEBUG("bootconf.mode: %d", conf->mode);
    DEBUG("bootconf.current_rom: %d", conf->current_rom);
    DEBUG("bootconf.gpio_rom: %d", conf->gpio_rom);
    DEBUG("bootconf.count: %d", conf->count);

    if(!c) {
      os_free(conf);
    }
  }

}


/**
 * Perform an OTA update
 *
 * Use HTTP to download either /rom0.bin or /rom1.bin depending on which
 * slot is being updated. If successful -- update the rboot config and
 * reboot.
 */

#define OTA_BUF_SIZE     1536

void OTA_update(IPAddress ip, uint16_t port, const char * url) {
  static bool in_progress = false;
    if (in_progress) {
        DEBUG("OTA_update: already updating!");
        return;
    }
    in_progress = true;
    DEBUG("OTA_update: ENTER");

    WiFiClient conn;
    char* clen_pos;
    uint16_t buf_head = 0;
    uint8_t* buf;
    uint32_t current_addr;

    rboot_config bootconf = rboot_get_config();
    rboot_dump_config(&bootconf);

    uint8_t upgrade_slot = bootconf.current_rom == 0 ? 1 : 0;
    current_addr = bootconf.roms[upgrade_slot];

    DEBUG("running rom: %d, upgrade rom: %d", bootconf.current_rom, upgrade_slot);

    if (current_addr % SECTOR_SIZE) {
      DEBUG("Bad rom slot %d at 0x%x\r\n", bootconf.current_rom, current_addr);
      goto bail;
    }

    buf = (uint8_t*)os_malloc(OTA_BUF_SIZE);
    if (!buf) {
        DEBUG("OTA_update: buffer allocation failed");
        goto bail;
    }

    {   // because goto
    int n = snprintf((char*)buf, OTA_BUF_SIZE,
            "GET %s%d.bin HTTP/1.0\r\n"
            "Connection: close\r\n"
            "Cache-Control: no-cache\r\n"
            "User-Agent: rBootOTA/0.1\r\n"
            "Accept: */*\r\n\r\n", url, upgrade_slot);

    if (n < 0 || n >= OTA_BUF_SIZE) {
        DEBUG("OTA_update: header block too large, n=%d", n);
        goto bail;
    }

    DEBUG(("OTA_update: connecting to " IPSTR ":%d\r\n"), IP2STR((uint32_t)ip), port);

    if (!conn.connect(ip, port)) {
        DEBUG("OTA_update: HTTP connection failed");
        goto bail;
    }

    yield();

    // send the request
    conn.write((const uint8_t *)buf, n);
    os_memset(buf, 0, OTA_BUF_SIZE);

    DEBUG("OTA_update: request sent.");

    // buffer in the header block
    uint32_t start = millis();

    buf_head = 0;
    while (buf_head < 4 || memcmp(buf+buf_head-4, "\r\n\r\n", 4) != 0) {
        if (conn.available()) {
            buf[buf_head++] = (uint8_t) conn.read();
            if (buf_head >= OTA_BUF_SIZE) {
                DEBUG("OTA_update: buffer overflow while reading headers");
                goto bail;
            }
            continue;
        }
        if ((millis() - start) > 3000) {
            DEBUG("OTA_update: read headers timeout");
            goto bail;
        }
    }

    // extract content length
    clen_pos = os_strstr((const char*)buf, "Content-Length:");
    if (clen_pos == NULL) {
        DEBUG("OTA_update: no Content-Length header found");
        goto bail;
    }

    int rom_size = atoi(clen_pos+15);
    if (rom_size < 250 || rom_size >= 0x79000 || rom_size % 4) {
        DEBUG("OTA_update: bad rom size: %d", rom_size);
        goto bail;
    }

    size_t remaining = rom_size;
    memset(buf, 0, OTA_BUF_SIZE);
    buf_head = 0;

    uint32_t rounded_size = (rom_size + SECTOR_SIZE - 1) & (~(SECTOR_SIZE - 1));
    DEBUG("flash erase @0x%x size=0x%x", current_addr, rounded_size);
    noInterrupts();
    int rc = SPIEraseAreaEx(current_addr, rounded_size);
    interrupts();
    if (rc) {
        DEBUG("erasing flash failed: %d", rc);
        goto bail;
    }

    DEBUG("writing application to flash");
    // read data from TCP, write to flash, erasing sectors as needed
    start = millis();
    while (remaining) {

        yield();

        if (!conn.connected()) {
            DEBUG("OTA_update: connection died.");
            goto bail;
        }

        if ((millis() - start) > 60000) {
            // an update will timeout eventually
            DEBUG("timeout while reading data");
            goto bail;
        }

        if (!conn.available()) {
            continue;
        }

        while (size_t available = conn.available()) {
            if (available > remaining) {
                DEBUG("OTA_update: got more than asked for?!?!");
            }

            // min and max are undef-d in ESP8266WiFiMulti...
            // size_t chunk_len = min(available, OTA_BUF_SIZE);
            // size_t chunk_len = std::min((const size_t)available, (const size_t)OTA_BUF_SIZE);
            size_t chunk_len = available < OTA_BUF_SIZE ? available : OTA_BUF_SIZE;
            // align to 4 bytes
            uint8_t leftover = chunk_len % 4;
            chunk_len -= leftover;

            size_t got = conn.readBytes(buf, chunk_len);
            if (got != chunk_len) {
                DEBUG("read %d instead of %d, connection failed", got, chunk_len);
                goto bail;
            }
            remaining -= chunk_len;

            // DEBUG("WRITE 0x%x, %d", current_addr, chunk_len);
            if (int res = SPIWrite(current_addr, buf, chunk_len)) {
                DEBUG("flash write failed: %d", res);
                goto bail;
            }
            current_addr += chunk_len;
            DEBUG("c %d r %d a %d", chunk_len, remaining, available);
        }
    }

    // remaining should be 0 here
    if (remaining != 0) {
        DEBUG("have remaining=%d", remaining);
        goto bail;
    }

    // update current rom slot and reboot
    rboot_set_current_rom(upgrade_slot);
    DEBUG("UPGGRADE COMPLETED.\r\nWill boot rom %d", rboot_get_current_rom());
    delay(100);
    ESP.restart();
    return;
    }

    bail:
    DEBUG("OTA_update failed!");
    in_progress = false;
    if (buf) os_free(buf);
    if (conn && conn.connected()) conn.stop();
    return;
}

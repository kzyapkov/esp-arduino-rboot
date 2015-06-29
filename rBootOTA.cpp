#include <Arduino.h>
#include <IPAddress.h>
#include <ESP8266WiFi.h>

#include "rBootOTA.h"
#include "flash_utils.h"
#include "debug.h"

extern "C" {
#include "c_types.h"
#include "ets_sys.h"
#include "os_type.h"
#include "osapi.h"
#include "mem.h"
#include "ip_addr.h"
#include "user_interface.h"
#include "osapi.h"
#include "rboot-ota.h"
}

#define OTA_BUF_SIZE     1536

// #define DEBUG(...)
#define DEBUG(fmt, ...)		os_printf(fmt "\r\n", ##__VA_ARGS__)

struct {
    IPAddress server_ip;
    uint16_t server_port;
    bool in_progress;
    uint32_t current_addr;
} OTA;

void OTA_setUpdateServer(IPAddress ip, uint16_t port) {
    OTA.server_ip = ip;
    OTA.server_port = port;
}

// function to do the actual writing to flash
// returns number of leftover bytes, moved to beginning of data
static int write_flash(uint8_t *data, uint16 len) {

    uint8_t leftover = len % 4;
    uint16_t trimmed_len = len - leftover;
    if (!trimmed_len) {
        return 0;
    }
	// write current chunk
	noInterrupts();
	SpiFlashOpResult fres = spi_flash_write(OTA.current_addr, (uint32_t *)data, trimmed_len);
	interrupts();
	if (fres == SPI_FLASH_RESULT_OK) {
		OTA.current_addr += trimmed_len;
        os_memcpy(data, data+trimmed_len, leftover);
        return leftover;
	}
    // flash write fail
    return -1;
}

void dump_rboot_config(rboot_config* c) {
    rboot_config* conf = c;
    if(!c) {
        conf = (rboot_config*)os_malloc(sizeof(rboot_config));
        *conf = rboot_get_config();
    }
    hexdump((uint8_t*)conf, sizeof(rboot_config));

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

/**
 * Perform an OTA update
 *
 * Use HTTP to download either /rom0.bin or /rom1.bin depending on which
 * slot is being updated. If successful -- update the rboot config and
 * reboot.
 */
void OTA_update() {
    if (OTA.in_progress) {
        DEBUG("OTA_update: already updating!");
        return;
    }
    OTA.in_progress = true;
    DEBUG("OTA_update: ENTER");

    WiFiClient conn;
    char* clen_pos;
    uint16_t buf_head = 0;
    uint8_t* buf;

    rboot_config bootconf = rboot_get_config();
    dump_rboot_config(&bootconf);

    uint8_t upgrade_slot = bootconf.current_rom == 0 ? 1 : 0;
	OTA.current_addr = bootconf.roms[upgrade_slot];

    DEBUG("running rom: %d, upgrade rom: %d", bootconf.current_rom, upgrade_slot);

	if (OTA.current_addr % SECTOR_SIZE) {
		DEBUG("Bad rom slot %d at 0x%x\r\n", bootconf.current_rom, OTA.current_addr);
		goto bail;
	}

    buf = (uint8_t*)os_malloc(OTA_BUF_SIZE);
    if (!buf) {
        DEBUG("OTA_update: buffer allocation failed");
        goto bail;
    }

    {   // because goto
    int n = snprintf((char*)buf, OTA_BUF_SIZE,
            "GET /rom%d.bin HTTP/1.0\r\n"
            "Connection: close\r\n"
            "Cache-Control: no-cache\r\n"
            "User-Agent: rBootOTA/0.1\r\n"
            "Accept: */*\r\n\r\n", upgrade_slot);

    if (n < 0 || n >= OTA_BUF_SIZE) {
        DEBUG("OTA_update: header block too large, n=%d", n);
        goto bail;
    }

    os_printf(("OTA_update: connecting to " IPSTR ":%d\r\n"),
            IP2STR((uint32_t)OTA.server_ip), OTA.server_port);

    if (!conn.connect(OTA.server_ip, OTA.server_port)) {
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
    DEBUG("flash erase @0x%x size=0x%x", OTA.current_addr, rounded_size);
    noInterrupts();
    int rc = SPIEraseAreaEx(OTA.current_addr, rounded_size);
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

            // DEBUG("WRITE 0x%x, %d", OTA.current_addr, chunk_len);
            if (int res = SPIWrite(OTA.current_addr, buf, chunk_len)) {
                DEBUG("flash write failed: %d", res);
                goto bail;
            }
            OTA.current_addr += chunk_len;
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
    OTA.in_progress = false;
    if (buf) os_free(buf);
    if (conn && conn.connected()) conn.stop();
    return;
}


#define HTTP_HEADER "Connection: keep-alive\r\n\
Cache-Control: no-cache\r\n\
User-Agent: rBoot-Sample/1.0\r\n\
Accept: */*\r\n\r\n"

void _ota_upgrade_done(void *arg, bool result) {

    OTA.in_progress = false;
    rboot_ota *ota = (rboot_ota*)arg;
    if(result == true) {
        // success, reboot
        rboot_set_current_rom(ota->rom_slot);
        ESP.restart();
    } else {
        // fail, cleanup
        DEBUG("ota_done: UPDATE FAILED");
        os_free(ota->request);
        os_free(ota);
    }
}

void OTA_update_async() {
    // from the rboot sample project...

    if (OTA.in_progress) return;
    OTA.in_progress = true;

    uint8 slot;
    rboot_ota *ota;

    // create the update structure
    ota = (rboot_ota*)os_malloc(sizeof(rboot_ota));
    memset(ota, 0, sizeof(rboot_ota));
    os_memcpy(ota->ip, &OTA.server_ip[0], 4);
    ota->port = 8000;
    ota->callback = (ota_callback)_ota_upgrade_done;
    ota->request = (uint8 *)os_malloc(512);

    // select rom slot to flash
    slot = rboot_get_current_rom();
    if (slot == 0) slot = 1; else slot = 0;
    ota->rom_slot = slot;

    // actual http request
    os_sprintf((char*)ota->request,
        "GET /%s HTTP/1.1\r\nHost: " IPSTR "\r\n" HTTP_HEADER,
        (slot == 0 ? "rom0.bin" : "rom1.bin"),
        IP2STR(*((uint32_t*)ota->ip)));

    // start the upgrade process
    if (rboot_ota_start(ota)) {
        DEBUG("ota_update: STARTED");
    } else {
        DEBUG("ota_update: START FAILED");
        os_free(ota->request);
        os_free(ota);
        OTA.in_progress = false;
        return;
    }

    // wait for completion
    while (OTA.in_progress) delay(10);

    delay(100);
    DEBUG("upgrade must have failed");

}

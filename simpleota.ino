#include "Arduino.h"
#include "IPAddress.h"
#include "ESP8266WiFi.h"

extern "C" {

#include "c_types.h"
#include "eagle_soc.h"
#include "ets_sys.h"
#include "os_type.h"
#include "osapi.h"
#include "mem.h"
#include "user_interface.h"
#include "rboot-ota.h"

}

#include "config.h"

#ifndef BUTTON_PIN
#define BUTTON_PIN      0
#endif

bool start_update = false;
bool updating = false;
bool switch_and_reset = false;

void update_done(void* arg, bool result) {
    updating = false;
    switch_and_reset = result;
    return;

    rboot_ota* ota = (rboot_ota*)arg;

    return;
    if (result) {
        os_printf("update_done: success\r\n");
        uint8_t rom = rboot_get_current_rom();
        rboot_set_current_rom(rom == 0 ? 1 : 0);
        delay(10);
        ESP.restart();
    } else {
        os_printf("update_done: fail\r\n");
        os_free(ota->request);
        os_free(ota);
        updating = false;
    }
}

#define HTTP_HEADER "Connection: keep-alive\r\n\
Cache-Control: no-cache\r\n\
User-Agent: rBoot-Sample/1.0\r\n\
Accept: */*\r\n\r\n"

void update() {

    if (updating) return;
    updating = true;

    uint8_t slot;
    rboot_ota *ota;

    // create the update structure
    ota = (rboot_ota*)os_malloc(sizeof(rboot_ota));
    memset(ota, 0, sizeof(rboot_ota));
    IPAddress ip = IPAddress(UPDATE_HOST);
    os_memcpy(ota->ip, &ip[0], 4);
    ota->port = UPDATE_PORT;
    ota->callback = (ota_callback)update_done;
    ota->request = (uint8 *)os_malloc(512);

    // select rom slot to flash
    slot = rboot_get_current_rom();
    if (slot == 0) slot = 1; else slot = 0;
    ota->rom_slot = slot;

    // actual http request
    os_sprintf((char*)ota->request,
    	"GET /%s HTTP/1.1\r\nHost: " IPSTR "\r\n" HTTP_HEADER,
    	(slot == 0 ? "rom0.bin" : "rom1.bin"),
    	IP2STR(ota->ip));

    // start the upgrade process
    if (rboot_ota_start(ota)) {
    	os_printf("ota_update: STARTED\r\n");
    } else {
    	os_printf("ota_update: START FAILED\r\n");
    	os_free(ota->request);
    	os_free(ota);
        updating = false;
    }

}

void on_button() {
    if (!updating) start_update = true;
}

void setup() {
    Serial.begin(230400);
    Serial.setDebugOutput(true);
    WiFi.begin(SSID, PASS);
    delay(5);
    Serial.println("\r\n\r\nArduino with rboot sample");
    Serial.print("running rom ");
    Serial.println(rboot_get_current_rom());
    while(WiFi.status() != WL_CONNECTED) delay(250);
    Serial.println("ready.");
    attachInterrupt(BUTTON_PIN, on_button, FALLING);
}

void loop() {
    if (start_update && !updating) {
        start_update = false;
        update();
    }
    if (switch_and_reset) {
        switch_and_reset = false;
        Serial.println("switching rom");
        uint8_t current_rom = rboot_get_current_rom();
        Serial.print("Current rom is: ");
        Serial.println(current_rom);

        rboot_set_current_rom(current_rom == 0 ? 1 : 0);

        current_rom = rboot_get_current_rom();
        Serial.print("switched to: ");
        Serial.println(current_rom);

        ESP.restart();
    }
    delay(50);
}
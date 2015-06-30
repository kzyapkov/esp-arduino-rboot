#include <Arduino.h>
#include <IPAddress.h>
#include <ESP8266WiFi.h>
#include "rBootOTA.h"
#include "config.h"

extern "C" {
#include "ip_addr.h"
}

/*
//This is bad!
void print_success() {
    os_printf("  _____ _    _  _____ _____ ______  _____ _____ \r\n");
    os_printf(" / ____| |  | |/ ____/ ____|  ____|/ ____/ ____|\r\n");
    os_printf("| (___ | |  | | |   | |    | |__  | (___| (___  \r\n");
    os_printf(" \\___ \\| |  | | |   | |    |  __|  \\___ \\\\___ \\ \r\n");
    os_printf(" ____) | |__| | |___| |____| |____ ____) |___) |\r\n");
    os_printf("|_____/ \\____/ \\_____\\_____|______|_____/_____/ \r\n");
}
*/

#ifndef BUTTON_PIN
#define BUTTON_PIN      5
#endif

//can make all/some static and change them when needed
const IPAddress ota_server(UPDATE_HOST);
const uint16_t ota_port = UPDATE_PORT;
const char * ota_url = UPDATE_URL;

bool start_update = false;
void on_button() {
    start_update = true;
}

void setup() {
    Serial.begin(DEBUG_BAUD);
    Serial.setDebugOutput(true);
    delay(5);
    Serial.println("\r\n\r\nArduino with rboot sample");
    Serial.print("running rom ");
    Serial.println(rboot_get_current_rom());
    WiFi.begin(SSID, PASS);
    if(WiFi.waitForConnectResult() == WL_CONNECTED){
      Serial.printf("Connected to %s\n", SSID);
    }
    attachInterrupt(BUTTON_PIN, on_button, FALLING);
}

void loop() {
    if (start_update) {
        start_update = false;
        Serial.printf("OTA_update: http://" IPSTR ":%d%s%u.bin\r\n", IP2STR((uint32_t)ota_server), ota_port, ota_url, !rboot_get_current_rom());
        OTA_update(ota_server, ota_port, ota_url);
    }
    delay(50);
}

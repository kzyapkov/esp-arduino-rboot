#include <Arduino.h>
#include <IPAddress.h>
#include <ESP8266WiFi.h>
#include "rBootOTA.h"
#include "config.h"

#ifndef BUTTON_PIN
#define BUTTON_PIN      0
#endif



void print_success() {
    os_printf("  _____ _    _  _____ _____ ______  _____ _____ \r\n");
    os_printf(" / ____| |  | |/ ____/ ____|  ____|/ ____/ ____|\r\n");
    os_printf("| (___ | |  | | |   | |    | |__  | (___| (___  \r\n");
    os_printf(" \\___ \\| |  | | |   | |    |  __|  \\___ \\\\___ \\ \r\n");
    os_printf(" ____) | |__| | |___| |____| |____ ____) |___) |\r\n");
    os_printf("|_____/ \\____/ \\_____\\_____|______|_____/_____/ \r\n");
}

bool start_update = false;
void on_button() {
    start_update = true;
}

void setup() {
    Serial.begin(DEBUG_BAUD);
    Serial.setDebugOutput(true);
    OTA_setUpdateServer(IPAddress(UPDATE_HOST), UPDATE_PORT);
    WiFi.begin(SSID, PASS);
    delay(5);
    Serial.println("\r\n\r\nArduino with rboot sample");
    Serial.print("running rom ");
    Serial.println(rboot_get_current_rom());
    while(WiFi.status() != WL_CONNECTED) delay(250);
    Serial.printf("Connected to %s", SSID);
    attachInterrupt(BUTTON_PIN, on_button, FALLING);
}

void loop() {
    if (start_update) {
        start_update = false;
        OTA_update();
    }
    delay(50);
}

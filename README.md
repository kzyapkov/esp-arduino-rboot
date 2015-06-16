# ESP8266/Arduino with rboot

This repository tries to show how to use the excellent arduino core and
libraries from [esp8266.com](https://github.com/esp8266/Arduino) with the
open source [rboot](https://github.com/raburton/esp8266) bootloader by
Richard Antony Burton.

# How to

 * Build `rboot`, upload it to 0x00000
 * Edit the top of `Makefile`, set the location of the Arduino custom
   hardware folder, change other settings as needed
 * Copy `config.h.sample` to `config.h`, edit for your network
 * Run `make`, `make flash`
 * Trigger an update by bringing BUTTON_PIN low.
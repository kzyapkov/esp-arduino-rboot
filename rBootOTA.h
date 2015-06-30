//Add proper header

#ifndef _RBOOT_OTA_H
#define _RBOOT_OTA_H

#include "Arduino.h"
#include "IPAddress.h"

#ifdef __cplusplus
extern "C" {
#endif

#include "rboot/rboot.h"

//////////////////////////////////////////////////
// API for OTA and rBoot config, for ESP8266.
// Copyright 2015 Richard A Burton
// richardaburton@gmail.com
// See license.txt for license terms.
// OTA code based on SDK sample from Espressif.
//////////////////////////////////////////////////

void rboot_dump_config(rboot_config*);
rboot_config rboot_get_config();
bool rboot_set_config(rboot_config *conf);
uint8  rboot_get_current_rom();
bool rboot_set_current_rom(uint8 rom);

#ifdef __cplusplus
}
#endif

void OTA_update(IPAddress ip, uint16_t port, const char * url);

#endif //_RBOOT_OTA_H

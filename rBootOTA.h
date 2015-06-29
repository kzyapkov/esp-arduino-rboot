#include "Arduino.h"
#include "IPAddress.h"
#ifdef __cplusplus

extern "C" {
#endif
#include "rboot-ota.h"
#ifdef __cplusplus
}
#endif

void OTA_setUpdateServer(IPAddress ip, uint16_t port);
void OTA_update();
void OTA_update_async();

void dump_rboot_config(rboot_config*);

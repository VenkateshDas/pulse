#ifndef CPULSE_H
#define CPULSE_H

#include <libproc.h>
#include <stdint.h>
#include <sys/proc_info.h>
#include <sys/sysctl.h>

/* AppleSMC user-client wire format (kSMCHandleYPCEvent, selector 2).
   Layout must match the kext exactly — defined in C so Swift can't
   reorder or pad it differently. */

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved[1];
    uint16_t release;
} PulseSMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} PulseSMCPLimit;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} PulseSMCKeyInfo;

typedef struct {
    uint32_t key;
    PulseSMCVersion vers;
    PulseSMCPLimit pLimitData;
    PulseSMCKeyInfo keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} PulseSMCKeyData;

enum {
    kPulseSMCUserClientOpen = 0,
    kPulseSMCHandleYPCEvent = 2,
    kPulseSMCReadKey = 5,
    kPulseSMCGetKeyFromIndex = 8,
    kPulseSMCGetKeyInfo = 9,
};

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include "DDC.h"

extern double CoreDisplay_Display_GetUserBrightness(CGDirectDisplayID display) __attribute__((weak_import));
extern void CoreDisplay_Display_SetUserBrightness(CGDirectDisplayID display, double brightness) __attribute__((weak_import));

extern int DisplayServicesCanChangeBrightness(CGDirectDisplayID display) __attribute__((weak_import));
extern int DisplayServicesGetBrightness(CGDirectDisplayID display, float *brightness) __attribute__((weak_import));
extern int DisplayServicesSetBrightness(CGDirectDisplayID display, float brightness) __attribute__((weak_import));
extern int DisplayServicesSetLinearBrightness(CGDirectDisplayID display, float brightness) __attribute__((weak_import));

/* Fires whenever the display's brightness changes from ANY source (media
   keys handled by macOS, Control Center, auto-brightness, ramp animation).
   userInfo carries {"value": double 0...1}. The observer argument is round-
   tripped verbatim — pass the display ID so the callback knows the source. */
extern int DisplayServicesRegisterForBrightnessChangeNotifications(CGDirectDisplayID display, CGDirectDisplayID observer, CFNotificationCallback callback) __attribute__((weak_import));
extern int DisplayServicesUnregisterForBrightnessChangeNotifications(CGDirectDisplayID display, CGDirectDisplayID observer) __attribute__((weak_import));

#endif /* CPULSE_H */

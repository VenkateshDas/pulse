#include "include/cpulse.h"

/* Header-only shim; SwiftPM requires at least one compilation unit. */

#include <sys/attr.h>
#include <string.h>

/* APFS clone identity is not an inode. Zero means unavailable/unsupported. */
uint64_t pulse_clone_id(const char *path) {
    struct attrlist attributes = {0};
    attributes.bitmapcount = ATTR_BIT_MAP_COUNT;
    attributes.commonattr = ATTR_CMN_RETURNED_ATTRS;
    attributes.forkattr = ATTR_CMNEXT_CLONEID;
    struct __attribute__((packed, aligned(4))) {
        uint32_t length;
        attribute_set_t returned;
        uint64_t clone_id;
    } result = {0};
    if (getattrlist(path, &attributes, &result, sizeof(result), FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW) != 0 ||
        result.length < sizeof(result) || !(result.returned.forkattr & ATTR_CMNEXT_CLONEID)) return 0;
    return result.clone_id;
}

#ifndef PULSE_BLAKE3_H
#define PULSE_BLAKE3_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PULSE_BLAKE3_OUT_LEN 32

typedef struct pulse_blake3_opaque *pulse_blake3_ctx_t;

pulse_blake3_ctx_t pulse_blake3_create(void);
void pulse_blake3_free(pulse_blake3_ctx_t ctx);
void pulse_blake3_init(pulse_blake3_ctx_t ctx);
void pulse_blake3_update(pulse_blake3_ctx_t ctx, const void *data, size_t len);
void pulse_blake3_final(pulse_blake3_ctx_t ctx, uint8_t out[PULSE_BLAKE3_OUT_LEN]);

#ifdef __cplusplus
}
#endif

#endif /* PULSE_BLAKE3_H */

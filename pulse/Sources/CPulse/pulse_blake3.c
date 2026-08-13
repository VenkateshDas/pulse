#include "pulse_blake3.h"
#include <stdlib.h>
#include <string.h>

#define PULSE_BLAKE3_BLOCK_LEN 64

typedef struct __attribute__((aligned(64))) pulse_blake3_opaque {
    uint32_t key[8];
    uint64_t chunk_counter;
    uint8_t buf[PULSE_BLAKE3_BLOCK_LEN];
    uint8_t buf_len;
    uint8_t blocks_compressed;
    uint8_t flags;
    uint32_t cv_stack[54 * 8];
    uint8_t cv_stack_len;
} pulse_blake3_opaque;

enum blake3_flags {
    CHUNK_START         = 1 << 0,
    CHUNK_END           = 1 << 1,
    PARENT              = 1 << 2,
    ROOT                = 1 << 3,
    KEYED_HASH          = 1 << 4,
    DERIVE_KEY_CONTEXT  = 1 << 5,
    DERIVE_KEY_MATERIAL = 1 << 6,
};

static const uint32_t IV[8] = {
    0x6A09E667UL, 0xBB67AE85UL, 0x3C6EF372UL, 0xA54FF53AUL,
    0x510E527FUL, 0x9B05688CUL, 0x1F83D9ABUL, 0x5BE0CD19UL
};

static const uint8_t MSG_SCHEDULE[7][16] = {
    {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15},
    {2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 8, 14, 15, 9},
    {3, 4, 10, 12, 13, 2, 7, 14, 6, 5, 9, 0, 11, 15, 8, 1},
    {10, 7, 12, 9, 14, 3, 13, 15, 4, 0, 1, 2, 5, 8, 11, 6},
    {12, 13, 9, 11, 15, 10, 14, 8, 7, 2, 0, 1, 3, 4, 6, 5},
    {14, 15, 11, 5, 8, 12, 9, 7, 6, 3, 2, 0, 10, 4, 13, 1},
    {11, 8, 5, 1, 7, 14, 12, 6, 13, 10, 3, 2, 15, 4, 9, 0},
};

static inline uint32_t rotr32(uint32_t w, unsigned int c) {
    return (w >> c) | (w << (32 - c));
}

static inline uint32_t load32(const void *src) {
    const uint8_t *p = (const uint8_t *)src;
    return ((uint32_t)p[0]) | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static inline void store32(void *dst, uint32_t w) {
    uint8_t *p = (uint8_t *)dst;
    p[0] = (uint8_t)(w);
    p[1] = (uint8_t)(w >> 8);
    p[2] = (uint8_t)(w >> 16);
    p[3] = (uint8_t)(w >> 24);
}

static void g(uint32_t v[16], size_t a, size_t b, size_t c, size_t d, uint32_t x, uint32_t y) {
    v[a] = v[a] + v[b] + x;
    v[d] = rotr32(v[d] ^ v[a], 16);
    v[c] = v[c] + v[d];
    v[b] = rotr32(v[b] ^ v[c], 12);
    v[a] = v[a] + v[b] + y;
    v[d] = rotr32(v[d] ^ v[a], 8);
    v[c] = v[c] + v[d];
    v[b] = rotr32(v[b] ^ v[c], 7);
}

static void round_fn(uint32_t v[16], const uint32_t m[16], size_t r) {
    const uint8_t *s = MSG_SCHEDULE[r];
    g(v, 0, 4,  8, 12, m[s[0]],  m[s[1]]);
    g(v, 1, 5,  9, 13, m[s[2]],  m[s[3]]);
    g(v, 2, 6, 10, 14, m[s[4]],  m[s[5]]);
    g(v, 3, 7, 11, 15, m[s[6]],  m[s[7]]);
    g(v, 0, 5, 10, 15, m[s[8]],  m[s[9]]);
    g(v, 1, 6, 11, 12, m[s[10]], m[s[11]]);
    g(v, 2, 7,  8, 13, m[s[12]], m[s[13]]);
    g(v, 3, 4,  9, 14, m[s[14]], m[s[15]]);
}

static void compress(const uint32_t cv[8], const uint8_t block[PULSE_BLAKE3_BLOCK_LEN],
                     uint8_t block_len, uint64_t counter, uint8_t flags, uint32_t out[16]) {
    uint32_t m[16];
    for (size_t i = 0; i < 16; i++) {
        m[i] = load32(block + i * 4);
    }
    uint32_t v[16] = {
        cv[0], cv[1], cv[2], cv[3],
        cv[4], cv[5], cv[6], cv[7],
        IV[0], IV[1], IV[2], IV[3],
        (uint32_t)counter, (uint32_t)(counter >> 32),
        (uint32_t)block_len, (uint32_t)flags
    };
    for (size_t r = 0; r < 7; r++) {
        round_fn(v, m, r);
    }
    for (size_t i = 0; i < 8; i++) {
        out[i] = v[i] ^ v[i + 8];
        out[i + 8] = v[i + 8] ^ cv[i];
    }
}

static void parent_cv(const uint32_t left_child[8], const uint32_t right_child[8],
                      const uint32_t key[8], uint8_t flags, uint32_t out[8]) {
    uint8_t block[PULSE_BLAKE3_BLOCK_LEN];
    for (size_t i = 0; i < 8; i++) {
        store32(block + i * 4, left_child[i]);
        store32(block + 32 + i * 4, right_child[i]);
    }
    uint32_t out16[16];
    compress(key, block, PULSE_BLAKE3_BLOCK_LEN, 0, flags | PARENT, out16);
    memcpy(out, out16, 32);
}

pulse_blake3_ctx_t pulse_blake3_create(void) {
    pulse_blake3_ctx_t ctx = (pulse_blake3_ctx_t)malloc(sizeof(pulse_blake3_opaque));
    if (ctx) {
        pulse_blake3_init(ctx);
    }
    return ctx;
}

void pulse_blake3_free(pulse_blake3_ctx_t ctx) {
    if (ctx) {
        free(ctx);
    }
}

void pulse_blake3_init(pulse_blake3_ctx_t ctx) {
    if (!ctx) return;
    memset(ctx, 0, sizeof(*ctx));
    memcpy(ctx->key, IV, sizeof(IV));
}

void pulse_blake3_update(pulse_blake3_ctx_t ctx, const void *data, size_t len) {
    if (!ctx || !data || len == 0) return;
    const uint8_t *src = (const uint8_t *)data;
    while (len > 0) {
        if (ctx->buf_len == PULSE_BLAKE3_BLOCK_LEN) {
            uint8_t flags = ctx->flags;
            if (ctx->blocks_compressed == 0) {
                flags |= CHUNK_START;
            }
            uint32_t out16[16];
            compress(ctx->key, ctx->buf, PULSE_BLAKE3_BLOCK_LEN, ctx->chunk_counter, flags, out16);
            memcpy(ctx->key, out16, 32);
            ctx->blocks_compressed++;
            ctx->buf_len = 0;
            
            if (ctx->blocks_compressed == 16) {
                uint32_t new_cv[8];
                memcpy(new_cv, ctx->key, 32);
                memcpy(ctx->key, IV, sizeof(IV));
                ctx->blocks_compressed = 0;
                ctx->chunk_counter++;
                
                uint32_t cur_cv[8];
                memcpy(cur_cv, new_cv, 32);
                uint64_t total_chunks = ctx->chunk_counter;
                size_t stack_idx = 0;
                while ((total_chunks & 1) == 0) {
                    parent_cv(&ctx->cv_stack[(ctx->cv_stack_len - 1 - stack_idx) * 8], cur_cv, IV, ctx->flags, cur_cv);
                    stack_idx++;
                    total_chunks >>= 1;
                }
                ctx->cv_stack_len -= (uint8_t)stack_idx;
                memcpy(&ctx->cv_stack[ctx->cv_stack_len * 8], cur_cv, 32);
                ctx->cv_stack_len++;
            }
        }
        
        size_t take = PULSE_BLAKE3_BLOCK_LEN - ctx->buf_len;
        if (take > len) take = len;
        memcpy(ctx->buf + ctx->buf_len, src, take);
        ctx->buf_len += (uint8_t)take;
        src += take;
        len -= take;
    }
}

void pulse_blake3_final(pulse_blake3_ctx_t ctx, uint8_t out[PULSE_BLAKE3_OUT_LEN]) {
    if (!ctx || !out) return;
    uint32_t last_cv[8];
    uint8_t flags = ctx->flags;
    if (ctx->blocks_compressed == 0) {
        flags |= CHUNK_START;
    }
    flags |= CHUNK_END;
    if (ctx->cv_stack_len == 0) {
        flags |= ROOT;
    }
    
    uint32_t out16[16];
    compress(ctx->key, ctx->buf, ctx->buf_len, ctx->chunk_counter, flags, out16);
    memcpy(last_cv, out16, 32);
    
    while (ctx->cv_stack_len > 0) {
        ctx->cv_stack_len--;
        uint8_t parent_flags = ctx->flags;
        if (ctx->cv_stack_len == 0) {
            parent_flags |= ROOT;
        }
        parent_cv(&ctx->cv_stack[ctx->cv_stack_len * 8], last_cv, IV, parent_flags, last_cv);
    }
    
    for (size_t i = 0; i < 8; i++) {
        store32(out + i * 4, last_cv[i]);
    }
}

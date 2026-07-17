#ifndef DAHO_STRING_H
#define DAHO_STRING_H

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <h2o.h>

// ---------------------------------------------------------
// BOUNDED UTF-8 STRING LAYOUT
// [ u32 char_len | u32 byte_len | bytes... \0 ]
// ---------------------------------------------------------
typedef struct
{
    uint32_t char_len;
    uint32_t byte_len;
    char bytes[]; // Flexible array member (lives inline in the allocation)
} daho_str_t;

// Counts Unicode code points in a UTF-8 byte array.
static inline uint32_t count_utf8_chars(const char *s, uint32_t byte_len)
{
    uint32_t count = 0;
    for (uint32_t i = 0; i < byte_len; i++)
    {
        // Count a byte only if it is NOT a UTF-8 continuation byte (10xxxxxx).
        if ((s[i] & 0xC0) != 0x80)
            count++;
    }
    return count;
}

// Standalone heap allocation. The caller is responsible for freeing it.
static inline daho_str_t *daho_str_new(const char *raw, uint32_t byte_len)
{
    daho_str_t *s = malloc(sizeof(daho_str_t) + byte_len + 1);
    s->byte_len = byte_len;
    s->char_len = count_utf8_chars(raw, byte_len);
    if (byte_len > 0 && raw != NULL)
    {
        memcpy(s->bytes, raw, byte_len);
    }
    s->bytes[byte_len] = '\0'; // Guard terminator
    return s;
}

// Pool allocation: freed automatically when the request's memory pool is
// released, so it needs no explicit free.
static inline daho_str_t *daho_str_new_pool(h2o_mem_pool_t *pool, const char *raw, uint32_t byte_len)
{
    daho_str_t *s = h2o_mem_alloc_pool(pool, sizeof(daho_str_t) + byte_len + 1);
    s->byte_len = byte_len;
    s->char_len = count_utf8_chars(raw, byte_len);
    if (byte_len > 0 && raw != NULL)
    {
        memcpy(s->bytes, raw, byte_len);
    }
    s->bytes[byte_len] = '\0'; // Guard terminator
    return s;
}

// O(1)-length-checked string comparison.
static inline int daho_str_is_equal(const daho_str_t *a, const char *raw_b, uint32_t len_b)
{
    if (a->byte_len != len_b)
        return 0;
    return memcmp(a->bytes, raw_b, len_b) == 0;
}

#endif // DAHO_STRING_H
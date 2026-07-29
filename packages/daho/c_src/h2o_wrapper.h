#ifndef H2O_WRAPPER_H
#define H2O_WRAPPER_H

#define H2O_USE_LIBUV 0

#include <stdint.h>
#include <stdatomic.h>
#include <pthread.h>
#include <h2o.h>
#include "daho_string.h"

#ifndef DART_EXPORT
#if defined(_WIN32)
#define DART_EXPORT __declspec(dllexport)
#else
#define DART_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif
#endif

#define MAX_WORKERS 64
#define MAX_STATIC_DIRS 10
#define FAST_PATH_BUCKETS 128
#define RING_SIZE 8192

// ---------------------------------------------------------
// DATA STRUCTURES
// ---------------------------------------------------------
typedef struct fast_path_node
{
    daho_str_t *path;
    daho_str_t *content_type;
    uint8_t *body;
    uint32_t body_len;
    struct fast_path_node *next;
} fast_path_node_t;

typedef struct
{
    daho_str_t *virtual_path;
    daho_str_t *local_path;
} static_dir_t;

typedef struct
{
    h2o_req_t *req;
    int status_code;
    daho_str_t **header_keys;
    daho_str_t **header_values;
    int header_count;
    uint8_t *body;
    size_t body_len;
} async_response_t;

// ---------------------------------------------------------
// DART FFI CALLBACK SIGNATURE (Updated for Bounded Strings)
// ---------------------------------------------------------
typedef void (*DartRouteCallback)(
    int64_t req_ptr,
    daho_str_t *path,
    daho_str_t *method,
    const uint8_t *body,
    int32_t body_len,
    daho_str_t *ip,
    daho_str_t **header_keys,
    daho_str_t **header_values,
    int32_t header_count,
    int32_t worker_id);

// ---------------------------------------------------------
// EXPORTED FUNCTIONS
// ---------------------------------------------------------
DART_EXPORT void add_static_path(daho_str_t *vpath, daho_str_t *lpath, int worker_id);
DART_EXPORT void add_fast_path(daho_str_t *path, daho_str_t *content_type, const uint8_t *body, int body_len, int worker_id);
DART_EXPORT void h2o_respond_from_dart(
    int64_t req_ptr, int status_code,
    daho_str_t **header_keys, daho_str_t **header_values,
    int header_count, const uint8_t *body, int body_len, int worker_id);
DART_EXPORT void start_h2o_server(int port, DartRouteCallback cb, int worker_id, int64_t max_body_size, int64_t req_timeout_ms, int64_t idle_timeout_ms,
                                   daho_str_t *tls_cert_path, daho_str_t *tls_key_path);

#endif // H2O_WRAPPER_H
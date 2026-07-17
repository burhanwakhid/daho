#include "h2o_wrapper.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <fcntl.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <time.h>

#ifndef SO_REUSEPORT
#define SO_REUSEPORT 15
#endif

// ---------------------------------------------------------
// GLOBAL VARIABLES
// ---------------------------------------------------------
static pthread_mutex_t startup_mutex = PTHREAD_MUTEX_INITIALIZER;
static fast_path_node_t *fast_path_map[MAX_WORKERS][FAST_PATH_BUCKETS];
static static_dir_t static_dirs_arr[MAX_WORKERS][MAX_STATIC_DIRS];
static int num_static_dirs_arr[MAX_WORKERS];
static DartRouteCallback dart_callbacks[MAX_WORKERS];
static int response_pipes[MAX_WORKERS][2];
static h2o_globalconf_t configs[MAX_WORKERS];
static h2o_context_t ctxs[MAX_WORKERS];
static h2o_accept_ctx_t accept_ctxs[MAX_WORKERS];
static async_response_t ring_buffers[MAX_WORKERS][RING_SIZE];
static _Atomic uint32_t ring_heads[MAX_WORKERS];
static _Atomic uint32_t ring_tails[MAX_WORKERS];

// FNV-1a hash for O(1) routing (length-bounded, no null terminator needed).
static uint32_t fnv1a(const char *s, size_t len)
{
    uint32_t h = 2166136261u;
    for (size_t i = 0; i < len; i++)
    {
        h = (h ^ (uint8_t)s[i]) * 16777619u;
    }
    return h;
}

// ---------------------------------------------------------
// REGISTRATION APIS (From Dart)
// ---------------------------------------------------------
DART_EXPORT void add_static_path(daho_str_t *vpath, daho_str_t *lpath, int worker_id)
{
    int idx = num_static_dirs_arr[worker_id];
    if (idx < MAX_STATIC_DIRS)
    {
        static_dirs_arr[worker_id][idx].virtual_path = daho_str_new(vpath->bytes, vpath->byte_len);
        static_dirs_arr[worker_id][idx].local_path = daho_str_new(lpath->bytes, lpath->byte_len);
        num_static_dirs_arr[worker_id]++;
    }
}

DART_EXPORT void add_fast_path(daho_str_t *path, daho_str_t *content_type, const uint8_t *body, int body_len, int worker_id)
{
    uint32_t hash = fnv1a(path->bytes, path->byte_len);
    uint32_t bucket = hash % FAST_PATH_BUCKETS;

    fast_path_node_t *node = malloc(sizeof(fast_path_node_t));
    node->path = daho_str_new(path->bytes, path->byte_len);
    node->content_type = daho_str_new(content_type->bytes, content_type->byte_len);

    // Copy the full body; fast-path bodies are arbitrary length.
    node->body = malloc(body_len > 0 ? body_len : 1);
    if (body_len > 0 && body != NULL)
    {
        memcpy(node->body, body, body_len);
    }
    node->body_len = body_len;

    node->next = fast_path_map[worker_id][bucket];
    fast_path_map[worker_id][bucket] = node;
}

// ---------------------------------------------------------
// WORKER EVENT LOOPS
// ---------------------------------------------------------
static void free_zero_copy_buffer(void *p)
{
    void **ptr = p;
    free(*ptr);
}

// Maps an HTTP status code to its standard reason phrase. Covers the codes
// Daho can emit; anything else falls back by class (e.g. "OK", "Error").
static const char *reason_phrase(int status)
{
    switch (status)
    {
    case 200: return "OK";
    case 201: return "Created";
    case 204: return "No Content";
    case 301: return "Moved Permanently";
    case 302: return "Found";
    case 303: return "See Other";
    case 304: return "Not Modified";
    case 400: return "Bad Request";
    case 401: return "Unauthorized";
    case 403: return "Forbidden";
    case 404: return "Not Found";
    case 405: return "Method Not Allowed";
    case 413: return "Payload Too Large";
    case 500: return "Internal Server Error";
    case 503: return "Service Unavailable";
    default:
        if (status >= 200 && status < 300) return "OK";
        if (status >= 300 && status < 400) return "Redirect";
        if (status >= 400 && status < 500) return "Client Error";
        return "Server Error";
    }
}

static void on_pipe_read(h2o_socket_t *sock, const char *err)
{
    if (err != NULL)
        return;
    int worker_id = (int)(intptr_t)sock->data;

    if (sock->input->size > 0)
    {
        h2o_buffer_consume(&sock->input, sock->input->size);
    }

    uint32_t tail = atomic_load_explicit(&ring_tails[worker_id], memory_order_relaxed);
    uint32_t head = atomic_load_explicit(&ring_heads[worker_id], memory_order_acquire);

    while (tail != head)
    {
        async_response_t res = ring_buffers[worker_id][tail % RING_SIZE];

        res.req->res.status = res.status_code;
        res.req->res.reason = reason_phrase(res.status_code);

        for (int i = 0; i < res.header_count; i++)
        {
            // Copy the header strings into the request's H2O memory pool.
            h2o_iovec_t k = h2o_strdup(&res.req->pool, res.header_keys[i]->bytes, res.header_keys[i]->byte_len);
            h2o_iovec_t v = h2o_strdup(&res.req->pool, res.header_values[i]->bytes, res.header_values[i]->byte_len);

            h2o_add_header_by_str(
                &res.req->pool, &res.req->res.headers,
                k.base, k.len, 0, NULL,
                v.base, v.len);

            // The originals are now safe to free (H2O owns its own copies).
            free(res.header_keys[i]);
            free(res.header_values[i]);
        }

        if (res.header_count > 0)
        {
            free(res.header_keys);
            free(res.header_values);
        }

        res.req->res.content_length = res.body_len;
        static h2o_generator_t dummy_generator = {NULL, NULL};
        h2o_start_response(res.req, &dummy_generator);

        // Zero-copy send of the body buffer.
        if (res.body_len > 0)
        {
            h2o_iovec_t body_vec = h2o_iovec_init(res.body, res.body_len);
            void **cleanup = h2o_mem_alloc_shared(&res.req->pool, sizeof(void *), free_zero_copy_buffer);
            *cleanup = res.body;
            h2o_send(res.req, &body_vec, 1, H2O_SEND_STATE_FINAL);
        }
        else
        {
            h2o_send(res.req, NULL, 0, H2O_SEND_STATE_FINAL);
        }

        tail++;
    }
    atomic_store_explicit(&ring_tails[worker_id], tail, memory_order_release);
}

DART_EXPORT void h2o_respond_from_dart(
    int64_t req_ptr, int status_code,
    daho_str_t **header_keys, daho_str_t **header_values,
    int header_count, const uint8_t *body, int body_len, int worker_id)
{
    async_response_t res;
    memset(&res, 0, sizeof(res));
    res.req = (h2o_req_t *)(intptr_t)req_ptr;
    res.status_code = status_code;
    res.header_count = header_count;

    if (header_count > 0)
    {
        res.header_keys = malloc(sizeof(daho_str_t *) * header_count);
        res.header_values = malloc(sizeof(daho_str_t *) * header_count);
        for (int i = 0; i < header_count; i++)
        {
            res.header_keys[i] = daho_str_new(header_keys[i]->bytes, header_keys[i]->byte_len);
            res.header_values[i] = daho_str_new(header_values[i]->bytes, header_values[i]->byte_len);
        }
    }
    res.body = (uint8_t *)body;
    res.body_len = body_len;

    // This runs on the Dart worker thread, while on_pipe_read drains the ring
    // on the evloop thread. If the ring is momentarily full, back off and retry
    // instead of silently dropping the response (which would hang the client).
    // Only after sustained overload (~100ms) do we give up and free the body.
    uint32_t head = atomic_load_explicit(&ring_heads[worker_id], memory_order_relaxed);
    uint32_t tail = atomic_load_explicit(&ring_tails[worker_id], memory_order_acquire);
    int spins = 0;
    while (head - tail >= RING_SIZE)
    {
        if (++spins > 1000)
        {
            // Give up: free the body we took ownership of and drop the response.
            if (res.body_len > 0 && res.body != NULL)
                free(res.body);
            for (int i = 0; i < header_count; i++)
            {
                free(res.header_keys[i]);
                free(res.header_values[i]);
            }
            if (header_count > 0)
            {
                free(res.header_keys);
                free(res.header_values);
            }
            return;
        }
        struct timespec backoff = {0, 100000}; // 100 microseconds
        nanosleep(&backoff, NULL);
        tail = atomic_load_explicit(&ring_tails[worker_id], memory_order_acquire);
    }

    ring_buffers[worker_id][head % RING_SIZE] = res;
    atomic_store_explicit(&ring_heads[worker_id], head + 1, memory_order_release);

    char dummy = '!';
    send(response_pipes[worker_id][1], &dummy, 1, 0);
}

static inline int get_worker_id_fast(h2o_context_t *ctx)
{
    return ctx - ctxs;
}

static int dart_route_handler(h2o_handler_t *self, h2o_req_t *req)
{
    int w_id = get_worker_id_fast(req->conn->ctx);

    // O(1) fast-path lookup by hash.
    uint32_t hash = fnv1a(req->path.base, req->path.len);
    uint32_t bucket = hash % FAST_PATH_BUCKETS;

    fast_path_node_t *node = fast_path_map[w_id][bucket];
    while (node != NULL)
    {
        if (daho_str_is_equal(node->path, req->path.base, req->path.len))
        {
            req->res.status = 200;
            req->res.reason = "OK";
            h2o_add_header(&req->pool, &req->res.headers, H2O_TOKEN_CONTENT_TYPE, NULL,
                           node->content_type->bytes, node->content_type->byte_len);
            h2o_send_inline(req, (char *)node->body, node->body_len);
            return 0;
        }
        node = node->next;
    }

    DartRouteCallback cb = dart_callbacks[w_id];
    if (cb == NULL)
        return -1;

    // Pool-allocated bounded strings (freed with the request pool).
    daho_str_t *path_str = daho_str_new_pool(&req->pool, req->path.base, req->path.len);
    daho_str_t *method_str = daho_str_new_pool(&req->pool, req->method.base, req->method.len);

    struct sockaddr_storage ss;
    socklen_t sslen = req->conn->callbacks->get_peername(req->conn, (struct sockaddr *)&ss);
    char ip_raw[INET6_ADDRSTRLEN] = "Unknown";
    if (sslen > 0)
    {
        if (ss.ss_family == AF_INET)
            inet_ntop(AF_INET, &((struct sockaddr_in *)&ss)->sin_addr, ip_raw, sizeof(ip_raw));
        else if (ss.ss_family == AF_INET6)
            inet_ntop(AF_INET6, &((struct sockaddr_in6 *)&ss)->sin6_addr, ip_raw, sizeof(ip_raw));
    }

    // Manual byte_len calculation for inet_ntop result to construct bounded string
    uint32_t ip_len = 0;
    while (ip_raw[ip_len] != '\0' && ip_len < INET6_ADDRSTRLEN)
        ip_len++;
    daho_str_t *ip_str = daho_str_new_pool(&req->pool, ip_raw, ip_len);

    size_t h_count = req->headers.size;
    daho_str_t **h_keys = h2o_mem_alloc_pool(&req->pool, sizeof(daho_str_t *) * h_count);
    daho_str_t **h_vals = h2o_mem_alloc_pool(&req->pool, sizeof(daho_str_t *) * h_count);

    for (size_t i = 0; i < h_count; ++i)
    {
        h_keys[i] = daho_str_new_pool(&req->pool, req->headers.entries[i].name->base, req->headers.entries[i].name->len);
        h_vals[i] = daho_str_new_pool(&req->pool, req->headers.entries[i].value.base, req->headers.entries[i].value.len);
    }

    // Call Dart
    cb((int64_t)(intptr_t)req, path_str, method_str, (uint8_t *)req->entity.base, req->entity.len, ip_str, h_keys, h_vals, h_count, w_id);
    return 0;
}

static void on_accept(h2o_socket_t *listener, const char *err)
{
    if (err != NULL)
        return;
    int worker_id = (int)(intptr_t)listener->data;
    h2o_socket_t *sock;
    while ((sock = h2o_evloop_socket_accept(listener)) != NULL)
    {
        h2o_accept(&accept_ctxs[worker_id], sock);
    }
}

DART_EXPORT void start_h2o_server(int port, DartRouteCallback cb, int worker_id, int64_t max_body_size, int64_t req_timeout_ms, int64_t idle_timeout_ms)
{
    // Guard against an out-of-range worker index (arrays are sized MAX_WORKERS).
    if (worker_id < 0 || worker_id >= MAX_WORKERS)
        return;

    dart_callbacks[worker_id] = cb;

    if (socketpair(AF_UNIX, SOCK_STREAM, 0, response_pipes[worker_id]) == -1)
        return;
    fcntl(response_pipes[worker_id][0], F_SETFL, O_NONBLOCK);
    fcntl(response_pipes[worker_id][1], F_SETFL, O_NONBLOCK);

    pthread_mutex_lock(&startup_mutex);

    h2o_config_init(&configs[worker_id]);
    configs[worker_id].max_request_entity_size = max_body_size;

    // Timeouts are in milliseconds; 0 means "keep H2O's default".
    if (req_timeout_ms > 0)
        configs[worker_id].http1.req_timeout = (uint64_t)req_timeout_ms;
    if (idle_timeout_ms > 0)
        configs[worker_id].http2.idle_timeout = (uint64_t)idle_timeout_ms;
    h2o_hostconf_t *hostconf = h2o_config_register_host(&configs[worker_id], h2o_iovec_init(H2O_STRLIT("default")), 65535);

    for (int i = 0; i < num_static_dirs_arr[worker_id]; i++)
    {
        // H2O config requires the null-terminator for paths; luckily our bounded string strictly enforces \0 at the end!
        h2o_pathconf_t *static_path = h2o_config_register_path(hostconf, static_dirs_arr[worker_id][i].virtual_path->bytes, 0);
        static const char *index_files[] = {"index.html", "index.htm", NULL};
        h2o_file_register(static_path, static_dirs_arr[worker_id][i].local_path->bytes, index_files, NULL, H2O_FILE_FLAG_SEND_COMPRESSED);
    }

    h2o_pathconf_t *pathconf = h2o_config_register_path(hostconf, "/", 0);
    h2o_handler_t *handler = h2o_create_handler(pathconf, sizeof(*handler));
    handler->on_req = dart_route_handler;

    h2o_evloop_t *loop = h2o_evloop_create();
    if (loop == NULL)
    {
        pthread_mutex_unlock(&startup_mutex);
        return;
    }

    h2o_context_init(&ctxs[worker_id], loop, &configs[worker_id]);
    accept_ctxs[worker_id].ctx = &ctxs[worker_id];
    accept_ctxs[worker_id].hosts = configs[worker_id].hosts;

    h2o_socket_t *pipe_sock = h2o_evloop_socket_create(loop, response_pipes[worker_id][0], 0);
    pipe_sock->data = (void *)(intptr_t)worker_id;
    h2o_socket_read_start(pipe_sock, on_pipe_read);

    atomic_init(&ring_heads[worker_id], 0);
    atomic_init(&ring_tails[worker_id], 0);

    int fd, reuseport_flag = 1, reuseaddr_flag = 1;
    if ((fd = socket(AF_INET, SOCK_STREAM, 0)) == -1)
    {
        pthread_mutex_unlock(&startup_mutex);
        return;
    }

    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK);
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuseaddr_flag, sizeof(reuseaddr_flag));
    setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &reuseport_flag, sizeof(reuseport_flag));

    int nodelay_flag = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &nodelay_flag, sizeof(nodelay_flag));

#ifdef TCP_DEFER_ACCEPT
    int defer_flag = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_DEFER_ACCEPT, &defer_flag, sizeof(defer_flag));
#endif

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(port);

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) == -1)
    {
        pthread_mutex_unlock(&startup_mutex);
        return;
    }
    if (listen(fd, SOMAXCONN) == -1)
    {
        pthread_mutex_unlock(&startup_mutex);
        return;
    }

    h2o_socket_t *sock = h2o_evloop_socket_create(loop, fd, H2O_SOCKET_FLAG_DONT_READ);
    sock->data = (void *)(intptr_t)worker_id;
    h2o_socket_read_start(sock, on_accept);

    pthread_mutex_unlock(&startup_mutex);

    printf("[C - H2O] Worker %d ready, serving traffic on port %d\n", worker_id, port);
    fflush(stdout);

    while (h2o_evloop_run(loop, INT32_MAX) == 0)
    {
    }
}
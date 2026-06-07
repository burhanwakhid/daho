#define H2O_USE_LIBUV 0

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <h2o.h>
#include <stdatomic.h>

#ifndef DART_EXPORT
#if defined(_WIN32)
#define DART_EXPORT __declspec(dllexport)
#else
#define DART_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif
#endif

#ifndef SO_REUSEPORT
#define SO_REUSEPORT 15
#endif

#define MAX_WORKERS 64
#define MAX_STATIC_DIRS 10
#define MAX_FAST_PATHS 64

// ---------------------------------------------------------
// STRUKTUR DATA FAST-PATH
// ---------------------------------------------------------
typedef struct
{
    char path[128];
    char content_type[64];
    char body[1024];
    int body_len;
} fast_path_t;

fast_path_t fast_paths[MAX_WORKERS][MAX_FAST_PATHS];
int num_fast_paths[MAX_WORKERS];

// ---------------------------------------------------------
// PERBAIKAN 1: KEMBALIKAN VARIABEL STATIC FILES
// ---------------------------------------------------------
typedef struct
{
    char virtual_path[256];
    char local_path[1024];
} static_dir_t;

static_dir_t static_dirs_arr[MAX_WORKERS][MAX_STATIC_DIRS];
int num_static_dirs_arr[MAX_WORKERS];

typedef void (*DartRouteCallback)(
    int64_t req_ptr, const char *path, const char *method,
    const uint8_t *body, int32_t body_len, const char *ip,
    const char **header_keys, const char **header_values, int32_t header_count, // INI YANG BARU
    int32_t worker_id);

DartRouteCallback dart_callbacks[MAX_WORKERS];
int response_pipes[MAX_WORKERS][2];

h2o_globalconf_t configs[MAX_WORKERS];
h2o_context_t ctxs[MAX_WORKERS];
h2o_accept_ctx_t accept_ctxs[MAX_WORKERS];

// ---------------------------------------------------------
// LOCK-FREE RING BUFFER UNTUK IPC
// ---------------------------------------------------------
#define RING_SIZE 8192
typedef struct
{
    h2o_req_t *req;
    int status_code;
    char **header_keys;
    char **header_values;
    int header_count;
    uint8_t *body;
    size_t body_len;
} async_response_t;

async_response_t ring_buffers[MAX_WORKERS][RING_SIZE];
_Atomic uint32_t ring_heads[MAX_WORKERS];
_Atomic uint32_t ring_tails[MAX_WORKERS];

DART_EXPORT void add_static_path(const char *vpath, const char *lpath, int worker_id)
{
    int idx = num_static_dirs_arr[worker_id];
    if (idx < MAX_STATIC_DIRS)
    {
        strncpy(static_dirs_arr[worker_id][idx].virtual_path, vpath, 255);
        strncpy(static_dirs_arr[worker_id][idx].local_path, lpath, 1023);
        num_static_dirs_arr[worker_id]++;
    }
}

DART_EXPORT void add_fast_path(const char *path, const char *content_type, const char *body, int body_len, int worker_id)
{
    int idx = num_fast_paths[worker_id];
    if (idx < MAX_FAST_PATHS)
    {
        strncpy(fast_paths[worker_id][idx].path, path, 127);
        strncpy(fast_paths[worker_id][idx].content_type, content_type, 63);
        memcpy(fast_paths[worker_id][idx].body, body, body_len);
        fast_paths[worker_id][idx].body_len = body_len;
        num_fast_paths[worker_id]++;
    }
}

static void free_zero_copy_buffer(void *p)
{
    void **ptr = p;
    free(*ptr);
}

static void on_pipe_read(h2o_socket_t *sock, const char *err)
{
    if (err != NULL)
        return;
    int worker_id = (int)(intptr_t)sock->data;

    // ---------------------------------------------------------
    // PERBAIKAN 2: KURAS SINYAL PIPA MENGGUNAKAN API H2O
    // ---------------------------------------------------------
    if (sock->input->size > 0)
    {
        h2o_buffer_consume(&sock->input, sock->input->size);
    }

    // AMBIL DATA DARI RAM BERSAMA (LOCK-FREE)
    uint32_t tail = atomic_load_explicit(&ring_tails[worker_id], memory_order_relaxed);
    uint32_t head = atomic_load_explicit(&ring_heads[worker_id], memory_order_acquire);

    while (tail != head)
    {
        async_response_t res = ring_buffers[worker_id][tail % RING_SIZE];

        res.req->res.status = res.status_code;
        res.req->res.reason = "OK";

        for (int i = 0; i < res.header_count; i++)
        {
            h2o_iovec_t k = h2o_strdup(&res.req->pool, res.header_keys[i], SIZE_MAX);
            h2o_iovec_t v = h2o_strdup(&res.req->pool, res.header_values[i], SIZE_MAX);
            h2o_add_header_by_str(&res.req->pool, &res.req->res.headers, k.base, k.len, 0, NULL, v.base, v.len);
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

        if (res.body_len > 0)
        {
            if (res.body_len < 8192)
            {
                h2o_send_inline(res.req, (char *)res.body, res.body_len);
                free(res.body);
            }
            else
            {
                h2o_iovec_t body_vec = h2o_iovec_init(res.body, res.body_len);
                void **cleanup = h2o_mem_alloc_shared(&res.req->pool, sizeof(void *), free_zero_copy_buffer);
                *cleanup = res.body;
                h2o_send(res.req, &body_vec, 1, H2O_SEND_STATE_FINAL);
            }
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
    int64_t req_ptr, int status_code, const char **header_keys, const char **header_values,
    int header_count, const uint8_t *body, int body_len, int worker_id)
{
    async_response_t res;
    memset(&res, 0, sizeof(res));
    res.req = (h2o_req_t *)(intptr_t)req_ptr;
    res.status_code = status_code;
    res.header_count = header_count;

    if (header_count > 0)
    {
        res.header_keys = malloc(sizeof(char *) * header_count);
        res.header_values = malloc(sizeof(char *) * header_count);
        for (int i = 0; i < header_count; i++)
        {
            res.header_keys[i] = strdup(header_keys[i]);
            res.header_values[i] = strdup(header_values[i]);
        }
    }
    res.body = (uint8_t *)body;
    res.body_len = body_len;

    uint32_t head = atomic_load_explicit(&ring_heads[worker_id], memory_order_relaxed);
    uint32_t tail = atomic_load_explicit(&ring_tails[worker_id], memory_order_relaxed);
    if (head - tail >= RING_SIZE)
    {
        return;
    }

    ring_buffers[worker_id][head % RING_SIZE] = res;
    atomic_store_explicit(&ring_heads[worker_id], head + 1, memory_order_release);

    char dummy = '!';
    send(response_pipes[worker_id][1], &dummy, 1, 0);
}

int get_worker_id(h2o_context_t *ctx)
{
    for (int i = 0; i < MAX_WORKERS; i++)
    {
        if (&ctxs[i] == ctx)
            return i;
    }
    return 0;
}

static int dart_route_handler(h2o_handler_t *self, h2o_req_t *req)
{
    int w_id = get_worker_id(req->conn->ctx);

    // NATIVE FAST-PATH
    for (int i = 0; i < num_fast_paths[w_id]; i++)
    {
        if (h2o_memis(req->path.base, req->path.len, fast_paths[w_id][i].path, strlen(fast_paths[w_id][i].path)))
        {
            req->res.status = 200;
            req->res.reason = "OK";
            h2o_add_header(&req->pool, &req->res.headers, H2O_TOKEN_CONTENT_TYPE, NULL,
                           fast_paths[w_id][i].content_type, strlen(fast_paths[w_id][i].content_type));
            h2o_send_inline(req, fast_paths[w_id][i].body, fast_paths[w_id][i].body_len);
            return 0;
        }
    }

    DartRouteCallback cb = dart_callbacks[w_id];
    if (cb == NULL)
        return -1;

    h2o_iovec_t path_pool = h2o_strdup(&req->pool, req->path.base, req->path.len);
    h2o_iovec_t method_pool = h2o_strdup(&req->pool, req->method.base, req->method.len);

    struct sockaddr_storage ss;
    socklen_t sslen = req->conn->callbacks->get_peername(req->conn, (struct sockaddr *)&ss);
    char ip_str[INET6_ADDRSTRLEN] = "Unknown";
    if (sslen > 0)
    {
        if (ss.ss_family == AF_INET)
            inet_ntop(AF_INET, &((struct sockaddr_in *)&ss)->sin_addr, ip_str, sizeof(ip_str));
        else if (ss.ss_family == AF_INET6)
            inet_ntop(AF_INET6, &((struct sockaddr_in6 *)&ss)->sin6_addr, ip_str, sizeof(ip_str));
    }
    h2o_iovec_t ip_pool = h2o_strdup(&req->pool, ip_str, strlen(ip_str));

    // -----------------------------------------------------------------
    // EKSTRAKSI SELURUH HEADERS (Zero-Allocation via Memory Pool)
    // -----------------------------------------------------------------
    size_t h_count = req->headers.size;

    // PERBAIKAN: Gunakan fungsi h2o_mem_alloc_pool!
    const char **h_keys = h2o_mem_alloc_pool(&req->pool, sizeof(char *) * h_count);
    const char **h_vals = h2o_mem_alloc_pool(&req->pool, sizeof(char *) * h_count);

    for (size_t i = 0; i < h_count; ++i)
    {
        h_keys[i] = h2o_strdup(&req->pool, req->headers.entries[i].name->base, req->headers.entries[i].name->len).base;
        h_vals[i] = h2o_strdup(&req->pool, req->headers.entries[i].value.base, req->headers.entries[i].value.len).base;
    }

    // Eksekusi callback dengan format baru
    cb((int64_t)(intptr_t)req, path_pool.base, method_pool.base, (uint8_t *)req->entity.base, req->entity.len, ip_pool.base, h_keys, h_vals, h_count, w_id);
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

DART_EXPORT void start_h2o_server(int port, DartRouteCallback cb, int worker_id, int64_t max_body_size)
{
    dart_callbacks[worker_id] = cb;

    if (socketpair(AF_UNIX, SOCK_STREAM, 0, response_pipes[worker_id]) == -1)
        return;
    fcntl(response_pipes[worker_id][0], F_SETFL, O_NONBLOCK);
    fcntl(response_pipes[worker_id][1], F_SETFL, O_NONBLOCK);

    h2o_config_init(&configs[worker_id]);
    configs[worker_id].max_request_entity_size = max_body_size;

    h2o_hostconf_t *hostconf = h2o_config_register_host(&configs[worker_id], h2o_iovec_init(H2O_STRLIT("default")), 65535);

    for (int i = 0; i < num_static_dirs_arr[worker_id]; i++)
    {
        h2o_pathconf_t *static_path = h2o_config_register_path(hostconf, static_dirs_arr[worker_id][i].virtual_path, 0);
        static const char *index_files[] = {"index.html", "index.htm", NULL};
        h2o_file_register(static_path, static_dirs_arr[worker_id][i].local_path, index_files, NULL, 0);
    }

    h2o_pathconf_t *pathconf = h2o_config_register_path(hostconf, "/", 0);
    h2o_handler_t *handler = h2o_create_handler(pathconf, sizeof(*handler));
    handler->on_req = dart_route_handler;

    h2o_evloop_t *loop = h2o_evloop_create();
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
        return;

    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK);
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuseaddr_flag, sizeof(reuseaddr_flag));
    setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &reuseport_flag, sizeof(reuseport_flag));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(port);

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) == -1)
        return;
    if (listen(fd, SOMAXCONN) == -1)
        return;

    h2o_socket_t *sock = h2o_evloop_socket_create(loop, fd, H2O_SOCKET_FLAG_DONT_READ);
    sock->data = (void *)(intptr_t)worker_id;
    h2o_socket_read_start(sock, on_accept);

    printf("[C - H2O] Worker %d siap melayani lalu lintas di port %d\n", worker_id, port);
    fflush(stdout);

    while (h2o_evloop_run(loop, INT32_MAX) == 0)
    {
    }
}
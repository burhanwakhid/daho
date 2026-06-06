#define H2O_USE_LIBUV 0

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <unistd.h>
#include <h2o.h>
#include "include/dart_api_dl.h"

#ifndef DART_EXPORT
#if defined(_WIN32)
#define DART_EXPORT __declspec(dllexport)
#else
#define DART_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif
#endif

// --- MEMORI UNTUK STATIC FILES ---
#define MAX_STATIC_DIRS 10
typedef struct
{
    char virtual_path[256];
    char local_path[1024];
} static_dir_t;

static_dir_t static_dirs[MAX_STATIC_DIRS];
int num_static_dirs = 0;

// Dipanggil oleh Dart untuk mendaftarkan folder statis
DART_EXPORT void add_static_path(const char *vpath, const char *lpath)
{
    if (num_static_dirs < MAX_STATIC_DIRS)
    {
        strncpy(static_dirs[num_static_dirs].virtual_path, vpath, 255);
        strncpy(static_dirs[num_static_dirs].local_path, lpath, 1023);
        num_static_dirs++;
    }
}
// ---------------------------------

int64_t dart_send_port = 0;
int response_pipe[2];

h2o_globalconf_t config;
h2o_context_t ctx;
h2o_accept_ctx_t accept_ctx;

typedef struct
{
    h2o_req_t *req;
    char *response_str;
} async_response_t;

DART_EXPORT void init_dart_api(void *data, int64_t port)
{
    Dart_InitializeApiDL(data);
    dart_send_port = port;
    printf("[C] FFI Async Bridge Terhubung via Port!\n");
    fflush(stdout);
}

static void send_parsed_response(h2o_req_t *req, char *response_from_dart)
{
    char *header_split = strstr(response_from_dart, "\n\n");
    char *body_ptr = response_from_dart;

    if (header_split != NULL)
    {
        *header_split = '\0';
        body_ptr = header_split + 2;

        char *saveptr;
        char *line = strtok_r(response_from_dart, "\n", &saveptr);
        if (line != NULL)
        {
            req->res.status = atoi(line);
            req->res.reason = "OK";

            while ((line = strtok_r(NULL, "\n", &saveptr)) != NULL)
            {
                char *colon = strchr(line, ':');
                if (colon != NULL)
                {
                    *colon = '\0';
                    char *key = line;
                    char *value = colon + 1;
                    while (*value == ' ')
                        value++;

                    h2o_iovec_t k = h2o_strdup(&req->pool, key, SIZE_MAX);
                    h2o_iovec_t v = h2o_strdup(&req->pool, value, SIZE_MAX);
                    h2o_add_header_by_str(&req->pool, &req->res.headers, k.base, k.len, 0, NULL, v.base, v.len);
                }
            }
        }
    }
    else
    {
        req->res.status = 500;
        req->res.reason = "Internal Error";
    }

    size_t body_len = strlen(body_ptr);
    h2o_send_inline(req, body_ptr, body_len);
}

static void on_pipe_read(h2o_socket_t *sock, const char *err)
{
    if (err != NULL)
        return;

    while (sock->input->size >= sizeof(async_response_t))
    {
        async_response_t res;
        memcpy(&res, sock->input->bytes, sizeof(async_response_t));
        h2o_buffer_consume(&sock->input, sizeof(async_response_t));

        send_parsed_response(res.req, res.response_str);
        free(res.response_str);
    }
}

DART_EXPORT void h2o_respond_from_dart(int64_t req_ptr, const char *response)
{
    async_response_t res;
    res.req = (h2o_req_t *)(intptr_t)req_ptr;
    res.response_str = strdup(response);
    send(response_pipe[1], &res, sizeof(res), 0);
}

static int dart_route_handler(h2o_handler_t *self, h2o_req_t *req)
{
    if (dart_send_port == 0)
        return -1;

    char path[2048];
    snprintf(path, sizeof(path), "%.*s", (int)req->path.len, req->path.base);
    char method[32];
    snprintf(method, sizeof(method), "%.*s", (int)req->method.len, req->method.base);

    char *body_str = "";
    if (req->entity.base != NULL && req->entity.len > 0)
    {
        body_str = malloc(req->entity.len + 1);
        memcpy(body_str, req->entity.base, req->entity.len);
        body_str[req->entity.len] = '\0';
    }

    Dart_CObject dart_req_ptr = {.type = Dart_CObject_kInt64, .value.as_int64 = (int64_t)(intptr_t)req};
    Dart_CObject dart_path = {.type = Dart_CObject_kString, .value.as_string = path};
    Dart_CObject dart_method = {.type = Dart_CObject_kString, .value.as_string = method};
    Dart_CObject dart_body = {.type = Dart_CObject_kString, .value.as_string = body_str};

    Dart_CObject *array_values[] = {&dart_req_ptr, &dart_path, &dart_method, &dart_body};
    Dart_CObject dart_msg = {.type = Dart_CObject_kArray, .value.as_array = {.length = 4, .values = array_values}};

    Dart_PostCObject_DL(dart_send_port, &dart_msg);
    if (req->entity.base != NULL && req->entity.len > 0)
        free(body_str);

    return 0;
}

static void on_accept(h2o_socket_t *listener, const char *err)
{
    h2o_socket_t *sock;
    if (err != NULL)
        return;
    while ((sock = h2o_evloop_socket_accept(listener)) != NULL)
        h2o_accept(&accept_ctx, sock);
}

DART_EXPORT void start_h2o_server(int port)
{
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, response_pipe) == -1)
        return;
    fcntl(response_pipe[0], F_SETFL, O_NONBLOCK);
    fcntl(response_pipe[1], F_SETFL, O_NONBLOCK);

    h2o_config_init(&config);
    h2o_hostconf_t *hostconf = h2o_config_register_host(&config, h2o_iovec_init(H2O_STRLIT("default")), 65535);

    // 1. DAFTARKAN RUTE STATIC FILES (H2O Zero-Copy)
    for (int i = 0; i < num_static_dirs; i++)
    {
        h2o_pathconf_t *static_path = h2o_config_register_path(hostconf, static_dirs[i].virtual_path, 0);
        static const char *index_files[] = {"index.html", "index.htm", NULL};
        // H2O secara native akan membajak request ini!
        h2o_file_register(static_path, static_dirs[i].local_path, index_files, NULL, 0);
        printf("[C] Zero-Copy Static terdaftar: %s -> %s\n", static_dirs[i].virtual_path, static_dirs[i].local_path);
    }

    // 2. DAFTARKAN RUTE DART SEBAGAI FALLBACK (Catch-All '/')
    h2o_pathconf_t *pathconf = h2o_config_register_path(hostconf, "/", 0);
    h2o_handler_t *handler = h2o_create_handler(pathconf, sizeof(*handler));
    handler->on_req = dart_route_handler;

    h2o_evloop_t *loop = h2o_evloop_create();
    h2o_context_init(&ctx, loop, &config);
    accept_ctx.ctx = &ctx;
    accept_ctx.hosts = config.hosts;

    h2o_socket_t *pipe_sock = h2o_evloop_socket_create(loop, response_pipe[0], 0);
    h2o_socket_read_start(pipe_sock, on_pipe_read);

    struct sockaddr_in addr;
    int fd, reuseaddr_flag = 1;
    if ((fd = socket(AF_INET, SOCK_STREAM, 0)) == -1)
        return;

    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);

    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuseaddr_flag, sizeof(reuseaddr_flag));
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(port);

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) == -1)
        return;
    if (listen(fd, SOMAXCONN) == -1)
        return;

    h2o_socket_t *sock = h2o_evloop_socket_create(loop, fd, H2O_SOCKET_FLAG_DONT_READ);
    h2o_socket_read_start(sock, on_accept);

    printf("[C] H2O Server berjalan di port %d\n", port);
    fflush(stdout);

    while (h2o_evloop_run(loop, INT32_MAX) == 0)
    {
    }
}
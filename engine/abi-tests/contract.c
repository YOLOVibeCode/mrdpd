/* ABI v1 contract suite (B2). Loads any dylib that exports include/mrdpd_engine.h.
 *
 * T1-GFX-01  push_frame 2×2 BGRA + poison-after-return
 * T1-SEC-04  dummy listen / MRDPD_ERR_BIND
 * T1-IN-01   scripted on_mouse / on_key via mrdpd_engine_test.h (StubEngine only)
 *
 * Usage: contract <path-to-dylib>
 * Stub-only symbols are required unless --allow-missing-stub-hooks is passed.
 */

#include "mrdpd_engine.h"
#include "mrdpd_engine_test.h"

#include <arpa/inet.h>
#include <dlfcn.h>
#include <errno.h>
#include <netinet/in.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

_Static_assert(sizeof(void *) == 8, "ABI v1 tests assume 64-bit");
_Static_assert(offsetof(MrdpdEngineConfig, bind_host) == 0, "config.bind_host");
_Static_assert(offsetof(MrdpdEngineConfig, bind_port) == 8, "config.bind_port");
_Static_assert(offsetof(MrdpdEngineConfig, cert_path) == 16, "config.cert_path");
_Static_assert(offsetof(MrdpdEngineConfig, key_path) == 24, "config.key_path");
_Static_assert(offsetof(MrdpdEngineConfig, nla_username) == 32, "config.nla_username");
_Static_assert(offsetof(MrdpdEngineConfig, nla_password) == 40, "config.nla_password");
_Static_assert(offsetof(MrdpdEngineConfig, desktop_width) == 48, "config.desktop_width");
_Static_assert(offsetof(MrdpdEngineConfig, desktop_height) == 50, "config.desktop_height");
_Static_assert(sizeof(MrdpdEngineConfig) == 56, "config size");
_Static_assert(sizeof(MrdpdFrame) == 40, "frame size");
_Static_assert(sizeof(MrdpdRect) == 16, "rect size");
_Static_assert(sizeof(MrdpdMouseEvent) == 16, "mouse size");
_Static_assert(sizeof(MrdpdKeyEvent) == 4, "key size");
_Static_assert(sizeof(MrdpdCallbacks) == 48, "callbacks size");

typedef struct Api {
    uint32_t (*abi_version)(void);
    int32_t (*start)(const MrdpdEngineConfig *, const MrdpdCallbacks *);
    int32_t (*stop)(void);
    int32_t (*push_frame)(const MrdpdFrame *);
    int32_t (*script_mouse)(const MrdpdMouseEvent *);
    int32_t (*script_key)(const MrdpdKeyEvent *);
    int32_t (*copy_last_frame)(uint8_t *, uint32_t, uint32_t *);
} Api;

static Api g_api;
static int g_fail;
static int g_pass;
static int g_require_stub_hooks = 1;

static void check(int cond, const char *file, int line, const char *msg)
{
    if (cond) {
        g_pass++;
        return;
    }
    g_fail++;
    fprintf(stderr, "FAIL %s:%d: %s\n", file, line, msg);
}

#define CHECK(cond, msg) check(!!(cond), __FILE__, __LINE__, (msg))

static void *must_dlsym(void *lib, const char *name)
{
    dlerror();
    void *sym = dlsym(lib, name);
    const char *err = dlerror();
    if (sym == NULL) {
        fprintf(stderr, "dlsym %s: %s\n", name, err ? err : "NULL");
    }
    return sym;
}

static MrdpdEngineConfig localhost_config(uint16_t port)
{
    MrdpdEngineConfig c;
    memset(&c, 0, sizeof(c));
    c.bind_host = "127.0.0.1";
    c.bind_port = port;
    c.desktop_width = 64;
    c.desktop_height = 64;
    return c;
}

static MrdpdCallbacks empty_callbacks(void)
{
    MrdpdCallbacks c;
    memset(&c, 0, sizeof(c));
    return c;
}

static void stop_quiet(void)
{
    if (g_api.stop != NULL) {
        (void)g_api.stop();
    }
}

static int listen_loopback_ephemeral(uint16_t *port_out)
{
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        return -1;
    }
    int off = 0;
    (void)setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &off, sizeof(off));
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = 0;
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        close(fd);
        return -1;
    }
    if (listen(fd, 1) != 0) {
        close(fd);
        return -1;
    }
    socklen_t len = sizeof(addr);
    if (getsockname(fd, (struct sockaddr *)&addr, &len) != 0) {
        close(fd);
        return -1;
    }
    *port_out = ntohs(addr.sin_port);
    return fd;
}

/* 1. T1-GFX-01 adjacent / ABI infra */
static void test_abi_version(void)
{
    CHECK(g_api.abi_version != NULL, "mrdpd_engine_abi_version exported");
    if (g_api.abi_version == NULL) {
        return;
    }
    CHECK(g_api.abi_version() == 1, "mrdpd_engine_abi_version() == 1");
}

/* 2. start / already-started / stop idempotent / start-stop-start */
static void test_start_stop(void)
{
    stop_quiet();
    MrdpdEngineConfig c = localhost_config(0);
    MrdpdCallbacks cb = empty_callbacks();
    CHECK(g_api.start(&c, &cb) == MRDPD_OK, "start on free port (port 0)");
    CHECK(g_api.start(&c, &cb) == MRDPD_ERR_ALREADY_STARTED, "second start");
    CHECK(g_api.stop() == MRDPD_OK, "stop");
    CHECK(g_api.stop() == MRDPD_OK, "stop idempotent");
    CHECK(g_api.start(&c, &cb) == MRDPD_OK, "start after stop");
    CHECK(g_api.stop() == MRDPD_OK, "stop after restart");
}

static void test_start_inval(void)
{
    stop_quiet();
    MrdpdEngineConfig c = localhost_config(0);
    MrdpdCallbacks cb = empty_callbacks();
    CHECK(g_api.start(NULL, &cb) == MRDPD_ERR_INVAL, "NULL config");
    CHECK(g_api.start(&c, NULL) == MRDPD_ERR_INVAL, "NULL callbacks");
    c.bind_host = NULL;
    CHECK(g_api.start(&c, &cb) == MRDPD_ERR_INVAL, "NULL bind_host");
}

/* 3. T1-SEC-04 — start on bound port → BIND */
static void test_bind_failure(void)
{
    stop_quiet();
    uint16_t port = 0;
    int holder = listen_loopback_ephemeral(&port);
    CHECK(holder >= 0 && port != 0, "test listener occupies a loopback port");
    if (holder < 0) {
        return;
    }
    MrdpdEngineConfig c = localhost_config(port);
    MrdpdCallbacks cb = empty_callbacks();
    int32_t rc = g_api.start(&c, &cb);
    CHECK(rc == MRDPD_ERR_BIND, "start on bound port → MRDPD_ERR_BIND");
    if (rc == MRDPD_OK) {
        stop_quiet();
    }
    close(holder);
}

static void test_start_cert(void)
{
    stop_quiet();
    MrdpdEngineConfig c = localhost_config(0);
    MrdpdCallbacks cb = empty_callbacks();
    c.cert_path = "/nonexistent/mrdpd-test-cert";
    c.key_path = "/nonexistent/mrdpd-test-key";
    CHECK(g_api.start(&c, &cb) == MRDPD_ERR_CERT, "unreadable cert/key → CERT");
    c.key_path = NULL;
    CHECK(g_api.start(&c, &cb) == MRDPD_ERR_INVAL, "cert without key → INVAL");
}

static void test_config_strings_copied(void)
{
    stop_quiet();
    char *host = malloc(16);
    CHECK(host != NULL, "malloc bind_host");
    if (host == NULL) {
        return;
    }
    memcpy(host, "127.0.0.1", 10);
    MrdpdEngineConfig c = localhost_config(0);
    c.bind_host = host;
    MrdpdCallbacks cb = empty_callbacks();
    CHECK(g_api.start(&c, &cb) == MRDPD_OK, "start with heap bind_host");
    free(host);
    CHECK(g_api.stop() == MRDPD_OK, "stop after freeing bind_host");
}

/* 5. push_frame before start → NOT_STARTED (run while idle) */
static void test_push_not_started(void)
{
    stop_quiet();
    uint8_t pixels[16];
    memset(pixels, 0x11, sizeof(pixels));
    MrdpdFrame fr;
    memset(&fr, 0, sizeof(fr));
    fr.width = 2;
    fr.height = 2;
    fr.stride = 8;
    fr.format = MRDP_PIXEL_BGRA8888;
    fr.pixels = pixels;
    CHECK(g_api.push_frame(&fr) == MRDPD_ERR_NOT_STARTED, "push before start");
    CHECK(g_api.push_frame(NULL) == MRDPD_ERR_NOT_STARTED || g_api.push_frame(NULL) == MRDPD_ERR_INVAL,
          "push NULL while idle is NOT_STARTED or INVAL");
}

/* 4. T1-GFX-01 — 2×2 BGRA + poison-after-return (docs/abi.md) */
static void test_push_poison(void)
{
    stop_quiet();
    MrdpdEngineConfig c = localhost_config(0);
    MrdpdCallbacks cb = empty_callbacks();
    CHECK(g_api.start(&c, &cb) == MRDPD_OK, "start for push_frame");

    uint8_t first[16];
    for (int i = 0; i < 16; i++) {
        first[i] = (uint8_t)(0x10 + i);
    }
    MrdpdFrame fr;
    memset(&fr, 0, sizeof(fr));
    fr.width = 2;
    fr.height = 2;
    fr.stride = 8;
    fr.format = MRDP_PIXEL_BGRA8888;
    fr.pixels = first;
    fr.dirty_rects = NULL;
    fr.dirty_rect_count = 0;
    CHECK(g_api.push_frame(&fr) == MRDPD_OK, "push 2×2 BGRA");

    memset(first, 0xA5, sizeof(first));

    if (g_api.copy_last_frame != NULL) {
        uint8_t stored[16];
        uint32_t n = 0;
        CHECK(g_api.copy_last_frame(stored, (uint32_t)sizeof(stored), &n) == MRDPD_OK,
              "copy last frame after poison");
        CHECK(n == 16, "stored size is stride * height");
        int poisoned = 1;
        int matches = 1;
        for (int i = 0; i < 16; i++) {
            if (stored[i] != 0xA5) {
                poisoned = 0;
            }
            if (stored[i] != (uint8_t)(0x10 + i)) {
                matches = 0;
            }
        }
        CHECK(!poisoned, "stored frame is not 0xA5 poison");
        CHECK(matches, "stored frame is the original pattern");
    } else if (g_require_stub_hooks) {
        CHECK(0, "mrdpd_stub_copy_last_frame required on StubEngine");
    }

    uint8_t second[16];
    memset(second, 0x33, sizeof(second));
    fr.pixels = second;
    CHECK(g_api.push_frame(&fr) == MRDPD_OK, "second push after poison");

    uint8_t badfmt[16];
    memset(badfmt, 0, sizeof(badfmt));
    fr.pixels = badfmt;
    fr.format = 99;
    CHECK(g_api.push_frame(&fr) == MRDPD_ERR_UNSUPPORTED, "unknown pixel format");

    CHECK(g_api.stop() == MRDPD_OK, "stop after push");
    fr.format = MRDP_PIXEL_BGRA8888;
    CHECK(g_api.push_frame(&fr) == MRDPD_ERR_NOT_STARTED, "push after stop");
}

static volatile int g_mouse_count;
static volatile int g_key_count;
static MrdpdMouseEvent g_last_mouse;
static MrdpdKeyEvent g_last_key;
static void *g_last_ud;

static void on_mouse(void *userdata, MrdpdMouseEvent event)
{
    g_last_ud = userdata;
    g_last_mouse = event;
    g_mouse_count++;
}

static void on_key(void *userdata, MrdpdKeyEvent event)
{
    g_last_ud = userdata;
    g_last_key = event;
    g_key_count++;
}

/* 6. T1-IN-01 — StubEngine scripted mouse via test header */
static void test_script_mouse(void)
{
    if (g_api.script_mouse == NULL) {
        CHECK(!g_require_stub_hooks, "mrdpd_stub_script_mouse required on StubEngine");
        return;
    }
    stop_quiet();
    g_mouse_count = 0;
    memset(&g_last_mouse, 0, sizeof(g_last_mouse));
    g_last_ud = NULL;

    int marker = 42;
    MrdpdEngineConfig c = localhost_config(0);
    MrdpdCallbacks cb = empty_callbacks();
    cb.userdata = &marker;
    cb.on_mouse = on_mouse;
    CHECK(g_api.start(&c, &cb) == MRDPD_OK, "start for scripted mouse");

    MrdpdMouseEvent ev;
    memset(&ev, 0, sizeof(ev));
    ev.x = 10;
    ev.y = 20;
    ev.buttons = 1u;
    ev.wheel = -3;
    CHECK(g_api.script_mouse(&ev) == MRDPD_OK, "script mouse");
    CHECK(g_mouse_count == 1, "on_mouse fired once");
    CHECK(g_last_ud == &marker, "userdata forwarded");
    CHECK(g_last_mouse.x == 10 && g_last_mouse.y == 20, "mouse coords");
    CHECK(g_last_mouse.buttons == 1u && g_last_mouse.wheel == -3, "buttons and wheel");

    CHECK(g_api.stop() == MRDPD_OK, "stop after mouse");
    CHECK(g_api.script_mouse(&ev) == MRDPD_ERR_NOT_STARTED, "script mouse after stop");
    usleep(50 * 1000);
    CHECK(g_mouse_count == 1, "no callback after stop returns");
}

/* 6b. T1-IN-01 — StubEngine scripted key via test header */
static void test_script_key(void)
{
    if (g_api.script_key == NULL) {
        CHECK(!g_require_stub_hooks, "mrdpd_stub_script_key required on StubEngine");
        return;
    }
    stop_quiet();
    g_key_count = 0;
    memset(&g_last_key, 0, sizeof(g_last_key));
    g_last_ud = NULL;

    int marker = 43;
    MrdpdEngineConfig c = localhost_config(0);
    MrdpdCallbacks cb = empty_callbacks();
    cb.userdata = &marker;
    cb.on_key = on_key;
    CHECK(g_api.start(&c, &cb) == MRDPD_OK, "start for scripted key");

    MrdpdKeyEvent ev;
    memset(&ev, 0, sizeof(ev));
    ev.scancode = 0x1E;
    ev.extended = 0;
    ev.pressed = 1;
    CHECK(g_api.script_key(&ev) == MRDPD_OK, "script key down");
    ev.pressed = 0;
    CHECK(g_api.script_key(&ev) == MRDPD_OK, "script key up");
    CHECK(g_key_count == 2, "on_key fired twice");
    CHECK(g_last_ud == &marker, "userdata forwarded");
    CHECK(g_last_key.scancode == 0x1E && g_last_key.pressed == 0, "last is key up");

    CHECK(g_api.stop() == MRDPD_OK, "stop after key");
    CHECK(g_api.script_key(&ev) == MRDPD_ERR_NOT_STARTED, "script key after stop");
    usleep(50 * 1000);
    CHECK(g_key_count == 2, "no key callback after stop returns");
}

static int load_api(void *lib)
{
    g_api.abi_version = (uint32_t (*)(void))must_dlsym(lib, "mrdpd_engine_abi_version");
    g_api.start = (int32_t (*)(const MrdpdEngineConfig *, const MrdpdCallbacks *))must_dlsym(
        lib, "mrdpd_engine_start");
    g_api.stop = (int32_t (*)(void))must_dlsym(lib, "mrdpd_engine_stop");
    g_api.push_frame = (int32_t (*)(const MrdpdFrame *))must_dlsym(lib, "mrdpd_engine_push_frame");
    g_api.script_mouse =
        (int32_t (*)(const MrdpdMouseEvent *))dlsym(lib, "mrdpd_stub_script_mouse");
    g_api.script_key = (int32_t (*)(const MrdpdKeyEvent *))dlsym(lib, "mrdpd_stub_script_key");
    g_api.copy_last_frame =
        (int32_t (*)(uint8_t *, uint32_t, uint32_t *))dlsym(lib, "mrdpd_stub_copy_last_frame");
    return g_api.abi_version && g_api.start && g_api.stop && g_api.push_frame;
}

int main(int argc, char **argv)
{
    const char *dylib = NULL;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--allow-missing-stub-hooks") == 0) {
            g_require_stub_hooks = 0;
        } else if (argv[i][0] != '-') {
            dylib = argv[i];
        }
    }
    if (dylib == NULL) {
        fprintf(stderr, "usage: %s <dylib> [--allow-missing-stub-hooks]\n", argv[0]);
        return 2;
    }

    void *lib = dlopen(dylib, RTLD_NOW | RTLD_LOCAL);
    if (lib == NULL) {
        fprintf(stderr, "dlopen %s: %s\n", dylib, dlerror());
        return 2;
    }
    if (!load_api(lib)) {
        fprintf(stderr, "missing production ABI symbols\n");
        return 2;
    }

    CHECK(MRDPD_OK == 0, "MRDPD_OK");
    CHECK(MRDPD_ERR_INVAL == 1, "MRDPD_ERR_INVAL");
    CHECK(MRDPD_ERR_ALREADY_STARTED == 2, "MRDPD_ERR_ALREADY_STARTED");
    CHECK(MRDPD_ERR_NOT_STARTED == 3, "MRDPD_ERR_NOT_STARTED");
    CHECK(MRDPD_ERR_BIND == 4, "MRDPD_ERR_BIND");
    CHECK(MRDPD_ERR_CERT == 5, "MRDPD_ERR_CERT");
    CHECK(MRDPD_ERR_UNSUPPORTED == 6, "MRDPD_ERR_UNSUPPORTED");
    CHECK(MRDPD_ERR_INTERNAL == 7, "MRDPD_ERR_INTERNAL");
    CHECK(MRDP_PIXEL_BGRA8888 == 1, "MRDP_PIXEL_BGRA8888");

    test_abi_version();
    test_push_not_started();
    test_start_inval();
    test_start_stop();
    test_bind_failure();
    test_start_cert();
    test_config_strings_copied();
    test_push_poison();
    test_script_mouse();
    test_script_key();

    stop_quiet();
    dlclose(lib);

    fprintf(stderr, "abi-tests: %d passed, %d failed\n", g_pass, g_fail);
    return g_fail ? 1 : 0;
}

/* Generated from docs/abi.md (ABI v1). Semantics live in the doc, not here. */
#ifndef MRDPD_ENGINE_H
#define MRDPD_ENGINE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define MRDP_PIXEL_BGRA8888 ((uint32_t)1)

#define MRDPD_OK 0
#define MRDPD_ERR_INVAL 1
#define MRDPD_ERR_ALREADY_STARTED 2
#define MRDPD_ERR_NOT_STARTED 3
#define MRDPD_ERR_BIND 4
#define MRDPD_ERR_CERT 5
#define MRDPD_ERR_UNSUPPORTED 6
#define MRDPD_ERR_INTERNAL 7

typedef struct MrdpdRect {
    int32_t x;
    int32_t y;
    uint32_t w;
    uint32_t h;
} MrdpdRect;

typedef struct MrdpdEngineConfig {
    const char *bind_host;
    uint16_t bind_port;
    const char *cert_path;
    const char *key_path;
    const char *nla_username;
    const char *nla_password;
    uint16_t desktop_width;
    uint16_t desktop_height;
} MrdpdEngineConfig;

typedef struct MrdpdFrame {
    uint32_t width;
    uint32_t height;
    uint32_t stride;
    uint32_t format;
    const uint8_t *pixels;
    const MrdpdRect *dirty_rects;
    uint32_t dirty_rect_count;
} MrdpdFrame;

typedef struct MrdpdMouseEvent {
    int32_t x;
    int32_t y;
    uint32_t buttons;
    int16_t wheel;
} MrdpdMouseEvent;

typedef struct MrdpdKeyEvent {
    uint16_t scancode;
    uint8_t extended;
    uint8_t pressed;
} MrdpdKeyEvent;

typedef struct MrdpdCallbacks {
    void *userdata;
    void (*on_mouse)(void *userdata, MrdpdMouseEvent event);
    void (*on_key)(void *userdata, MrdpdKeyEvent event);
    void (*on_client_connected)(void *userdata);
    void (*on_client_disconnected)(void *userdata, int32_t reason);
    void (*on_log)(void *userdata, int32_t level, const char *msg);
} MrdpdCallbacks;

uint32_t mrdpd_engine_abi_version(void);
int32_t mrdpd_engine_start(const MrdpdEngineConfig *config, const MrdpdCallbacks *callbacks);
int32_t mrdpd_engine_stop(void);
int32_t mrdpd_engine_push_frame(const MrdpdFrame *frame);

#ifdef __cplusplus
}
#endif

#endif

/* StubEngine-only. Not part of the production ABI in docs/abi.md.
 * The real engine dylib must not export these symbols. */
#ifndef MRDPD_ENGINE_TEST_H
#define MRDPD_ENGINE_TEST_H

#include "mrdpd_engine.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Fire one on_mouse callback with a copy of `event`. No-op if on_mouse is NULL. */
int32_t mrdpd_stub_script_mouse(const MrdpdMouseEvent *event);

/* Fire one on_key callback with a copy of `event`. No-op if on_key is NULL. */
int32_t mrdpd_stub_script_key(const MrdpdKeyEvent *event);

/* Copy the last push_frame pixel buffer (engine-owned, stride * height bytes). */
int32_t mrdpd_stub_copy_last_frame(uint8_t *out, uint32_t out_cap, uint32_t *out_len);

#ifdef __cplusplus
}
#endif

#endif

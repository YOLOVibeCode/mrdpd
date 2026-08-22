# C ABI semantics (B2)

This document is the source of truth for `include/mrdpd_engine.h`. Change this file first, then the header, then tests, then code.

ABI version for the first slice: **1**.

`mrdpd_engine_abi_version()` must return `1`. Swift EngineKit refuses to `dlopen` a dylib whose version is not exactly the version it was compiled against.

## Design rules

- C only. No C++ exceptions, no Objective-C, no Swift calling convention.
- All pointers passed from Swift to the engine are **borrowed for the duration of the call** unless a function is explicitly documented as consuming.
- The engine must not retain frame buffers, strings, or callback userdata beyond the call that supplied them, except `userdata` on `start`, which is valid until `stop` returns.
- Callbacks must not call back into the engine on the same stack (no reentrancy). Queue work instead.
- Errors are `int32_t` codes from the table below. 0 is success. No errno soup.

## Threading

| Entry | Called from | Notes |
| --- | --- | --- |
| `mrdpd_engine_abi_version` | any | pure |
| `mrdpd_engine_start` | Swift main / cooperative executor | blocks until bind succeeds or fails; must not be called twice without stop |
| `mrdpd_engine_stop` | same as start | waits until callbacks will no longer fire, then returns |
| `mrdpd_engine_push_frame` | a Swift capture/encode queue | may be called concurrently with callbacks, must not be called concurrently with itself unless documented later |
| callbacks (`on_mouse`, `on_key`, …) | engine-owned thread(s) | EngineKit hops to a known Swift executor before invoking `InputSink` |

After `stop` returns, no callback may fire. Contract tests must wait and assert silence.

## Types (logical; C layout in the header)

```text
MrdpdEngineConfig
  bind_host: const char*     // UTF-8, NUL-terminated, borrowed at start
  bind_port: uint16_t
  cert_path: const char*     // optional; NULL = engine generates ephemeral
  key_path:  const char*
  nla_username: const char*  // borrowed at start
  nla_password: const char*  // borrowed at start; engine must not log it
  desktop_width, desktop_height: uint16_t  // initial virtual desktop

MrdpdFrame
  width, height: uint32_t
  stride: uint32_t           // bytes per row, >= width * 4
  format: uint32_t           // v1: only MRDP_PIXEL_BGRA8888 = 1
  pixels: const uint8_t*     // borrowed until push_frame returns
  dirty_rects: const MrdpdRect*
  dirty_rect_count: uint32_t

MrdpdRect
  x, y: int32_t
  w, h: uint32_t

MrdpdCallbacks
  userdata: void*
  on_mouse: void(*)(void*, MrdpdMouseEvent)
  on_key: void(*)(void*, MrdpdKeyEvent)
  on_client_connected: void(*)(void*)
  on_client_disconnected: void(*)(void*, int32_t reason)
  on_log: void(*)(void*, int32_t level, const char* msg)

MrdpdMouseEvent
  x, y: int32_t              // virtual-desktop pixels
  buttons: uint32_t          // bit0 left, bit1 right, bit2 middle
  wheel: int16_t             // vertical; v1 no horizontal (T2)

MrdpdKeyEvent
  scancode: uint16_t         // RDP scancode
  extended: uint8_t          // 0/1
  pressed: uint8_t           // 1 down, 0 up
```

v1 has **no** clipboard, audio, AVC, or layout functions.

## Functions

### `uint32_t mrdpd_engine_abi_version(void)`

Always safe. Never fails.

### `int32_t mrdpd_engine_start(const MrdpdEngineConfig* config, const MrdpdCallbacks* callbacks)`

Copies what it needs from `config` and `callbacks` (the function pointers and `userdata`). Strings are copied into engine-owned buffers during `start`; the caller may free them after `start` returns.

Fails with `MRDPD_ERR_ALREADY_STARTED` if called twice.

Fails with `MRDPD_ERR_BIND` if the port cannot be bound.

Fails with `MRDPD_ERR_CERT` if cert/key paths are given but unreadable.

`NULL` config or callbacks → `MRDPD_ERR_INVAL`.

### `int32_t mrdpd_engine_stop(void)`

Idempotent. Second stop is `0`. After stop, `start` may be called again (start/stop/start is a contract test).

### `int32_t mrdpd_engine_push_frame(const MrdpdFrame* frame)`

Must not be called before `start` or after `stop` (`MRDPD_ERR_NOT_STARTED`).

`pixels` is valid **only until this function returns**. Contract tests poison the buffer after return and later force a callback or a second push; if the engine crashes or displays poison, it retained the buffer.

Empty dirty list means “full frame.”

## Error codes

| Code | Name | Meaning |
| --- | --- | --- |
| 0 | `MRDPD_OK` | success |
| 1 | `MRDPD_ERR_INVAL` | null or nonsense arguments |
| 2 | `MRDPD_ERR_ALREADY_STARTED` | start while running |
| 3 | `MRDPD_ERR_NOT_STARTED` | push/stop-path use when idle (stop still 0) |
| 4 | `MRDPD_ERR_BIND` | cannot listen |
| 5 | `MRDPD_ERR_CERT` | TLS material |
| 6 | `MRDPD_ERR_UNSUPPORTED` | pixel format or ABI misuse |
| 7 | `MRDPD_ERR_INTERNAL` | engine bug; must log via on_log |

## StubEngine behavior (normative for tests)

StubEngine is not a toy. It must:

- Export the same symbols as the real engine.
- Bind a TCP port (can be a dummy accept loop) so bind-failure tests are real.
- Accept `push_frame` and store a copy **it allocates**, never the caller pointer.
- After start, fire exactly the scripted callbacks tests request (for M0: one mouse-move when the test calls a stub-only `mrdpd_stub_script_mouse` **test symbol**, not part of the production ABI; M3 adds `mrdpd_stub_script_key`). Production engine must not export stub-only symbols.
- Alternative for production-shaped tests: the headless client in M1 drives real input; M0 uses a test-only second header `mrdpd_engine_test.h` implemented only by StubEngine.

Preferred: `mrdpd_engine_test.h` is StubEngine-only. ABI contract tests that apply to **both** dylibs never call test-only symbols. Scripted input for M0 Swift wiring uses the test header against StubEngine only. M1 input tests use a real client.

## Versioning

- Additive functions bump ABI to v2+ and require EngineKit to negotiate (exact match for now; no mixed versions in T1).
- Removing or changing a v1 struct field is forbidden; add a v2 struct instead.

## Poison-after-return test (required)

1. Allocate a 2×2 BGRA buffer, known pattern.
2. `push_frame`.
3. `memset(buffer, 0xA5, …)`.
4. `push_frame` again with a **different** live buffer, or encode/display in StubEngine.
5. Assert the engine’s stored/displayed first frame is still the original pattern, not `0xA5`.

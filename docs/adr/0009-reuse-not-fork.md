# ADR 0009: Reuse upstream and prior art; do not fork macrdp

Status: proposed (accepted when the PR that adds it merges)
Date: 2026-10-04

## Context

[clintcan/macrdp](https://github.com/clintcan/macrdp) (MIT OR Apache-2.0, ~35k lines of Rust, active) already ships most single-screen RDP polish mrdpd has not built: H.264, cursor shapes, clipboard, audio, redirection, virtual displays, and hardening ([spike R16](../spikes/2026-10-04-r16-clients-and-prior-art.md) §C). It has no multi-monitor support, one session at a time, and no display switching. Those three are exactly what the target scenario needs.

## Decision

1. **Keep mrdpd's architecture**: Swift host plus IronRDP engine behind the C ABI ([ADR 0001](0001-swift-first-hybrid.md), [0002](0002-c-abi-engine-boundary.md)). Do not fork macrdp:
   - Its core is single-display and single-session (a 4,105-line `main.rs`). Viewports would be a rewrite of its center, not an extension.
   - It is Rust with objc2 for every Apple API, the tax ADR 0001 rejected.
   - The native client ([ADR 0008](0008-native-ipad-client.md)) wants Swift code shared with the host.
2. **Use upstream IronRDP directly**: `egfx`, `nscodec`, `run_connection`, `with_honor_client_desktop_size`, RDPEDISP, and the auto-reconnect cookie (now upstream, macrdp PR #1405). Pin crates.io releases and bump deliberately.
3. **Port macrdp's macOS knowledge, with attribution** in the file header (MIT/Apache permits it):
   - VideoToolbox/EGFX settings;
   - cursor capture via SkyLight;
   - Accessibility workarounds for symbolic hotkeys (Cmd+Tab, Spotlight);
   - the macOS 26 `CGVirtualDisplay` surface;
   - keyboard layouts;
   - the mstsc blank-recovery.

   Port behavior, with tests that cite our IDs. Do not paste code without tests.
4. **Track macrdp like an upstream.** Re-check releases quarterly (R21). Send IronRDP fixes upstream as they do.

## Consequences

- Clipboard (M7), audio (M11), and redirection are re-implemented later on the viewport model, not inherited.
- If the owner needs a polished single-screen RDP server before V3 lands, macrdp works today with Windows App. The two must not listen on the same port at once.

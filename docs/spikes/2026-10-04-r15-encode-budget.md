# Spike R15: Encode budget for two simultaneous viewports

Date: 2026-10-04
Question: Can the owner's Mac (Apple M4 Max, macOS 26.6.2) hardware-encode the target scenario at the same time: a 3840×2160 viewport (the iPad's external 4K monitor) and a 2752×2064 viewport (iPad Pro 13") at 60 fps with interactive latency?
Build / version: VideoToolbox (system), `scripts/bench/encode-budget.swift`, `just bench-encode`.
What we ran: hardware-only VideoToolbox sessions; RealTime on; frame reordering off; low-latency rate control; H.264 High or HEVC Main; ~5 bits/pixel/s (41 Mbit/s at 4K, 28 Mbit/s at iPad 13"). "Speed priority" adds `MaxFrameDelayCount 0` and `PrioritizeEncodingSpeedOverQuality`. Each session is fed on its own thread, paced at 60 fps (or 30/15 where noted), for 4 s. The content is desktop-like synthetic frames: a static wallpaper, a document window whose glyph grid scrolls 12 px per frame, and a moving block. Latency is the time from submitting a frame to receiving its encoded sample.

## Evidence

H.264, speed priority (default settings give the same picture):

| Scenario | Median latency per stream | p95 |
| --- | --- | --- |
| 4K alone @60 | 82 ms | 92 ms |
| 4K alone @30 | 20 ms | 24 ms |
| iPad 13" alone @60 | 15 ms | 20 ms |
| 4K + iPad, both @60 | 82 / 14 ms | 100 / 26 ms |
| 4K as two 1920×2160 halves @60 | 11 / 11 ms | 14 / 15 ms |
| 4K halves + iPad, all @60 | 11 / 94 / 94 ms | 14 / 119 / 119 ms |
| **4K halves @60 + iPad @30** | **24 / 19 / 14 ms** | 47 / 39 / 16 ms |
| **4K @30 + iPad @60** | **20 / 15 ms** | 29 / 29 ms |
| 2560×1440 + iPad, both @60 | 10 / 15 ms | 14 / 29 ms |
| 4K + iPad + MBP built-in 3456×2234, all @60 | 207 / 207 / 207 ms | 350 ms |

HEVC behaves the same way per engine, needs ~26% less bitrate (25.9 vs 35.0 Mbit/s at 4K), is slightly slower per frame (4K alone 90 ms; halves 11.5 ms), and degrades worse when sessions share an engine.

An earlier, uncommitted run showed "4K halves + iPad @60 [speed]" at 21/21/15 ms. The committed rerun did **not** reproduce it (11/94/94 ms). Treat that run as luck in how sessions landed on engines, not as capacity.

## Answer

1. **Two hardware encode engines.** VideoToolbox places each session on one engine; a session never spans both. One engine keeps up with roughly one iPad-13"-sized frame (≈5.7 Mpx) every 16.7 ms (15 ms measured). One 4K frame takes ≈20 ms on one engine, so **4K at 60 fps needs both engines** (two tiles).
2. **Full-motion 4K60 plus iPad60 at the same time does not fit** (≈14 Mpx per frame interval against ≈11.4 Mpx of capacity). **It does fit with a focus policy**: the viewport you are using runs at 60 fps (tiled if larger than ≈5.7 Mpx) and the other runs at 30 fps or less. Measured: 24/19/14 ms and 20/15 ms medians.
3. **A third full-motion stream overloads everything** (207 ms). Encode capacity is the scarcest resource in the system and must be scheduled ([ADR 0007](../adr/0007-h264-encode-scheduler.md)), not assumed.
4. **H.264 is the default**: lower per-frame time on the same engines, and RDP EGFX only carries AVC. HEVC is opt-in where bitrate matters more than latency (WAN, native client).
5. **Idle viewports cost nothing.** ScreenCaptureKit delivers frames only on change, so the budget only binds when two screens are in full motion at once.
6. Consistent with prior art: macrdp measured two sessions at 1.02× the throughput of one on its (single-engine) machine and parked AVC444 at 4K60 for the same reason.

## Effect on spec / milestones

- [ADR 0007](../adr/0007-h264-encode-scheduler.md): H.264 via VideoToolbox for every viewport; `EncodeScheduler` with a focus policy and tiling.
- New IDs: T1-GFX-08 (scheduler + tiling) and T1-PERF-05 (two viewports at once) in [spec.md](../spec.md).
- V4 in [milestones.md](../milestones.md).

## Follow-up

- Rerun on other Macs. Base and Pro M-series chips have **one** encode engine: there the second viewport must be ≤ 30 fps or reduced resolution even when the first is not 4K.
- Synthetic content is pessimistic for typical desktops (mostly static) and close to reality for full-screen scrolling. Measure capture → encode → decode → present end to end in `just live-check` once EGFX lands (V4).
- RDP tiling needs two EGFX surfaces mapped to one output. Verify Windows App iPadOS draws that (R17). Fallback: encode the focused 4K viewport at 2560×1440 or 3008×1692 and let the client upscale, or 4K at 30 fps.

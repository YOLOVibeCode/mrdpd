# ADR 0007: H.264 for every viewport, behind an encode scheduler

Status: proposed (accepted when the PR that adds it merges)
Date: 2026-10-04
Supersedes: tier placement of T2-GFX-01 (client-side cursor) and T2-GFX-02 (EGFX H.264), which this ADR re-files as T1-GFX-06 and T1-GFX-07.

## Context

- RemoteFX on loopback: a full-display repaint at 1600×1200 took a median of 110.7 ms, max 232 ms (`just live-check`, 2026-10-04). A 4K viewport is 4.3× the pixels. RemoteFX cannot carry the target scenario.
- [Spike R15](../spikes/2026-10-04-r15-encode-budget.md) on the owner's M4 Max:
  - two hardware encode engines; one session per engine;
  - one engine does an iPad-13"-sized frame in ~15 ms, but a 4K frame takes ~20 ms (so 4K at 60 fps needs both);
  - 4K halves at 60 fps plus the iPad at 30 fps fits (24/19/14 ms medians); a third full-motion stream overloads everything.
- The cursor is composited into frames today (T1-GFX-05), so pointer motion waits for capture, encode, network, and decode. That is a large part of "not smooth".
- IronRDP 0.13 has feature `egfx` (ironrdp-egfx 0.3, AVC420/AVC444 server). macrdp ships VideoToolbox H.264 over it and documents the Microsoft-client quirks (R16 §E).

## Decision

1. **H.264 via VideoToolbox is the T1 video path for every viewport.**
   - RDP: EGFX AVC420 (`ironrdp-server` feature `egfx`).
   - Native client: the same encoder output ([ADR 0008](0008-native-ipad-client.md)).

   RemoteFX stays as the automatic fallback for RDP clients that do not advertise AVC.
2. **Encoder settings**, from R15 and macrdp:
   - hardware only, RealTime, no frame reordering, low-latency rate control;
   - `MaxFrameDelayCount 0`, `PrioritizeEncodingSpeedOverQuality`;
   - full-range BT.709;
   - IDR every 2 s and on demand (switch, overview, large change);
   - flush frames after a burst so client presentation buffers drain;
   - HEVC is opt-in (native client, WAN).
3. **`EncodeScheduler` owns the encoder budget.**
   - Slots = hardware engines, detected at startup by a short calibration (2 on M-series Max/Ultra, 1 on base/Pro), not by chip name.
   - The **focused viewport** (most recent input) gets 60 fps and is split into two tiles when larger than one engine's 60 fps capacity (~5.7 Mpx on M4 Max).
   - Other viewports are capped at 30 fps, or 15 fps when three are active. Reduce resolution before frame rate for unfocused viewports.
   - At most one frame is queued per viewport and the oldest is dropped. The scheduler never lets the queue build. Latency beats completeness.
   - Idle viewports cost nothing: SCK only delivers on change.
4. **Tiling.**
   - Native client: tiles are ours.
   - RDP: two EGFX surfaces mapped to one output. If Windows App on iPadOS does not render that (R17), encode the focused 4K viewport at 3008×1692 or 2560×1440 and let the client upscale, or 4K at 30 fps.
5. **Client-side cursor is T1** (T1-GFX-06).
   - RDP: color pointer PDUs plus position.
   - Native: a cursor stream.

   The cursor is removed from captured frames (`showsCursor = false`) once a client renders it. A viewport whose source display does not hold the Mac cursor gets a hidden pointer.

## Consequences

- `AvcFrameSink` (planned for M10) is extracted at V4 on its first failing test, as a viewport-scoped encoder seam, not a method on `FrameSource`.
- New IDs: T1-GFX-06 cursor, T1-GFX-07 H.264 viewport video, T1-GFX-08 scheduler and tiling, T1-PERF-05 two viewports at once. T2-GFX-01 and T2-GFX-02 are marked superseded.
- AVC444 stays T2 (T2-GFX-03). It costs two encodes per frame, which the budget cannot afford at 4K.
- On single-engine Macs the second viewport is always ≤ 30 fps or reduced resolution. This is documented, not hidden.

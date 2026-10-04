# Benches (T1-PERF)

CI does not open an RDP session. `just bench` is the TCC-free subset. `just live-check` ([live-check.md](live-check.md)) measures T1-PERF-02/03/04 on loopback against a live `mrdpd-serve`. LAN numbers go in the milestone interop log.

## T1-PERF-01 — ≥ 30 fps 1080p-equivalent under motion on LAN

Automated: `FramePacerTests.testAllowsAtLeast30FpsWhenClockAdvances` (TCC-free). The pacer allows at least 30 emits per 60 slots at 16 ms, and never more than 60 fps.

LAN: after `just serve`, connect a client, move a window, note FPS in the M5 interop log.

## T1-PERF-03 — idle < 50 kbit/s

`just live-check t1_perf_03`: bytes the headless client receives over 5 s with the probe window static. Not CI. 2026-10-04: 0.0 kbit/s.

## T1-PERF-04 — CPU < 40% of one P-core idle 1080p

`just live-check t1_perf_04`: `ps -o time` delta for `mrdpd-serve` over 5 s idle. Not CI. 2026-10-04: 0.2–0.4 % at 1600×1200.

## T1-PERF-02 — input-to-photon < 80 ms on LAN

`just live-check t1_perf_02`: FastPath key-down → probe toggles a 60 pt patch → time until the client's decoded frame shows it. Median of 12. Loopback only; LAN/Tailscale adds RTT. Not CI. 2026-10-04: median 35.9 ms, max 51 ms.

A **full-display** repaint (whole 1600×1200 window changes colour) measured median 110.7 ms, max 232 ms on the same path. That is the cost of RemoteFX on large damage and matches the iPad "not smooth" report; M8 (smaller stream) and M10 (H.264) are the levers.

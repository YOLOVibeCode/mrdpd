# Benches (T1-PERF)

CI does not open an RDP session on the LAN. `just bench` is the automated subset. Live numbers go in the milestone interop log.

## T1-PERF-01 — ≥ 30 fps 1080p-equivalent under motion on LAN

Automated: `FramePacerTests.testAllowsAtLeast30FpsWhenClockAdvances` (TCC-free). The pacer allows at least 30 emits per 60 slots at 16 ms, and never more than 60 fps.

LAN: after `just serve`, connect a client, move a window, note FPS in the M5 interop log.

## T1-PERF-03 — idle < 50 kbit/s

Not CI. `just serve` + client sitting idle. Use client stats, `nettop`, or Activity Monitor Network. Record kbit/s in `docs/tasks/m5.md`.

## T1-PERF-04 — CPU < 40% of one P-core idle 1080p

Not CI. Same idle session. Activity Monitor CPU for `mrdpd-serve` (and the engine thread). Record in `docs/tasks/m5.md`.

## T1-PERF-02 — input-to-photon < 80 ms on LAN

Not CI. After `just serve` + client, click or type and note perceived lag. Record in `docs/tasks/m6.md`.

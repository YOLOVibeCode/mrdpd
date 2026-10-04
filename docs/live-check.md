# Live check (`just live-check`)

One command that proves a live session end to end on this Mac, without a human or an iPad:

```bash
just live-check                 # all 9 checks, ~30 s after the release build
just live-check t1_perf_02      # one check (cargo test name filter)
```

It builds release `mrdpd-engine`, `mrdpd-serve`, and `mrdpd-probe`, then runs
`engine/mrdpd-engine/tests/live_check.rs` with `--ignored --test-threads=1`.

## What each test does

Every test starts a fresh lab:

1. **`mrdpd-probe`** (`Sources/mrdpd-probe/main.swift`) puts one borderless window over the
   captured display (the first `SCDisplay`, same as `mrdpd-serve`). It logs every input
   it receives to stdout (`ev=leftDown x=… y=…`, Quartz global points) and paints a colour
   per event kind. Mouse events repaint the whole window. Key events toggle a 60 pt patch at
   the client's sample point, so latency is measured on a typing-sized update.
2. **`mrdpd-serve`** on `127.0.0.1:<free port>`.
3. **Headless IronRDP client** (`tests/common`) connects with NLA, waits for the probe's grey,
   then clicks centre to make the probe the key window.

Each check asserts on **both sides**: what the Mac received (probe stdout) and what the
client saw (decoded RemoteFX pixels at the sample point).

| Test | ID | Asserts |
| --- | --- | --- |
| `t1_in_03_live_click_lands_on_mapped_point` | T1-IN-03 | leftDown/leftUp at the `DisplayMap` point (±1.5 pt); red → green on the client |
| `t1_in_03_live_right_click` | T1-IN-03 | rightDown/rightUp at the mapped point; magenta |
| `t1_in_03_live_drag` | T1-IN-03 | ≥ 5 `leftDragged` for 10 moves, last one and leftUp at the end point; yellow |
| `t1_in_03_live_vertical_wheel` | T1-IN-03 | +120 / −120 give non-zero `scrollingDeltaY` of opposite sign; blue |
| `t1_in_04_live_typing` | T1-IN-02 / T1-IN-04 | "Hello mrdpd 42" (Shift included) arrives as exactly those characters, no auto-repeat |
| `t1_in_04_live_cmd_shortcut` | T1-IN-04 | Left GUI (extended 0x5B) + A → keyDown keycode 0 with Command |
| `t1_perf_02_input_to_photon` | T1-PERF-02 | median key-down → patch visible on the client < 80 ms (12 keys) |
| `t1_perf_03_idle_bitrate` | T1-PERF-03 | < 50 kbit/s received over 5 s idle |
| `t1_perf_04_idle_cpu` | T1-PERF-04 | `mrdpd-serve` CPU (`ps -o time`) < 40 % of one core over 5 s idle |

## Requirements and safety

- Screen Recording **and** Accessibility on the terminal that runs it ([tcc.md](tcc.md)).
- It moves the pointer and covers the first display for a few seconds per test. **Escape**
  quits the probe; it also exits on stdin EOF and after 180 s.
- Keys are only injected after the probe reports it is the key window
  (`require_focus`); otherwise the test fails instead of typing into another app.
- Loopback only (T1-SEC-04). Latency is loopback: LAN or Tailscale adds network RTT.
- Never in CI. CI runs `just test` only (`.github/workflows/test.yml`).

## Results

Record runs in the milestone interop log. First runs: [tasks/m6.md](tasks/m6.md).

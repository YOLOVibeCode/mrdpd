# ADR 0006: Map Mac displays into the client's monitor layout

Status: accepted  
Date: 2026-10-04

## Context

An RDP client reports only its own monitors (GCC at connect, RDPEDISP after connect). The server decides what fills each one. mrdpd serves the physical console, so the Mac can have more displays than the client: three Mac displays against two desktop monitors, or against one iPad.

Today `mrdpd-serve` captures `content.displays.first`, so the iPad may not show the display the user works on (checkpoint pitfall). Findings: [R1 follow-up spike](../spikes/2026-10-03-r1-host-display-picker.md).

## Decision

- mrdpd honors the client's monitor layout and maps Mac displays into it. It never changes the Mac's display modes.
- Mac displays are lettered A, B, C… left to right by global frame, then top to bottom.
- One client monitor: the main display by default (owner, 2026-10-04). `--display` picks another (`T1-MON-02`, T1, M6 follow-up).
- Several client monitors: A on 1, B on 2 by default, extra Mac displays hidden (owner, 2026-10-03) (`T2-MON-05`, M9).
- Switching happens in-session from a picker that mrdpd draws into the frames (`T2-MON-06`): a translucent tab about 10% of the monitor's width at top center unless spike R15 says otherwise, display tiles, an outline step to pick the target monitor, and a swap when the display is already shown. Stock clients only; no custom client.
- `T2-MON-03` captures only displays shown on some client monitor.
- IronRDP route:
  - After the M6 gate and before M8, move to IronRDP 0.14 (release PR #2067: `ironrdp-server` 0.14.0, acceptor and connector 0.11.0, displaycontrol 0.9.0), or pin that PR's commit if it has not published. The engine is ported once, and `monitor_count()` (#1918) comes with it.
  - File an upstream issue, then a PR, for the connect-time monitor list and an N-monitor `MonitorLayoutPdu` at connect and on reactivation. Consume it from a fork branch via `[patch]` until it merges.

## Consequences

- With one monitor, the default moves from "first SCK display" to "main display". These are usually the same display.
- Hidden Mac displays still receive windows, dialogs and notifications the remote user cannot see. With "Displays have separate Spaces" off, hiding the main display also hides the menu bar and Dock; mrdpd warns.
- The picker tab covers part of the macOS menu bar, and clicks there go to the tab. Client chrome may cover the tab (R15).
- M8 and M9 work lands on IronRDP 0.14. R5 (reconnect cookies) benefits from the same upgrade.
- Gates are unchanged: T2 items wait for M6 to be interop-green (AGENTS.md).

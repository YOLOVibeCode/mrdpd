# Spike R1: IronRDP static multimon / GCC monitor data

Date: 2026-08-20
Question: Does IronRDP’s **server** path advertise a real multi-monitor topology at connect (GCC Client Monitor Data / server Monitor Layout PDU with N>1 monitors), or only a single desktop?
Build / version of IronRDP: crates.io `ironrdp-server` / `ironrdp-acceptor` **0.13.0**, cross-checked against Devolutions/IronRDP `master` (`crates/ironrdp-acceptor/src/connection.rs`, `crates/ironrdp-server/src/display.rs`).
What we ran: source inspection (no live GCC capture; M1 has no multimon client).
Evidence (logs, PDUs, links):

- Acceptor state `MonitorLayoutSend` in [`connection.rs`](https://github.com/Devolutions/IronRDP/blob/master/crates/ironrdp-acceptor/src/connection.rs): if the client sets `SUPPORT_MONITOR_LAYOUT_PDU`, the server sends **one** `MonitorLayoutPdu` whose single `gcc::Monitor` is derived from `self.desktop_size` (origin 0,0, `PRIMARY`). There is no loop over a client GCC monitor list.
- No `ClientMonitor` / `TS_UD_CS_MONITOR` handling in that acceptor file (search is empty).
- Dynamic layout **is** implemented: `RdpServerDisplay::request_layout(DisplayControlMonitorLayout)` (MS-RDPEDISP) and `DisplayUpdate::Resize`. That is T1-MON-01 / T2-MON-02, not T2-MON-01.

Answer: **Static GCC multimon is not implemented server-side.** IronRDP will handshake a single virtual desktop. RDPEDISP after connect is the supported resize/layout path. T2-MON-01 needs an upstream acceptor change (honor client GCC monitor list and emit N monitors in `MonitorLayoutPdu`) or a local fork of `ironrdp-acceptor`.
Effect on spec / M9 / M10: Keep T2-MON-01 at M9; do **not** treat it as OUT. M1 ships single-monitor. No T2 feature work until M6 is interop-green (`AGENTS.md`).
Follow-up (upstream issue, ADR, OUT-row): File/track an IronRDP issue for server GCC `TS_UD_CS_MONITOR` → multi-entry Monitor Layout PDU before M9. No ADR. Spec row T2-MON-01 stays “spike R1” with this file as the answer: **implement via upstream (or acceptor patch) at M9**.

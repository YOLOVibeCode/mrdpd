# Spike R15: can every client reach a top-center picker tab?

Date: 2026-10-04 (local run; device runs pending)
Question: `T2-MON-06` puts a translucent tab at the top center of each client monitor. Do the clients' own toolbars or menu bars cover it, and does a click or tap reach it?
Build / version of IronRDP: crates.io `ironrdp-server` 0.13.0 (pinned). Spike code on branch `spike-r15-tab` (never merged), on top of `T1-MON-02`.
What we ran:

- `MRDPD_SPIKE_TAB=1 swift run mrdpd-serve -- 127.0.0.1 3399` on a 3-display Mac (darwin 25.6.0), serving the main display (2056×1329).
- `engine/mrdpd-engine/tests/spike_r15.rs` (`--ignored`): the IronRDP headless client grabs one frame, crops the tab area, and hovers the tab.

Evidence (logs, PDUs, links):

- The serve logged `R15: spike tab at 925,0,205,29 (x,y,w,h)`: 10% of the width, 29 px tall, hanging from the top edge.
- The headless frame shows the tab over the menu bar: dark at 60% opacity, light border, three-line grip.
- The hover reached it: `R15: pointer over tab at (1027,14)`.

Answer: **Partial.** The tab renders in the RDP stream, and the server sees the pointer over it. Whether each client's own chrome covers it is still open.

Still to run, ideally during the M6 iPad re-test. Each check needs the tab visible, plus `R15: click inside tab` in the serve's stderr after a click or tap:

- [ ] Windows App iPadOS, full screen: does its session toolbar overlap the tab?
- [ ] Windows App macOS, full screen: does the macOS menu bar slide over the tab when the pointer reaches the top edge?
- [ ] FreeRDP (`sdl-freerdp /f`): same check.
- [ ] mstsc or Windows App on Windows, full screen, if a PC is available: does the connection bar cover the tab?

For any check that fails, retry with `MRDPD_SPIKE_TAB_Y=48` (offset down from the edge), then `MRDPD_SPIKE_TAB_POS=left` or `right` (top corners).

```bash
git checkout spike-r15-tab
MRDPD_SPIKE_TAB=1 swift run mrdpd-serve -- <tailscale-ip> 3390 --display B
```

Effect on spec / M9 / M10: `T2-MON-06` keeps "top center unless R15 says otherwise" until the device runs are logged here. No ABI or engine change.
Follow-up (upstream issue, ADR, OUT-row): log the four checks here. Then set R15 to `mitigated` (a position works on every client) or `accepted` (key chord fallback), before Slice 4 builds the picker.

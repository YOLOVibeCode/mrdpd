# mrdpd

Apache-licensed **RDP server for macOS**. [Windows App](https://apps.apple.com/app/windows-app/id1295203466) on an iPad (and FreeRDP / desktop Windows App) should drive the logged-in Mac console — lid-closed / repair-window included.

**Target (2026-10-04):** a Mac with several displays, driven from an iPad Pro with an external 4K monitor. Each client screen is an independent **viewport** that shows any Mac display, switchable from that screen. See [docs/architecture.md](docs/architecture.md) and ADRs [0006](docs/adr/0006-viewports.md)–[0009](docs/adr/0009-reuse-not-fork.md).

**Pre-alpha.** Full snapshot: [docs/checkpoint.md](docs/checkpoint.md) (2026-08-21). Session rules: [AGENTS.md](AGENTS.md).

## Pick up here

M0–M5 are in tree. **M6 injects HID** (`CGEventInputSink`) but the **iPad survival gate is not `interop-green`**.

Last iPad session (Tailscale `100.x:3390`, 3360×1890 RemoteFX): desktop **rendered**, **some typing worked**, motion was **not smooth**. Click / drag / scroll / Cmd were not fully scored. Session size is the **first `SCDisplay`**, not the iPad.

**`just live-check`** (2026-10-04) proves the server side with no human: click, right click, drag, wheel, typing, and Cmd+A reach the Mac at the mapped point, and key-to-photon is ~36 ms on loopback. Full-display repaints are ~110 ms, which is the smoothness problem. See [docs/live-check.md](docs/live-check.md).

**Do next** (viewport track, [docs/milestones.md](docs/milestones.md))

1. **V0**: one iPad session that scores M6 input and answers the Windows App questions (two windows? Cmd mapping? H.264?). Checklist: [docs/tasks/v0.md](docs/tasks/v0.md).
2. **V1**: any Mac display, sized to the client screen (replaces M8). The Mac's display modes never change.
3. **V2** switching (hotkeys, HUD, overview) → **V3** two screens at once → **V4** H.264 + client-side cursor. **V5** native iPad client only if [ADR 0008](docs/adr/0008-native-ipad-client.md) is accepted.

Lab NLA: user `mrdpd`, password `changeme` (not the Mac login). Bind an explicit host; **never** `0.0.0.0`.

```bash
just test                          # TCC-free
just test-local                    # Screen Recording + Accessibility
just serve                         # 127.0.0.1:3390
just serve host=<tailscale-ip>     # iPad
just live-check                    # live loop: probe + serve + headless client (TCC; takes the screen ~30 s)
```

TCC: same Terminal/Cursor needs **Screen Recording** and **Accessibility** ([docs/tcc.md](docs/tcc.md)).

## Status

| M | What | State |
| --- | --- | --- |
| 0 | Docs + StubEngine + Frame/Input/EngineKit | done |
| 1 | Real IronRDP engine, headless #FF00FF | done |
| 2 | 1080p quadrants, FreeRDP GDI | done (iPad pattern skipped; live view later) |
| 3 | Keymap + FastPath → `RecordingInputSink` | done |
| 4 | SCK capture + dirty rects | done |
| 5 | Live view (`mrdpd-serve`, pacer, cursor) | done; iPad **saw** desktop |
| 6 | Inject (`DisplayMap` + `CGEventInputSink`) | **partial**; `just live-check` 9/9; iPad not fully scored; smoothness open |
| V0–V5 | Viewports: any display, client-sized, switchable, two screens, H.264, native client | **next** — [milestones](docs/milestones.md) |
| 7 | Clipboard | after V3 |
| 8–10 | Resize, multimon, EGFX | folded into V1, V3, V4 |
| 11–12 | Audio, daemon | after V3 |

## Docs

| Doc | What |
| --- | --- |
| [docs/checkpoint.md](docs/checkpoint.md) | Dated pickup snapshot |
| [docs/spec.md](docs/spec.md) | Requirement IDs |
| [docs/method.md](docs/method.md) | TDD + ISP |
| [docs/architecture.md](docs/architecture.md) | Viewports: Swift host, IronRDP engine behind C ABI, encode scheduler |
| [docs/milestones.md](docs/milestones.md) | M0–M12 and the viewport track V0–V5 |
| [docs/traceability.md](docs/traceability.md) | ID → test → status |
| [docs/live-check.md](docs/live-check.md) | `just live-check`: automated live input + perf loop |
| [AGENTS.md](AGENTS.md) | Rules for every session |

## License

[Apache License 2.0](LICENSE). Third-party: [NOTICE](NOTICE) (IronRDP).

## Security

Do not commit credentials, TLS private keys, NLA passwords, or `.env` files. [SECURITY.md](SECURITY.md). After clone:

```bash
git config core.hooksPath .githooks
```

## Non-goals (until T1 works)

No RemoteApp, no multi-user sessions, no FileVault pre-boot, no App Store, no mic/camera/drive redirection (T3).

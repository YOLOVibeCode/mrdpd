# mrdpd

Apache-licensed **RDP server for macOS**. [Windows App](https://apps.apple.com/app/windows-app/id1295203466) on an iPad (and FreeRDP / desktop Windows App) should drive the logged-in Mac console — lid-closed / repair-window included.

**Pre-alpha.** Full snapshot: [docs/checkpoint.md](docs/checkpoint.md) (2026-08-21). Session rules: [AGENTS.md](AGENTS.md).

## Pick up here

M0–M5 are in tree. **M6 injects HID** (`CGEventInputSink`) but the **iPad survival gate is not `interop-green`**.

Last iPad session (Tailscale `100.x:3390`, 3360×1890 RemoteFX): desktop **rendered**, **some typing worked**, motion was **not smooth**. Click / drag / scroll / Cmd were not fully scored. Session size is the **first `SCDisplay`**, not the iPad.

**Do next**

1. Re-run iPad: confirm click, drag, scroll, Cmd even if laggy. Log in [docs/tasks/m6.md](docs/tasks/m6.md).
2. **M8** (`T1-MON-01`): RDPEDISP + SCK reconfigure to iPad size. Helps fit and smoothness. Does **not** change the Mac’s hardware resolution (that would need an ADR).
3. Do **not** start T2 (multimon, EGFX/H.264, audio, file clipboard) until M6 is honestly interop-green.

Lab NLA: user `mrdpd`, password `changeme` (not the Mac login). Bind an explicit host; **never** `0.0.0.0`.

```bash
just test                          # TCC-free
just test-local                    # Screen Recording + Accessibility
just serve                         # 127.0.0.1:3390
just serve host=<tailscale-ip>     # iPad
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
| 6 | Inject (`DisplayMap` + `CGEventInputSink`) | **partial**; typing some; smoothness open |
| 7 | Clipboard | not started |
| 8 | Resize stream to iPad | **next product work** |
| 9–12 | Multimon, EGFX, audio, daemon | after M6 interop-green |

## Docs

| Doc | What |
| --- | --- |
| [docs/checkpoint.md](docs/checkpoint.md) | Dated pickup snapshot |
| [docs/spec.md](docs/spec.md) | Requirement IDs |
| [docs/method.md](docs/method.md) | TDD + ISP |
| [docs/architecture.md](docs/architecture.md) | Swift + IronRDP behind C ABI |
| [docs/milestones.md](docs/milestones.md) | M0–M12; M6 = daily-usable from iPad |
| [docs/traceability.md](docs/traceability.md) | ID → test → status |
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

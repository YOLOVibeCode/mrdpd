# mrdpd

Apache-licensed **RDP server for macOS**. The goal is a real Remote Desktop endpoint on the Mac so [Windows App](https://apps.apple.com/app/windows-app/id1295203466) on an iPad (and desktop clients) can drive the logged-in console session — including lid-closed / repair-window use.

This repository is **pre-alpha**. M6 injects keyboard/mouse (`just serve` needs Screen Recording **and** Accessibility). Lab: `just serve-pattern` or `just serve` on `127.0.0.1:3390`.

## License

[Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for third-party attribution (IronRDP).

## Docs

Start at [docs/README.md](docs/README.md) (read [docs/checkpoint.md](docs/checkpoint.md) first). Session rules: [AGENTS.md](AGENTS.md). Parallel agents: [docs/workstreams.md](docs/workstreams.md).

| Doc | What |
| --- | --- |
| [docs/spec.md](docs/spec.md) | Requirements with stable IDs |
| [docs/method.md](docs/method.md) | How we build (TDD + ISP) |
| [docs/architecture.md](docs/architecture.md) | Swift app + IronRDP engine behind a C ABI |
| [docs/milestones.md](docs/milestones.md) | M0–M12; **M6 is daily-usable from iPad** |

## Status

- **M0a** (documentation pack): done
- **M0b** (StubEngine + FrameKit + InputKit + EngineKit): contract tests green
- **M1** (real `mrdpd-engine` + C-HEADLESS #FF00FF): `just test` green; spikes R1/R2/R5 written
- **M2** (1080p quadrants): C-HEADLESS + FreeRDP `sdl-freerdp` GDI green; iPad still required for DoD
- **M3** (input decode): keymap + FastPath → `RecordingInputSink`
- **M4** (SCK capture): `just test-local` contract-green
- **M5** (live view): `just serve` + 60 fps pacer + cursor composite; iPad live view still required for DoD
- **M6** (inject): `CGEventInputSink` + Retina `DisplayMap`; iPad typing still required for the survival-gate DoD

## Security / secrets

Never commit credentials, TLS private keys, NLA passwords, or `.env` files. See [SECURITY.md](SECURITY.md). After clone:

```bash
git config core.hooksPath .githooks
```

Public GitHub also runs Gitleaks on every push.

## Non-goals (until T1 works)

No RemoteApp, no multi-user sessions, no FileVault pre-boot, no App Store, no mic/camera/drive redirection (T3).

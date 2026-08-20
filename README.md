# mrdpd

Apache-licensed **RDP server for macOS**. The goal is a real Remote Desktop endpoint on the Mac so [Windows App](https://apps.apple.com/app/windows-app/id1295203466) on an iPad (and desktop clients) can drive the logged-in console session — including lid-closed / repair-window use.

This repository is **pre-alpha**. The tree is currently the specification, agent workstreams, and an empty Swift/Rust skeleton. There is not yet a daemon you can run.

## License

[Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for third-party attribution (IronRDP).

## Docs

Start at [docs/README.md](docs/README.md). Session rules: [AGENTS.md](AGENTS.md). Parallel agents: [docs/workstreams.md](docs/workstreams.md).

| Doc | What |
| --- | --- |
| [docs/spec.md](docs/spec.md) | Requirements with stable IDs |
| [docs/method.md](docs/method.md) | How we build (TDD + ISP) |
| [docs/architecture.md](docs/architecture.md) | Swift app + IronRDP engine behind a C ABI |
| [docs/milestones.md](docs/milestones.md) | M0–M12; **M6 is daily-usable from iPad** |

## Status

- **M0a** (this documentation pack): in tree
- **M0b** (StubEngine + Swift contracts): not started

## Security / secrets

Never commit credentials, TLS private keys, NLA passwords, or `.env` files. See [SECURITY.md](SECURITY.md). After clone:

```bash
git config core.hooksPath .githooks
```

Public GitHub also runs Gitleaks on every push.

## Non-goals (until T1 works)

No RemoteApp, no multi-user sessions, no FileVault pre-boot, no App Store, no mic/camera/drive redirection (T3).

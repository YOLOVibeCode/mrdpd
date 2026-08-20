# Security

**Do not open a GitHub issue that contains secrets.** If you accidentally committed a password, private key, certificate, NLA credential, or cloud token:

1. Rotate it immediately (assume it is public).
2. Email the maintainers privately; do not paste the secret in the issue body.
3. We will purge history if needed (`git filter-repo` / GitHub support).

This repository is configured to reject common secret files and patterns:

- `.gitignore` denies keys, certs, `.env`, credential stores, and local config
- `.githooks/pre-commit` runs `scripts/check-secrets.sh` (filename denylist + content patterns)
- CI runs Gitleaks on every push and pull request
- Public GitHub repos also get GitHub secret scanning / push protection

Enable the local hook after clone:

```bash
git config core.hooksPath .githooks
```

The initial clone of this repo already sets `core.hooksPath` when you run `git clone` only if you copy that config; the command above is the source of truth.

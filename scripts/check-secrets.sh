#!/usr/bin/env bash
# Deny secret paths and secret-looking content. Used by .githooks/pre-commit.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${ROOT}" ]]; then
  ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi
cd "$ROOT"

fail() { echo "SECRET GUARD: $*" >&2; exit 1; }

path_denied() {
  local f="$1" base
  base="$(basename "$f")"
  case "$base" in
    .env|.env.local|.env.production|.netrc|.npmrc|.pypirc|id_rsa|id_dsa|id_ecdsa|id_ed25519|credentials.json|auth.json)
      return 0 ;;
  esac
  case "$f" in
    *.pem|*.key|*.p8|*.p12|*.pfx|*.jks|*.keystore|*.mobileprovision|*.kdbx|*.ovpn|*.rdp)
      return 0 ;;
    *.secret|secrets.yaml|secrets.yml|secrets.toml|secrets.json)
      return 0 ;;
  esac
  return 1
}

scan_content() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  case "$f" in
    scripts/check-secrets.sh|.gitleaks.toml)
      return 0
      ;;
  esac
  grep -qI '' "$f" 2>/dev/null || return 0
  if grep -E -n \
    -e 'BEGIN (OPENSSH |RSA |EC |DSA |ENCRYPTED )?PRIVATE KEY' \
    -e 'AKIA[0-9A-Z]{16}' \
    -e 'ASIA[0-9A-Z]{16}' \
    -e 'AIza[0-9A-Za-z_-]{35}' \
    -e 'ghp_[A-Za-z0-9]{36}' \
    -e 'github_pat_[A-Za-z0-9_]{20,}' \
    -e 'xox[baprs]-' \
    -e 'sk_live_' \
    -e 'sk-ant-' \
    -e '-----BEGIN PGP PRIVATE KEY BLOCK-----' \
    "$f" >/dev/null 2>&1; then
    fail "secret-looking content in $f"
  fi
}

STAGED=()
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && [[ "${1:-}" != "--all" ]]; then
  while IFS= read -r -d '' f; do
    STAGED+=("$f")
  done < <(git diff --cached --name-only -z --diff-filter=ACMR 2>/dev/null || true)
fi

if [[ ${#STAGED[@]} -eq 0 || "${1:-}" == "--all" ]]; then
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    STAGED+=("$f")
  done < <(git ls-files 2>/dev/null || true)
fi

for f in "${STAGED[@]+"${STAGED[@]}"}"; do
  [[ -z "$f" ]] && continue
  path_denied "$f" && fail "refusing secret-like path: $f"
  scan_content "$f"
done

if command -v gitleaks >/dev/null 2>&1; then
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && [[ "${1:-}" != "--all" ]]; then
    gitleaks protect --staged --redact --config .gitleaks.toml --no-banner \
      || fail "gitleaks found a secret"
  fi
fi

echo "SECRET GUARD: ok (${#STAGED[@]} path(s))"

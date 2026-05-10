#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

for script in scripts/build.sh scripts/install.sh; do
    if [[ ! -x "$script" ]]; then
        echo "[FAIL] $script must be executable." >&2
        exit 1
    fi
    bash -n "$script"
    echo "[OK] $script"
done

if ! grep -q 'scripts/build.sh' scripts/README.md; then
    echo "[FAIL] scripts/README.md must document scripts/build.sh." >&2
    exit 1
fi

if ! grep -q 'scripts/install.sh' scripts/README.md; then
    echo "[FAIL] scripts/README.md must document scripts/install.sh." >&2
    exit 1
fi

echo "[OK] Script entrypoint tests passed."

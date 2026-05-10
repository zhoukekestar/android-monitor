#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

LOG_DIR="${TMPDIR:-/tmp}/android-monitor"
LOG_FILE="$LOG_DIR/install.log"
REPLACE=0
mkdir -p "$LOG_DIR"

usage() {
    cat <<'EOF'
install.sh

Installs the Android receiver on the connected authorized phone.

Usage:
  scripts/install.sh
  scripts/install.sh --replace

Options:
  --replace   Explicitly replace an installed Android Monitor with a different
              signing certificate. This uninstalls the existing phone app first.
  --help      Show this message.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --replace)
            REPLACE=1
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "[FAIL] Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if [[ "$REPLACE" -eq 1 ]]; then
    if scripts/replace-android-receiver.sh --confirm-uninstall >"$LOG_FILE" 2>&1; then
        cat <<EOF
[OK] Replace install complete.
Log:
  $LOG_FILE
EOF
        exit 0
    fi

    cat <<EOF
[FAIL] Replace install failed.
Log:
  $LOG_FILE

Last log lines:
EOF
    tail -n 80 "$LOG_FILE"
    exit 1
fi

if scripts/install-android-receiver.sh >"$LOG_FILE" 2>&1; then
    cat <<EOF
[OK] Install complete.
Log:
  $LOG_FILE
EOF
    exit 0
fi

if grep -q "INSTALL_PARSE_FAILED_INCONSISTENT_CERTIFICATES" "$LOG_FILE"; then
    cat <<EOF
[FAIL] Install blocked: the phone already has Android Monitor installed with a different signing certificate.

Keep using the installed phone app:
  scripts/verify-device-runtime.sh --skip-install

Replace it with this build:
  scripts/install.sh --replace

Log:
  $LOG_FILE
EOF
    exit 1
fi

if grep -q "INSTALL_FAILED_USER_RESTRICTED" "$LOG_FILE"; then
    cat <<EOF
[FAIL] Install blocked by the phone: INSTALL_FAILED_USER_RESTRICTED.

Enable Developer Options > Install via USB / USB debugging security settings,
or stage the APK and install it manually from Downloads:
  scripts/stage-apk.sh

Log:
  $LOG_FILE
EOF
    exit 1
fi

cat <<EOF
[FAIL] Install failed.
Log:
  $LOG_FILE

Last log lines:
EOF
tail -n 80 "$LOG_FILE"
exit 1

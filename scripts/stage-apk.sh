#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APK_PATH="$ROOT_DIR/AndroidReceiver/app/build/outputs/apk/debug/android-receiver-debug.apk"
DEST="/sdcard/Download/AndroidMonitorReceiver-debug.apk"

usage() {
    cat <<'EOF'
stage-apk.sh

Copies the built AndroidReceiver APK to the phone's Downloads folder for manual
installation. This does not run adb install.

Options:
  --dest <path>   Device destination path. Default: /sdcard/Download/AndroidMonitorReceiver-debug.apk
  --help          Show this message.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dest)
            if [[ $# -lt 2 ]]; then
                echo "[FAIL] --dest requires a value" >&2
                exit 2
            fi
            DEST="$2"
            shift
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

if [[ ! -s "$APK_PATH" ]]; then
    echo "[FAIL] APK not found: $APK_PATH" >&2
    echo "       Build it first with: scripts/phase0-check.sh --skip-device" >&2
    exit 1
fi

if ! command -v adb >/dev/null 2>&1; then
    echo "[FAIL] adb was not found on PATH" >&2
    exit 1
fi

echo "==> Checking authorized Android device"
ADB_DEVICES="$(adb devices)"
printf '%s\n' "$ADB_DEVICES"
if ! printf '%s\n' "$ADB_DEVICES" | awk 'NR > 1 && $2 == "device" { found = 1 } END { exit found ? 0 : 1 }'; then
    echo "[FAIL] No authorized adb device found." >&2
    exit 3
fi

echo "==> Copying APK to $DEST"
adb push "$APK_PATH" "$DEST"

cat <<EOF
[OK] APK staged for manual install:
     $DEST

On the phone, open the file from Downloads and approve the installation prompt.
After installation, run:
  scripts/phase0-check.sh --skip-install
EOF

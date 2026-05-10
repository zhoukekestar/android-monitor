#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT_DIR/scripts/lib/adb-path.sh"
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

ADB_BIN="$(resolve_adb_bin)"
if [[ -z "$ADB_BIN" ]]; then
    echo "[FAIL] adb was not found from ANDROID_HOME, ANDROID_SDK_ROOT, ~/Library/Android/sdk, or PATH." >&2
    exit 1
fi

echo "==> Checking authorized Android device"
require_single_authorized_adb_device "$ADB_BIN"

echo "==> Copying APK to $DEST"
"$ADB_BIN" push "$APK_PATH" "$DEST"

cat <<EOF
[OK] APK staged for manual install:
     $DEST

On the phone, open the file from Downloads and approve the installation prompt.
After installation, run:
  scripts/phase0-check.sh --skip-install
EOF

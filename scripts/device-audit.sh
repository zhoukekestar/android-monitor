#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT_DIR/scripts/lib/adb-path.sh"

PACKAGE_NAME="com.androidmonitor.receiver"
PORT="${PHASE0_STREAM_PORT:-38888}"
CHECK_REVERSE_LIST=0

usage() {
    cat <<'EOF'
device-audit.sh

Collects read-only Android device state for Phase 0: ADB authorization, device
identity, display size, AndroidReceiver install status, adb reverse state, and
H.264 decoder hints.

Options:
  --port <port>           Stream port to check in adb reverse output. Default: 38888.
  --check-reverse-list    Run adb reverse --list. This can disconnect some Android 5 devices.
  --help                  Show this message.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --port)
            if [[ $# -lt 2 ]]; then
                echo "[FAIL] --port requires a value" >&2
                exit 2
            fi
            PORT="$2"
            shift
            ;;
        --check-reverse-list)
            CHECK_REVERSE_LIST=1
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

ADB_BIN="$(resolve_adb_bin)"
if [[ -z "$ADB_BIN" ]]; then
    echo "[FAIL] adb was not found from ANDROID_HOME, ANDROID_SDK_ROOT, ~/Library/Android/sdk, or PATH." >&2
    exit 1
fi

echo "==> ADB devices"
require_single_authorized_adb_device "$ADB_BIN"

adb_shell() {
    "$ADB_BIN" shell "$@" 2>/dev/null | tr -d '\r'
}

prop() {
    adb_shell getprop "$1" || true
}

echo "==> Device identity"
printf 'Manufacturer: %s\n' "$(prop ro.product.manufacturer)"
printf 'Brand:        %s\n' "$(prop ro.product.brand)"
printf 'Model:        %s\n' "$(prop ro.product.model)"
printf 'Device:       %s\n' "$(prop ro.product.device)"
printf 'Android:      %s (API %s)\n' "$(prop ro.build.version.release)" "$(prop ro.build.version.sdk)"
printf 'ABI:          %s\n' "$(prop ro.product.cpu.abi)"
printf 'Hardware:     %s\n' "$(prop ro.hardware)"
printf 'Platform:     %s\n' "$(prop ro.mediatek.platform)"

echo "==> Display"
adb_shell wm size || true
adb_shell wm density || true
DISPLAY_INFO="$(adb_shell dumpsys display || true)"
printf '%s\n' "$DISPLAY_INFO" | grep -m 1 'DisplayDeviceInfo' || true
printf '%s\n' "$DISPLAY_INFO" | grep -m 1 'PhysicalDisplayInfo' || true

echo "==> AndroidReceiver package"
PACKAGES="$(adb_shell pm list packages "$PACKAGE_NAME" || true)"
if printf '%s\n' "$PACKAGES" | grep -q "^package:$PACKAGE_NAME$"; then
    echo "[OK] $PACKAGE_NAME is installed"
    adb_shell pm path "$PACKAGE_NAME" || true
    adb_shell dumpsys package "$PACKAGE_NAME" | grep -E 'versionCode|versionName|firstInstallTime|lastUpdateTime' || true
else
    echo "[INFO] $PACKAGE_NAME is not installed"
fi

echo "==> ADB reverse"
if [[ "$CHECK_REVERSE_LIST" -ne 1 ]]; then
    echo "[INFO] Skipped adb reverse --list; pass --check-reverse-list to query it."
    echo "[INFO] tcp:$PORT reverse state is unknown"
else
    set +e
    REVERSE_LIST="$("$ADB_BIN" reverse --list 2>&1 | tr -d '\r')"
    REVERSE_LIST_STATUS=$?
    set -e
    if [[ "$REVERSE_LIST_STATUS" -ne 0 ]]; then
        printf '%s\n' "$REVERSE_LIST"
        echo "[WARN] Could not list adb reverse entries; reverse state is unknown."
    elif [[ -n "$REVERSE_LIST" ]]; then
        printf '%s\n' "$REVERSE_LIST"
    else
        echo "[INFO] No adb reverse entries"
    fi
    if [[ "$REVERSE_LIST_STATUS" -ne 0 ]]; then
        echo "[INFO] tcp:$PORT reverse state is unknown"
    elif printf '%s\n' "$REVERSE_LIST" | grep -q "tcp:$PORT[[:space:]]\+tcp:$PORT"; then
        echo "[OK] tcp:$PORT is reversed"
    else
        echo "[INFO] tcp:$PORT is not reversed"
    fi
fi

echo "==> H.264 decoder hints"
CODEC_DUMPSYS="$(adb_shell dumpsys media.codec || true)"
if [[ -n "$CODEC_DUMPSYS" && "$CODEC_DUMPSYS" != *"Can't find service"* ]]; then
    printf '%s\n' "$CODEC_DUMPSYS" | grep -i -E 'video/avc|h264|decoder' || true
else
    CODEC_XML="$(adb_shell cat /system/etc/media_codecs.xml || true)"
    if [[ -z "$CODEC_XML" ]]; then
        echo "[WARN] Could not read media.codec dumpsys or /system/etc/media_codecs.xml"
    else
        printf '%s\n' "$CODEC_XML" | awk '
            /<MediaCodec/ {
                block = $0
                if ($0 ~ /\/>/) {
                    lower = tolower(block)
                    if (lower ~ /decoder/ && lower ~ /video\/avc/) {
                        print block
                    }
                    block = ""
                    next
                }
                in_block = 1
                next
            }
            in_block {
                block = block "\n" $0
                if ($0 ~ /<\/MediaCodec>/) {
                    lower = tolower(block)
                    if (lower ~ /decoder/ && lower ~ /video\/avc/) {
                        print block "\n"
                    }
                    block = ""
                    in_block = 0
                }
            }
        '
    fi
fi

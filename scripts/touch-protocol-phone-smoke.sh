#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAC_DIR="$ROOT_DIR/MacHost"
APK_PATH="$ROOT_DIR/AndroidReceiver/app/build/outputs/apk/debug/android-receiver-debug.apk"
PACKAGE_NAME="com.androidmonitor.receiver"
ACTIVITY_NAME="$PACKAGE_NAME/.MainActivity"
PORT="${PHASE0_STREAM_PORT:-38888}"
OUTPUT_DIR="/tmp/android-monitor-touch-protocol-phone-smoke"
MAC_LOG="$OUTPUT_DIR/mac-host.log"
ANDROID_LOG="$OUTPUT_DIR/android-input-logcat.log"
WINDOW_XML="$OUTPUT_DIR/window.xml"
H264_OUTPUT="$OUTPUT_DIR/stream.h264"
SKIP_INSTALL=0

usage() {
    cat <<'EOF'
touch-protocol-phone-smoke.sh

Runs a no-virtual-display phone smoke for Android touch control messages. The
script starts a synthetic H.264 stream with input-event logging, launches the
Android receiver, long-presses to enable touch input, sends tap and drag gestures
through ADB, and requires MacHost to log received touch actions.

This verifies the Android touch-control path over USB without creating a virtual
display. It does not verify CoreGraphics input injection or two-finger scroll;
those still require manual verification on a real virtual display.

Options:
  --skip-install   Do not install the debug APK before launching.
  --output-dir <p> Default: /tmp/android-monitor-touch-protocol-phone-smoke.
  --help           Show this message.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-install)
            SKIP_INSTALL=1
            ;;
        --output-dir)
            OUTPUT_DIR="${2:?--output-dir requires a value}"
            MAC_LOG="$OUTPUT_DIR/mac-host.log"
            ANDROID_LOG="$OUTPUT_DIR/android-input-logcat.log"
            WINDOW_XML="$OUTPUT_DIR/window.xml"
            H264_OUTPUT="$OUTPUT_DIR/stream.h264"
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

if ! command -v adb >/dev/null 2>&1; then
    echo "[FAIL] adb was not found on PATH" >&2
    exit 1
fi

ADB_DEVICES="$(adb devices)"
printf '%s\n' "$ADB_DEVICES"
if ! printf '%s\n' "$ADB_DEVICES" | awk 'NR > 1 && $2 == "device" { found = 1 } END { exit found ? 0 : 1 }'; then
    echo "[FAIL] No authorized adb device found." >&2
    exit 3
fi

if [[ "$SKIP_INSTALL" -eq 0 ]]; then
    if [[ ! -s "$APK_PATH" ]]; then
        echo "[FAIL] APK not found: $APK_PATH" >&2
        exit 4
    fi
    echo "==> Installing AndroidReceiver"
    adb install -r -d "$APK_PATH"
fi

mkdir -p "$OUTPUT_DIR"
rm -f "$MAC_LOG" "$ANDROID_LOG" "$WINDOW_XML" "$H264_OUTPUT"

MAC_PID=""
cleanup() {
    if [[ -n "$MAC_PID" ]] && kill -0 "$MAC_PID" >/dev/null 2>&1; then
        kill "$MAC_PID" >/dev/null 2>&1 || true
        wait "$MAC_PID" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

echo "==> Configuring adb reverse"
adb reverse --remove "tcp:$PORT" >/dev/null 2>&1 || true
adb reverse "tcp:$PORT" "tcp:$PORT"

echo "==> Starting synthetic MacHost stream"
(
    cd "$MAC_DIR"
    swift run phase0-spike \
        --synthetic-only \
        --duration 60 \
        --fps 5 \
        --width 320 \
        --height 240 \
        --bitrate-mbps 1 \
        --output "$H264_OUTPUT" \
        --port "$PORT" \
        --no-adb-reverse \
        --wait-for-client 8 \
        --log-input-events
) >"$MAC_LOG" 2>&1 &
MAC_PID=$!

echo "==> Launching AndroidReceiver with touch input enabled"
adb logcat -c || true
adb shell am force-stop "$PACKAGE_NAME" >/dev/null 2>&1 || true
adb shell am start --ez touch_enabled true --ez debug_input_logging true -n "$ACTIVITY_NAME" | tr -d '\r'
sleep 2

adb shell uiautomator dump /sdcard/android-monitor-window.xml >/dev/null
adb exec-out cat /sdcard/android-monitor-window.xml | tr -d '\r' >"$WINDOW_XML"

read -r CENTER_X CENTER_Y DRAG_X1 DRAG_Y1 DRAG_X2 DRAG_Y2 < <(
    python3 - "$WINDOW_XML" <<'PY'
import re
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    xml = handle.read()

bounds = [tuple(map(int, match)) for match in re.findall(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', xml)]
if not bounds:
    raise SystemExit("no UI bounds found")
max_x = max(b[2] for b in bounds)
max_y = max(b[3] for b in bounds)
center_x = max_x // 2
center_y = max_y // 2
drag_x1 = max(20, center_x - max_x // 8)
drag_x2 = min(max_x - 20, center_x + max_x // 8)
print(center_x, center_y, drag_x1, center_y, drag_x2, center_y)
PY
)

echo "==> Sending tap and drag gestures"
adb shell input tap "$CENTER_X" "$CENTER_Y"
sleep 0.2
adb shell input swipe "$DRAG_X1" "$DRAG_Y1" "$DRAG_X2" "$DRAG_Y2" 500

echo "==> Waiting for MacHost input-event logs"
deadline=$((SECONDS + 12))
while (( SECONDS < deadline )); do
    if grep -q "Android input: action=down" "$MAC_LOG" \
        && grep -q "Android input: action=up" "$MAC_LOG" \
        && grep -q "Android input: action=move" "$MAC_LOG"; then
        break
    fi
    sleep 0.25
done

adb logcat -d -v time AndroidMonitorInput:I AndroidMonitorStream:W '*:S' \
    | tr -d '\r' \
    | grep -E 'AndroidMonitorInput|Failed to send touch|Touch input initial' \
    >"$ANDROID_LOG" || true

for action in down up move; do
    if ! grep -q "Android input: action=$action" "$MAC_LOG"; then
        cat "$MAC_LOG" >&2 || true
        cat "$ANDROID_LOG" >&2 || true
        echo "[FAIL] Missing logged Android touch action: $action" >&2
        exit 1
    fi
done

cleanup
MAC_PID=""

grep "Android input: action=" "$MAC_LOG" | tail -n 8
echo "[OK] Phone touch protocol smoke passed. Artifacts: $OUTPUT_DIR"

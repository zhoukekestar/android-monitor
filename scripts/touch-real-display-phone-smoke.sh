#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAC_DIR="$ROOT_DIR/MacHost"
APK_PATH="$ROOT_DIR/AndroidReceiver/app/build/outputs/apk/debug/android-receiver-debug.apk"
PACKAGE_NAME="com.androidmonitor.receiver"
ACTIVITY_NAME="$PACKAGE_NAME/.MainActivity"
PORT="${PHASE0_STREAM_PORT:-38888}"
OUTPUT_DIR="/tmp/android-monitor-touch-real-display-phone-smoke"
MAC_LOG="$OUTPUT_DIR/mac-host.log"
ANDROID_LOG="$OUTPUT_DIR/android-input-logcat.log"
WINDOW_XML="$OUTPUT_DIR/window.xml"
H264_OUTPUT="$OUTPUT_DIR/stream.h264"
ACCESSIBILITY_LOG="$OUTPUT_DIR/accessibility.log"
DURATION=45
SKIP_INSTALL=0
REQUIRE_SCROLL=0
SCROLL_TIMEOUT=120

usage() {
    cat <<'EOF'
touch-real-display-phone-smoke.sh

Runs a strict real-virtual-display phone input smoke. The script requires a
clean display audit and Accessibility permission, starts a real TextEdit-backed
stream with MacHost input-event logging, launches AndroidReceiver with touch
enabled, sends ADB tap/drag gestures, and verifies MacHost received the touch
messages while mapped to a real virtual display.

This verifies the phone-to-Mac input path on a real virtual display. Use
--require-scroll for a manual two-finger scroll check while the stream is
running.

Options:
  --skip-install     Do not install the debug APK before launching.
  --duration <sec>   Default: 45.
  --output-dir <p>   Default: /tmp/android-monitor-touch-real-display-phone-smoke.
  --require-scroll   Wait for a manually performed two-finger scroll event.
  --scroll-timeout <sec>
                     Seconds to wait for --require-scroll. Default: 120.
  --help             Show this message.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-install)
            SKIP_INSTALL=1
            ;;
        --duration)
            DURATION="${2:?--duration requires a value}"
            shift
            ;;
        --output-dir)
            OUTPUT_DIR="${2:?--output-dir requires a value}"
            MAC_LOG="$OUTPUT_DIR/mac-host.log"
            ANDROID_LOG="$OUTPUT_DIR/android-input-logcat.log"
            WINDOW_XML="$OUTPUT_DIR/window.xml"
            H264_OUTPUT="$OUTPUT_DIR/stream.h264"
            ACCESSIBILITY_LOG="$OUTPUT_DIR/accessibility.log"
            shift
            ;;
        --require-scroll)
            REQUIRE_SCROLL=1
            ;;
        --scroll-timeout)
            SCROLL_TIMEOUT="${2:?--scroll-timeout requires a value}"
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

if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [[ "$DURATION" -lt 20 ]]; then
    echo "[FAIL] --duration must be an integer >= 20: $DURATION" >&2
    exit 2
fi
if ! [[ "$SCROLL_TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$SCROLL_TIMEOUT" -le 0 ]]; then
    echo "[FAIL] --scroll-timeout must be a positive integer: $SCROLL_TIMEOUT" >&2
    exit 2
fi

STREAM_DURATION="$DURATION"
if [[ "$REQUIRE_SCROLL" -eq 1 ]]; then
    MIN_SCROLL_STREAM_DURATION=$((SCROLL_TIMEOUT + 30))
    if [[ "$STREAM_DURATION" -lt "$MIN_SCROLL_STREAM_DURATION" ]]; then
        STREAM_DURATION="$MIN_SCROLL_STREAM_DURATION"
    fi
fi

if ! command -v adb >/dev/null 2>&1; then
    echo "[FAIL] adb was not found on PATH" >&2
    exit 1
fi

"$ROOT_DIR/scripts/display-audit.sh" --fail-on-stale

mkdir -p "$OUTPUT_DIR"
rm -f "$MAC_LOG" "$ANDROID_LOG" "$WINDOW_XML" "$H264_OUTPUT" "$ACCESSIBILITY_LOG"

if ! (cd "$MAC_DIR" && swift run phase0-spike --check-accessibility-permission) >"$ACCESSIBILITY_LOG" 2>&1; then
    cat "$ACCESSIBILITY_LOG" >&2 || true
    cat >&2 <<EOF
[FAIL] Accessibility permission is required before real touch injection can be accepted.
       Grant Accessibility to the terminal or Android Monitor Host app, then rerun.
EOF
    exit 5
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

echo "==> Starting real virtual-display MacHost stream"
(
    cd "$MAC_DIR"
    swift run phase0-spike \
        --duration "$STREAM_DURATION" \
        --fps 15 \
        --width 1024 \
        --height 600 \
        --bitrate-mbps 2 \
        --output "$H264_OUTPUT" \
        --port "$PORT" \
        --no-adb-reverse \
        --wait-for-client 8 \
        --external-textedit-window \
        --pre-capture-delay 3 \
        --log-input-events
) >"$MAC_LOG" 2>&1 &
MAC_PID=$!

echo "==> Launching AndroidReceiver with touch input enabled"
adb logcat -c || true
adb shell am force-stop "$PACKAGE_NAME" >/dev/null 2>&1 || true
adb shell am start --ez touch_enabled true --ez debug_input_logging true -n "$ACTIVITY_NAME" | tr -d '\r'

echo "==> Waiting for Android client_hello"
deadline=$((SECONDS + 20))
while (( SECONDS < deadline )); do
    if grep -q "Android hello:" "$MAC_LOG"; then
        break
    fi
    sleep 0.25
done
if ! grep -q "Android hello:" "$MAC_LOG"; then
    cat "$MAC_LOG" >&2 || true
    echo "[FAIL] MacHost did not receive Android client_hello." >&2
    exit 7
fi

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

echo "==> Waiting for MacHost tap/drag input-event logs"
deadline=$((SECONDS + 12))
while (( SECONDS < deadline )); do
    if grep -q "Android input: action=down" "$MAC_LOG" \
        && grep -q "Android input: action=up" "$MAC_LOG" \
        && grep -q "Android input: action=move" "$MAC_LOG"; then
        break
    fi
    sleep 0.25
done

if [[ "$REQUIRE_SCROLL" -eq 1 ]]; then
    echo "==> Perform a two-finger scroll on the Android screen now"
    deadline=$((SECONDS + SCROLL_TIMEOUT))
    while (( SECONDS < deadline )); do
        if grep -q "Android input: action=scroll" "$MAC_LOG"; then
            break
        fi
        sleep 0.25
    done
fi

for action in down up move; do
    if ! grep -q "Android input: action=$action" "$MAC_LOG"; then
        cat "$MAC_LOG" >&2 || true
        echo "[FAIL] Missing logged Android touch action: $action" >&2
        exit 8
    fi
done
if [[ "$REQUIRE_SCROLL" -eq 1 ]] && ! grep -q "Android input: action=scroll" "$MAC_LOG"; then
    cat "$MAC_LOG" >&2 || true
    echo "[FAIL] Missing logged Android two-finger scroll action." >&2
    exit 9
fi

echo "==> Waiting for MacHost stream to finish"
if ! wait "$MAC_PID"; then
    MAC_PID=""
    cat "$MAC_LOG" >&2 || true
    echo "[FAIL] MacHost stream failed." >&2
    exit 10
fi
MAC_PID=""

adb logcat -d -v time AndroidMonitorInput:I AndroidMonitorStream:W '*:S' \
    | tr -d '\r' \
    | grep -E 'AndroidMonitorInput|Failed to send touch|Touch input initial' \
    >"$ANDROID_LOG" || true

"$ROOT_DIR/scripts/verify-annexb-keyframe.py" "$H264_OUTPUT"
"$ROOT_DIR/scripts/verify-h264-freshness.py" \
    "$H264_OUTPUT" \
    --fps 1 \
    --min-frames 4 \
    --keep-frames "$OUTPUT_DIR/decoded-frames"

if grep -q '\[WARN\] No captured frames arrived' "$MAC_LOG"; then
    echo "[FAIL] MacHost fell back to synthetic frames." >&2
    exit 11
fi
if ! grep -E '\[OK\] Capture finished: [1-9][0-9]* frames' "$MAC_LOG" >/dev/null; then
    echo "[FAIL] MacHost did not report captured real frames." >&2
    exit 12
fi
if ! grep -E '\[INFO\] Android stats: decoded=[1-9][0-9]*' "$MAC_LOG" >/dev/null; then
    echo "[FAIL] No decoded-frame stats were received from Android." >&2
    exit 13
fi

"$ROOT_DIR/scripts/display-audit.sh" --fail-on-stale

grep "Android input: action=" "$MAC_LOG" | tail -n 12
echo "[OK] Real-display phone touch smoke passed. Artifacts: $OUTPUT_DIR"

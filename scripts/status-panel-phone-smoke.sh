#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAC_DIR="$ROOT_DIR/MacHost"
APK_PATH="$ROOT_DIR/AndroidReceiver/app/build/outputs/apk/debug/android-receiver-debug.apk"
PACKAGE_NAME="com.androidmonitor.receiver"
ACTIVITY_NAME="$PACKAGE_NAME/.MainActivity"
PORT="${STATUS_PANEL_PORT:-38889}"
OUTPUT_DIR="/tmp/android-monitor-status-phone-smoke"
SERVER_LOG="$OUTPUT_DIR/status-panel-server.log"
LOGCAT_LOG="$OUTPUT_DIR/android-status-logcat.log"
WINDOW_XML="$OUTPUT_DIR/window.xml"
SKIP_INSTALL=0

usage() {
    cat <<'EOF'
status-panel-phone-smoke.sh

Runs a phone Status Panel smoke without creating a virtual display. The script
starts status-panel-server, configures adb reverse, launches AndroidReceiver,
taps the Status button through UI automation, and requires Android logcat to
report a received status snapshot.

Options:
  --skip-install   Do not install the debug APK before launching.
  --port <port>    Default: 38889, or STATUS_PANEL_PORT.
  --output-dir <p> Default: /tmp/android-monitor-status-phone-smoke.
  --help           Show this message.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-install)
            SKIP_INSTALL=1
            ;;
        --port)
            PORT="${2:?--port requires a value}"
            shift
            ;;
        --output-dir)
            OUTPUT_DIR="${2:?--output-dir requires a value}"
            SERVER_LOG="$OUTPUT_DIR/status-panel-server.log"
            LOGCAT_LOG="$OUTPUT_DIR/android-status-logcat.log"
            WINDOW_XML="$OUTPUT_DIR/window.xml"
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
rm -f "$SERVER_LOG" "$LOGCAT_LOG" "$WINDOW_XML"

SERVER_PID=""
cleanup() {
    if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" >/dev/null 2>&1; then
        kill "$SERVER_PID" >/dev/null 2>&1 || true
        wait "$SERVER_PID" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

echo "==> Building status-panel server"
(cd "$MAC_DIR" && swift build --product status-panel-server)

echo "==> Starting status-panel server on localhost:$PORT"
(cd "$ROOT_DIR" && "$MAC_DIR/.build/debug/status-panel-server" "$PORT") >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!
sleep 1

echo "==> Configuring adb reverse"
adb reverse --remove "tcp:$PORT" >/dev/null 2>&1 || true
adb reverse "tcp:$PORT" "tcp:$PORT"

echo "==> Launching AndroidReceiver"
adb logcat -c || true
adb shell am force-stop "$PACKAGE_NAME" >/dev/null 2>&1 || true
adb shell am start -n "$ACTIVITY_NAME" | tr -d '\r'
sleep 2

echo "==> Tapping Status mode"
adb shell uiautomator dump /sdcard/android-monitor-window.xml >/dev/null
adb exec-out cat /sdcard/android-monitor-window.xml | tr -d '\r' >"$WINDOW_XML"
TAP_COORDS="$(python3 - "$WINDOW_XML" <<'PY'
import re
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    xml = handle.read()

match = re.search(r'text="Status"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', xml)
if not match:
    raise SystemExit(1)
x1, y1, x2, y2 = map(int, match.groups())
print(f"{(x1 + x2) // 2} {(y1 + y2) // 2}")
PY
)"
adb shell input tap $TAP_COORDS
sleep 5

echo "==> Checking Android status logs"
adb logcat -d -v time AndroidMonitorStatus:I '*:S' | tr -d '\r' >"$LOGCAT_LOG"
if ! grep -q "Status snapshot received" "$LOGCAT_LOG"; then
    cat "$SERVER_LOG" >&2 || true
    cat "$LOGCAT_LOG" >&2 || true
    echo "[FAIL] No Android status snapshot log found." >&2
    exit 1
fi

grep "Status snapshot received" "$LOGCAT_LOG" | tail -n 3
echo "[OK] Phone Status Panel smoke passed. Artifacts: $OUTPUT_DIR"

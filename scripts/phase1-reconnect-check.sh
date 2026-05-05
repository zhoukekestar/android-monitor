#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAC_DIR="$ROOT_DIR/MacHost"
PACKAGE_NAME="com.androidmonitor.receiver"
ACTIVITY_NAME="com.androidmonitor.receiver/.MainActivity"

WIDTH=1024
HEIGHT=600
FPS=15
BITRATE_MBPS=2
DURATION=24
PORT="${PHASE0_STREAM_PORT:-38888}"
OUTPUT_DIR="/tmp/android-monitor-phase1-reconnect"

usage() {
    cat <<'EOF'
phase1-reconnect-check.sh

Runs a Phase 1 reconnect gate. MacHost stays running while AndroidReceiver is
force-stopped and relaunched mid-stream. The gate requires a second
client_hello and decoded-frame stats after that second connection.

Options:
  --output-dir <path>   Default: /tmp/android-monitor-phase1-reconnect
  --help                Show this message.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir)
            OUTPUT_DIR="${2:?--output-dir requires a value}"
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

"$ROOT_DIR/scripts/display-audit.sh" --fail-on-stale

echo "==> Checking authorized Android device"
ADB_DEVICES="$(adb devices)"
printf '%s\n' "$ADB_DEVICES"
if ! printf '%s\n' "$ADB_DEVICES" | awk 'NR > 1 && $2 == "device" { found = 1 } END { exit found ? 0 : 1 }'; then
    echo "[FAIL] No authorized adb device found." >&2
    exit 3
fi

echo "==> Verifying AndroidReceiver is installed"
INSTALLED_PACKAGES="$(adb shell pm list packages "$PACKAGE_NAME" | tr -d '\r')"
if ! printf '%s\n' "$INSTALLED_PACKAGES" | grep -q "^package:$PACKAGE_NAME$"; then
    echo "[FAIL] $PACKAGE_NAME is not installed." >&2
    exit 6
fi

mkdir -p "$OUTPUT_DIR"
MAC_LOG="$OUTPUT_DIR/mac-host.log"
ANDROID_LOG="$OUTPUT_DIR/android-logcat.log"
H264_OUTPUT="$OUTPUT_DIR/stream.h264"
rm -f "$MAC_LOG" "$ANDROID_LOG" "$H264_OUTPUT"

LOGCAT_PID=""
MAC_PID=""
cleanup() {
    if [[ -n "$MAC_PID" ]] && kill -0 "$MAC_PID" >/dev/null 2>&1; then
        kill "$MAC_PID" >/dev/null 2>&1 || true
        wait "$MAC_PID" >/dev/null 2>&1 || true
    fi
    if [[ -n "$LOGCAT_PID" ]] && kill -0 "$LOGCAT_PID" >/dev/null 2>&1; then
        kill "$LOGCAT_PID" >/dev/null 2>&1 || true
        wait "$LOGCAT_PID" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

wait_for_shell_condition() {
    local description="$1"
    local timeout_seconds="$2"
    local start
    start="$(date +%s)"
    while true; do
        if eval "$3"; then
            return 0
        fi

        if [[ -n "$MAC_PID" ]] && ! kill -0 "$MAC_PID" >/dev/null 2>&1; then
            echo "[FAIL] MacHost exited before: $description" >&2
            cat "$MAC_LOG" >&2 || true
            exit 1
        fi

        if (( $(date +%s) - start >= timeout_seconds )); then
            echo "[FAIL] Timed out waiting for: $description" >&2
            echo "       See $MAC_LOG and $ANDROID_LOG" >&2
            exit 1
        fi
        sleep 0.5
    done
}

echo "==> Configuring adb reverse"
adb reverse --remove "tcp:$PORT" >/dev/null 2>&1 || true
adb reverse "tcp:$PORT" "tcp:$PORT"
{
    echo "[OK] adb reverse command accepted: tcp:$PORT -> tcp:$PORT"
    echo "[INFO] Skipped adb reverse --list because some Android 5 adbd builds disconnect after that diagnostic call."
} | tee "$OUTPUT_DIR/adb-reverse.txt"

echo "==> Capturing Android logs"
adb logcat -c || true
adb logcat -v time AndroidMonitorStream:V AndroidMonitorDecoder:V '*:S' >"$ANDROID_LOG" 2>&1 &
LOGCAT_PID=$!

echo "==> Launching AndroidReceiver"
adb shell am force-stop "$PACKAGE_NAME" >/dev/null 2>&1 || true
sleep 0.5
adb shell am start -n "$ACTIVITY_NAME" | tr -d '\r'
sleep 1

echo "==> Starting MacHost stream"
(
    cd "$MAC_DIR"
    swift run phase0-spike \
        --width "$WIDTH" \
        --height "$HEIGHT" \
        --fps "$FPS" \
        --bitrate-mbps "$BITRATE_MBPS" \
        --duration "$DURATION" \
        --output "$H264_OUTPUT" \
        --port "$PORT" \
        --no-adb-reverse \
        --external-textedit-window \
        --pre-capture-delay 2
) >"$MAC_LOG" 2>&1 &
MAC_PID=$!

wait_for_shell_condition \
    "initial Android client_hello" \
    20 \
    "grep -q '\\[OK\\] Android hello:' '$MAC_LOG'"

wait_for_shell_condition \
    "initial decoded-frame stats" \
    20 \
    "grep -E '\\[INFO\\] Android stats: decoded=[1-9][0-9]*' '$MAC_LOG' >/dev/null"

echo "==> Restarting AndroidReceiver while MacHost continues streaming"
adb shell am force-stop "$PACKAGE_NAME" >/dev/null 2>&1 || true
sleep 2
adb shell am start -n "$ACTIVITY_NAME" | tr -d '\r'

wait_for_shell_condition \
    "second Android client_hello" \
    20 \
    "[[ \$(grep -c '\\[OK\\] Android hello:' '$MAC_LOG' 2>/dev/null || true) -ge 2 ]]"

SECOND_HELLO_LINE="$(grep -n '\[OK\] Android hello:' "$MAC_LOG" | tail -n 1 | cut -d: -f1)"
wait_for_shell_condition \
    "decoded-frame stats after reconnect" \
    20 \
    "tail -n +$SECOND_HELLO_LINE '$MAC_LOG' | grep -E '\\[INFO\\] Android stats: decoded=[1-9][0-9]*' >/dev/null"

wait "$MAC_PID"
MAC_PID=""

cleanup
LOGCAT_PID=""
trap - EXIT

if [[ ! -s "$H264_OUTPUT" ]]; then
    echo "[FAIL] Stream output was not created: $H264_OUTPUT" >&2
    exit 1
fi

"$ROOT_DIR/scripts/verify-annexb-keyframe.py" "$H264_OUTPUT"

if ! grep -E '\[OK\] Capture finished: [1-9][0-9]* frames' "$MAC_LOG" >/dev/null; then
    echo "[FAIL] MacHost did not report captured real frames." >&2
    echo "       See $MAC_LOG and $ANDROID_LOG" >&2
    exit 10
fi

LAST_RECONNECT_STATS="$(tail -n +"$SECOND_HELLO_LINE" "$MAC_LOG" | grep -E '\[INFO\] Android stats: decoded=[1-9][0-9]*' | tail -n 1)"

cat <<EOF
[OK] Phase 1 reconnect check passed.
     $LAST_RECONNECT_STATS

Artifacts:
  Mac log:     $MAC_LOG
  Android log: $ANDROID_LOG
  H.264 file:  $H264_OUTPUT
EOF

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAC_DIR="$ROOT_DIR/MacHost"
. "$ROOT_DIR/scripts/lib/adb-path.sh"
PACKAGE_NAME="com.androidmonitor.receiver"
ACTIVITY_NAME="com.androidmonitor.receiver/.MainActivity"

WIDTH=1024
HEIGHT=600
FPS=15
BITRATE_MBPS=2
DURATION=10
PORT="${PHASE0_STREAM_PORT:-38888}"
OUTPUT_DIR="/tmp/android-monitor-phase0-stream-test"
SYNTHETIC_ONLY=0
TEST_CONTENT_WINDOW=0
EXTERNAL_TEXTEDIT_WINDOW=0
CURSOR_TEST_WINDOW=0
REQUIRE_REAL_CAPTURE=0
ALLOW_STALE_VIRTUAL_DISPLAYS=0
MIN_DECODED_FRAMES=1
MIN_INPUT_FPS=0
MAX_DROPPED_FRAMES=""
PRE_CAPTURE_DELAY=0

usage() {
    cat <<'EOF'
phase0-stream-test.sh

Runs the post-install Phase 0 decode/render test. Requires AndroidReceiver to
already be installed. The script configures adb reverse, launches the receiver,
runs phase0-spike, captures Mac and Android logs, and fails if no decoded-frame
stats are received from Android.

Options:
  --width <px>          Default: 1024
  --height <px>         Default: 600
  --fps <n>             Default: 15
  --bitrate-mbps <n>    Default: 2
  --duration <seconds>  Default: 10
  --port <port>         Default: 38888
  --output-dir <path>   Default: /tmp/android-monitor-phase0-stream-test
  --synthetic-only      Stream synthetic frames instead of creating/capturing a virtual display.
  --test-content-window Show animated host content on the virtual display during capture.
  --external-textedit-window
                        Show a normal animated TextEdit window on the virtual display during capture.
  --cursor-test-window Show a static cursor target and sweep the macOS cursor during capture.
  --pre-capture-delay <seconds>
                        Wait after setup before capture starts. Default: 0.
  --require-real-capture
                        Fail if MacHost falls back to synthetic frames.
                        Also fail if a stale Android Monitor virtual display
                        remains after MacHost exits.
  --allow-stale-virtual-displays
                        Do not preflight-fail when old CGVirtualDisplay instances are still online.
  --min-decoded-frames <n>
                        Require at least this many decoded frames in final Android stats. Default: 1.
  --min-input-fps <n>   Require at least this input FPS in final Android stats. Default: 0.
  --max-dropped-frames <n>
                        Fail if final Android stats report more dropped frames than this.
  --help                Show this message.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --width)
            WIDTH="${2:?--width requires a value}"
            shift
            ;;
        --height)
            HEIGHT="${2:?--height requires a value}"
            shift
            ;;
        --fps)
            FPS="${2:?--fps requires a value}"
            shift
            ;;
        --bitrate-mbps)
            BITRATE_MBPS="${2:?--bitrate-mbps requires a value}"
            shift
            ;;
        --duration)
            DURATION="${2:?--duration requires a value}"
            shift
            ;;
        --port)
            PORT="${2:?--port requires a value}"
            shift
            ;;
        --output-dir)
            OUTPUT_DIR="${2:?--output-dir requires a value}"
            shift
            ;;
        --synthetic-only)
            SYNTHETIC_ONLY=1
            ;;
        --test-content-window)
            TEST_CONTENT_WINDOW=1
            ;;
        --external-textedit-window)
            EXTERNAL_TEXTEDIT_WINDOW=1
            ;;
        --cursor-test-window)
            CURSOR_TEST_WINDOW=1
            ;;
        --pre-capture-delay)
            PRE_CAPTURE_DELAY="${2:?--pre-capture-delay requires a value}"
            shift
            ;;
        --require-real-capture)
            REQUIRE_REAL_CAPTURE=1
            ;;
        --allow-stale-virtual-displays)
            ALLOW_STALE_VIRTUAL_DISPLAYS=1
            ;;
        --min-decoded-frames)
            MIN_DECODED_FRAMES="${2:?--min-decoded-frames requires a value}"
            shift
            ;;
        --min-input-fps)
            MIN_INPUT_FPS="${2:?--min-input-fps requires a value}"
            shift
            ;;
        --max-dropped-frames)
            MAX_DROPPED_FRAMES="${2:?--max-dropped-frames requires a value}"
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

require_positive_int() {
    local name="$1"
    local value="$2"
    if ! [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" -le 0 ]]; then
        echo "[FAIL] $name must be a positive integer: $value" >&2
        exit 2
    fi
}

require_non_negative_int() {
    local name="$1"
    local value="$2"
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "[FAIL] $name must be a non-negative integer: $value" >&2
        exit 2
    fi
}

require_positive_int "--width" "$WIDTH"
require_positive_int "--height" "$HEIGHT"
require_positive_int "--fps" "$FPS"
require_positive_int "--bitrate-mbps" "$BITRATE_MBPS"
require_positive_int "--duration" "$DURATION"
require_positive_int "--port" "$PORT"
require_positive_int "--min-decoded-frames" "$MIN_DECODED_FRAMES"
if [[ -n "$MAX_DROPPED_FRAMES" ]]; then
    require_non_negative_int "--max-dropped-frames" "$MAX_DROPPED_FRAMES"
fi
if ! awk -v value="$MIN_INPUT_FPS" 'BEGIN { exit(value ~ /^[0-9]+([.][0-9]+)?$/ ? 0 : 1) }'; then
    echo "[FAIL] --min-input-fps must be a non-negative number: $MIN_INPUT_FPS" >&2
    exit 2
fi
if ! awk -v value="$PRE_CAPTURE_DELAY" 'BEGIN { exit(value ~ /^[0-9]+([.][0-9]+)?$/ ? 0 : 1) }'; then
    echo "[FAIL] --pre-capture-delay must be a non-negative number: $PRE_CAPTURE_DELAY" >&2
    exit 2
fi

if command -v lsof >/dev/null 2>&1; then
    PORT_LISTENERS="$(lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)"
    if [[ -n "$PORT_LISTENERS" ]]; then
        cat >&2 <<EOF
[FAIL] Mac TCP port $PORT is already in use, so the stream server cannot start.
       Stop the existing Android Monitor stream or quit Android Monitor Host, then rerun.

$PORT_LISTENERS
EOF
        exit 8
    fi
fi

if [[ "$REQUIRE_REAL_CAPTURE" -eq 1 && "$SYNTHETIC_ONLY" -ne 1 && "$ALLOW_STALE_VIRTUAL_DISPLAYS" -ne 1 ]]; then
    STALE_VIRTUAL_DISPLAY_COUNT="$("$ROOT_DIR/scripts/display-audit.sh" --count)"
    if [[ "$STALE_VIRTUAL_DISPLAY_COUNT" -gt 0 ]]; then
        cat >&2 <<EOF
[FAIL] Found $STALE_VIRTUAL_DISPLAY_COUNT stale Android Monitor virtual display(s) before strict real-capture testing.
       Log out or restart macOS to clear old CGVirtualDisplay instances, then rerun this command.
       To bypass this guard for diagnostics only, pass --allow-stale-virtual-displays.
EOF
        exit 11
    fi
fi

ADB_BIN="$(resolve_adb_bin)"
if [[ -z "$ADB_BIN" ]]; then
    echo "[FAIL] adb was not found from ANDROID_HOME, ANDROID_SDK_ROOT, ~/Library/Android/sdk, or PATH." >&2
    exit 1
fi

echo "==> Checking authorized Android device"
require_single_authorized_adb_device "$ADB_BIN"

echo "==> Verifying AndroidReceiver is installed"
INSTALLED_PACKAGES="$("$ADB_BIN" shell pm list packages "$PACKAGE_NAME" | tr -d '\r')"
if ! printf '%s\n' "$INSTALLED_PACKAGES" | grep -q "^package:$PACKAGE_NAME$"; then
    cat >&2 <<EOF
[FAIL] $PACKAGE_NAME is not installed.
       Install the APK manually or run scripts/stage-apk.sh, then install it
       from the phone's Downloads app before rerunning this stream test.
EOF
    exit 6
fi

mkdir -p "$OUTPUT_DIR"
MAC_LOG="$OUTPUT_DIR/mac-host.log"
ANDROID_LOG="$OUTPUT_DIR/android-logcat.log"
H264_OUTPUT="$OUTPUT_DIR/stream.h264"
rm -f "$MAC_LOG" "$ANDROID_LOG" "$H264_OUTPUT"

LOGCAT_PID=""
cleanup() {
    if [[ -n "$LOGCAT_PID" ]] && kill -0 "$LOGCAT_PID" >/dev/null 2>&1; then
        kill "$LOGCAT_PID" >/dev/null 2>&1 || true
        wait "$LOGCAT_PID" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

echo "==> Configuring adb reverse"
"$ADB_BIN" reverse --remove "tcp:$PORT" >/dev/null 2>&1 || true
"$ADB_BIN" reverse "tcp:$PORT" "tcp:$PORT"
{
    echo "[OK] adb reverse command accepted: tcp:$PORT -> tcp:$PORT"
    echo "[INFO] Skipped adb reverse --list because some Android 5 adbd builds disconnect after that diagnostic call."
} | tee "$OUTPUT_DIR/adb-reverse.txt"

echo "==> Capturing Android logs"
"$ADB_BIN" logcat -c || true
"$ADB_BIN" logcat -v time AndroidMonitorStream:V AndroidMonitorDecoder:V '*:S' >"$ANDROID_LOG" 2>&1 &
LOGCAT_PID=$!

echo "==> Launching AndroidReceiver"
"$ADB_BIN" shell am force-stop "$PACKAGE_NAME" >/dev/null 2>&1 || true
sleep 0.5
"$ADB_BIN" shell am start -n "$ACTIVITY_NAME" | tr -d '\r'
sleep 1

echo "==> Running Mac stream"
SPIKE_ARGS=(
    swift run phase0-spike
    --width "$WIDTH"
    --height "$HEIGHT"
    --fps "$FPS"
    --bitrate-mbps "$BITRATE_MBPS"
    --duration "$DURATION"
    --output "$H264_OUTPUT"
    --port "$PORT"
    --no-adb-reverse
)
if [[ "$SYNTHETIC_ONLY" -eq 1 ]]; then
    SPIKE_ARGS+=(--synthetic-only)
fi
if [[ "$TEST_CONTENT_WINDOW" -eq 1 ]]; then
    SPIKE_ARGS+=(--test-content-window)
fi
if [[ "$EXTERNAL_TEXTEDIT_WINDOW" -eq 1 ]]; then
    SPIKE_ARGS+=(--external-textedit-window)
fi
if [[ "$CURSOR_TEST_WINDOW" -eq 1 ]]; then
    SPIKE_ARGS+=(--cursor-test-window)
fi
if [[ "$PRE_CAPTURE_DELAY" != "0" ]]; then
    SPIKE_ARGS+=(--pre-capture-delay "$PRE_CAPTURE_DELAY")
fi

(
    cd "$MAC_DIR"
    "${SPIKE_ARGS[@]}"
) 2>&1 | tee "$MAC_LOG"

cleanup
LOGCAT_PID=""
trap - EXIT

if [[ ! -s "$H264_OUTPUT" ]]; then
    echo "[FAIL] Stream output was not created: $H264_OUTPUT" >&2
    exit 1
fi

"$ROOT_DIR/scripts/verify-annexb-keyframe.py" "$H264_OUTPUT"

if [[ "$REQUIRE_REAL_CAPTURE" -eq 1 ]]; then
    if grep -q '\[WARN\] No captured frames arrived' "$MAC_LOG"; then
        echo "[FAIL] MacHost fell back to synthetic frames." >&2
        echo "       See $MAC_LOG and $ANDROID_LOG" >&2
        exit 9
    fi
    if ! grep -E '\[OK\] Capture finished: [1-9][0-9]* frames' "$MAC_LOG" >/dev/null; then
        echo "[FAIL] MacHost did not report captured real frames." >&2
        echo "       See $MAC_LOG and $ANDROID_LOG" >&2
        exit 10
    fi
fi

if ! grep -q '\[OK\] Android hello:' "$MAC_LOG"; then
    echo "[FAIL] Mac host did not receive Android client_hello." >&2
    echo "       See $MAC_LOG and $ANDROID_LOG" >&2
    exit 7
fi

if ! grep -E '\[INFO\] Android stats: decoded=[1-9][0-9]*' "$MAC_LOG" >/dev/null; then
    echo "[FAIL] No decoded-frame stats were received from Android." >&2
    echo "       See $MAC_LOG and $ANDROID_LOG" >&2
    exit 8
fi

LAST_STATS="$(grep -E '\[INFO\] Android stats:' "$MAC_LOG" | tail -n 1)"
if [[ ! "$LAST_STATS" =~ decoded=([0-9]+)[[:space:]]dropped=([0-9]+)[[:space:]]input=([0-9]+([.][0-9]+)?)[[:space:]]fps ]]; then
    echo "[FAIL] Could not parse final Android stats line." >&2
    echo "       $LAST_STATS" >&2
    exit 12
fi

FINAL_DECODED_FRAMES="${BASH_REMATCH[1]}"
FINAL_DROPPED_FRAMES="${BASH_REMATCH[2]}"
FINAL_INPUT_FPS="${BASH_REMATCH[3]}"

if [[ "$FINAL_DECODED_FRAMES" -lt "$MIN_DECODED_FRAMES" ]]; then
    echo "[FAIL] Final decoded frame count $FINAL_DECODED_FRAMES is below required minimum $MIN_DECODED_FRAMES." >&2
    echo "       $LAST_STATS" >&2
    echo "       See $MAC_LOG and $ANDROID_LOG" >&2
    exit 13
fi

if ! awk -v actual="$FINAL_INPUT_FPS" -v minimum="$MIN_INPUT_FPS" 'BEGIN { exit(actual + 0 >= minimum + 0 ? 0 : 1) }'; then
    echo "[FAIL] Final input FPS $FINAL_INPUT_FPS is below required minimum $MIN_INPUT_FPS." >&2
    echo "       $LAST_STATS" >&2
    echo "       See $MAC_LOG and $ANDROID_LOG" >&2
    exit 14
fi

if [[ -n "$MAX_DROPPED_FRAMES" && "$FINAL_DROPPED_FRAMES" -gt "$MAX_DROPPED_FRAMES" ]]; then
    echo "[FAIL] Final dropped frame count $FINAL_DROPPED_FRAMES is above maximum $MAX_DROPPED_FRAMES." >&2
    echo "       $LAST_STATS" >&2
    echo "       See $MAC_LOG and $ANDROID_LOG" >&2
    exit 15
fi

if [[ "$REQUIRE_REAL_CAPTURE" -eq 1 && "$SYNTHETIC_ONLY" -ne 1 && "$ALLOW_STALE_VIRTUAL_DISPLAYS" -ne 1 ]]; then
    POST_RUN_STALE_VIRTUAL_DISPLAY_COUNT="$("$ROOT_DIR/scripts/display-audit.sh" --count)"
    if [[ "$POST_RUN_STALE_VIRTUAL_DISPLAY_COUNT" -gt 0 ]]; then
        echo "[FAIL] Found $POST_RUN_STALE_VIRTUAL_DISPLAY_COUNT stale Android Monitor virtual display(s) after strict real-capture testing." >&2
        echo "       MacHost must release the virtual display before this gate can pass." >&2
        echo "       Log out or restart macOS to clear the current WindowServer state before rerunning." >&2
        "$ROOT_DIR/scripts/display-audit.sh" >&2 || true
        exit 16
    fi
fi

cat <<EOF
[OK] Phase 0 stream test received Android decoder stats.
     $LAST_STATS

Artifacts:
  Mac log:     $MAC_LOG
  Android log: $ANDROID_LOG
  H.264 file:  $H264_OUTPUT
EOF

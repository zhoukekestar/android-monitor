#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAC_DIR="$ROOT_DIR/MacHost"
ANDROID_DIR="$ROOT_DIR/AndroidReceiver"
GRADLEW="$ROOT_DIR/gradlew"
APK_PATH="$ANDROID_DIR/app/build/outputs/apk/debug/android-receiver-debug.apk"
SMOKE_H264="/tmp/android-monitor-phase0-check.h264"
PROTOCOL_H264="/tmp/android-monitor-phase0-protocol.h264"
PROTOCOL_LOG="/tmp/android-monitor-phase0-protocol.log"
PROTOCOL_PORT="${PHASE0_PROTOCOL_PORT:-38999}"

JAVA_HOME_DEFAULT="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
ANDROID_HOME_DEFAULT="$HOME/Library/Android/sdk"

SKIP_DEVICE=0
SKIP_INSTALL=0

usage() {
    cat <<'EOF'
phase0-check.sh

Builds the Mac spike, verifies synthetic H.264 encode, builds the Android API 21
receiver, and optionally installs it on an authorized USB-debugging device.

Options:
  --skip-device    Do not require adb or an authorized Android device.
  --skip-install   Require the app to already be installed; only set up ADB reverse and launch it.
  --help           Show this message.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-device)
            SKIP_DEVICE=1
            ;;
        --skip-install)
            SKIP_INSTALL=1
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

echo "==> Building MacHost"
(cd "$MAC_DIR" && swift build)

echo "==> Verifying synthetic H.264 encode"
(
    cd "$MAC_DIR"
    swift run phase0-spike \
        --synthetic-only \
        --duration 1 \
        --fps 5 \
        --width 320 \
        --height 240 \
        --bitrate-mbps 1 \
        --output "$SMOKE_H264" \
        --no-server
)

if [[ ! -s "$SMOKE_H264" ]]; then
    echo "[FAIL] Synthetic H.264 output was not created: $SMOKE_H264" >&2
    exit 1
fi
echo "[OK] Synthetic H.264 output: $SMOKE_H264 ($(wc -c < "$SMOKE_H264") bytes)"
"$ROOT_DIR/scripts/verify-annexb-keyframe.py" "$SMOKE_H264"

echo "==> Verifying localhost stream protocol"
rm -f "$PROTOCOL_H264" "$PROTOCOL_LOG"
SERVER_PID=""
cleanup_protocol_server() {
    if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" >/dev/null 2>&1; then
        kill "$SERVER_PID" >/dev/null 2>&1 || true
        wait "$SERVER_PID" >/dev/null 2>&1 || true
    fi
}
trap cleanup_protocol_server EXIT
(
    cd "$MAC_DIR"
    swift run phase0-spike \
        --synthetic-only \
        --duration 4 \
        --fps 5 \
        --width 320 \
        --height 240 \
        --bitrate-mbps 1 \
        --output "$PROTOCOL_H264" \
        --port "$PROTOCOL_PORT" \
        --no-adb-reverse
) >"$PROTOCOL_LOG" 2>&1 &
SERVER_PID=$!

if ! "$ROOT_DIR/scripts/protocol-smoke.py" \
    --port "$PROTOCOL_PORT" \
    --expect-width 320 \
    --expect-height 240 \
    --expect-fps 5 \
    --expect-bitrate-mbps 1; then
    cat "$PROTOCOL_LOG" >&2 || true
    exit 1
fi

wait "$SERVER_PID"
SERVER_PID=""
trap - EXIT

if [[ ! -x "$GRADLEW" ]]; then
    echo "[FAIL] Gradle wrapper not found or not executable: $GRADLEW" >&2
    exit 1
fi

if [[ -z "${JAVA_HOME:-}" || ! -x "$JAVA_HOME/bin/java" ]]; then
    export JAVA_HOME="$JAVA_HOME_DEFAULT"
fi

if [[ -z "${ANDROID_HOME:-}" || ! -d "$ANDROID_HOME" ]]; then
    export ANDROID_HOME="$ANDROID_HOME_DEFAULT"
fi

echo "==> Building AndroidReceiver"
"$GRADLEW" :android-receiver:assembleDebug

if [[ ! -s "$APK_PATH" ]]; then
    echo "[FAIL] APK was not created: $APK_PATH" >&2
    exit 1
fi
echo "[OK] Android APK: $APK_PATH ($(wc -c < "$APK_PATH") bytes)"

echo "==> Running AndroidReceiver unit tests"
"$GRADLEW" :android-receiver:testDebugUnitTest

echo "==> Auditing macOS virtual display state"
"$ROOT_DIR/scripts/display-audit.sh" || true

if [[ "$SKIP_DEVICE" -eq 1 ]]; then
    echo "[OK] Build-only Phase 0 checks passed"
    exit 0
fi

echo "==> Checking macOS screen capture permission"
set +e
(
    cd "$MAC_DIR"
    swift run phase0-spike --check-screen-capture-permission
)
CAPTURE_PERMISSION_STATUS=$?
set -e

if [[ "$CAPTURE_PERMISSION_STATUS" -ne 0 ]]; then
    echo "[FAIL] macOS screen capture permission is not granted." >&2
    echo "       Grant Screen/System Audio Recording to the launcher terminal/app." >&2
fi

if ! command -v adb >/dev/null 2>&1; then
    echo "[FAIL] adb was not found on PATH" >&2
    exit 1
fi

echo "==> Checking authorized Android device"
ADB_DEVICES="$(adb devices)"
echo "$ADB_DEVICES"

if ! printf '%s\n' "$ADB_DEVICES" | awk 'NR > 1 && $2 == "device" { found = 1 } END { exit found ? 0 : 1 }'; then
    echo "[FAIL] No authorized adb device found." >&2
    echo "       Unlock the phone and accept the USB debugging prompt, then rerun this script." >&2
    exit 3
fi

if [[ "$SKIP_INSTALL" -eq 1 ]]; then
    echo "==> Verifying AndroidReceiver is already installed"
    INSTALLED_PACKAGES="$(adb shell pm list packages com.androidmonitor.receiver | tr -d '\r')"
    if ! printf '%s\n' "$INSTALLED_PACKAGES" | grep -q '^package:com\.androidmonitor\.receiver$'; then
        cat >&2 <<'EOF'
[FAIL] AndroidReceiver is not installed on the device.
       Install AndroidReceiver/app/build/outputs/apk/debug/android-receiver-debug.apk manually
       on the phone, then rerun:
       scripts/phase0-check.sh --skip-install
EOF
        exit 6
    fi
    echo "[OK] AndroidReceiver package is installed"
else
    echo "==> Installing AndroidReceiver"
    set +e
    INSTALL_OUTPUT="$(adb install -r -d "$APK_PATH" 2>&1)"
    INSTALL_STATUS=$?
    set -e
    printf '%s\n' "$INSTALL_OUTPUT"

    if [[ "$INSTALL_STATUS" -ne 0 ]]; then
        if printf '%s\n' "$INSTALL_OUTPUT" | grep -q 'INSTALL_FAILED_USER_RESTRICTED'; then
            cat >&2 <<'EOF'
[FAIL] Android blocked USB installation: INSTALL_FAILED_USER_RESTRICTED.
       On Xiaomi/MIUI devices, enable Developer Options settings such as:
       - USB debugging
       - Install via USB
       - USB debugging (Security settings), if present
       If USB install remains blocked, install the APK manually on the phone and rerun:
       scripts/phase0-check.sh --skip-install
EOF
            exit 5
        fi
        echo "[FAIL] adb install failed." >&2
        exit "$INSTALL_STATUS"
    fi
fi

echo "==> Configuring adb reverse for USB stream"
adb reverse --remove tcp:38888 >/dev/null 2>&1 || true
adb reverse tcp:38888 tcp:38888
echo "[OK] adb reverse command accepted: tcp:38888 -> tcp:38888"

echo "==> Launching AndroidReceiver"
adb shell am start -n com.androidmonitor.receiver/.MainActivity

if [[ "$CAPTURE_PERMISSION_STATUS" -ne 0 ]]; then
    cat <<EOF
[WARN] Device setup complete, but macOS capture permission is still missing.

Next:
  1. Grant Screen/System Audio Recording to the launcher terminal/app.
  2. Quit and reopen that terminal/app.
  3. Re-run:
     cd "$MAC_DIR"
     swift run phase0-spike --check-screen-capture-permission
EOF
    exit 4
fi

cat <<EOF
[OK] Device setup complete.

Next:
  cd "$MAC_DIR"
  swift run phase0-spike --request-screen-capture-permission --width 1024 --height 600 --fps 15 --bitrate-mbps 2 --duration 10
EOF

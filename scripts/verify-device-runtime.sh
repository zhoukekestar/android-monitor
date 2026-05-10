#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
. "$ROOT_DIR/scripts/lib/adb-path.sh"

WIDTH="${WIDTH:-1024}"
HEIGHT="${HEIGHT:-600}"
FPS="${FPS:-15}"
BITRATE_MBPS="${BITRATE_MBPS:-2}"
DURATION="${DURATION:-10}"
SKIP_INSTALL=0
REAL_DISPLAY=0

usage() {
    cat <<'EOF'
verify-device-runtime.sh

Runs the final phone-connected runtime gate:
  1. Require exactly one authorized ADB device, unless ANDROID_SERIAL is set.
  2. Build/install/launch AndroidReceiver, unless --skip-install is used.
  3. Run a short USB H.264 streaming verification against the phone.

By default this uses synthetic host frames and does not create a macOS virtual
display. Pass --real-display for the stricter capture path after display-audit
reports no stale Android Monitor virtual displays.

Options:
  --skip-install         Use the already installed AndroidReceiver package.
                         This is useful when the phone blocks reinstall or has
                         a differently signed working client installed.
  --real-display         Create/capture a macOS CGVirtualDisplay instead of
                         using synthetic frames. Refuses to run if stale
                         Android Monitor virtual displays are online.

Environment overrides:
  ANDROID_SERIAL=<serial>  Required when multiple authorized devices are connected.
  WIDTH=1024 HEIGHT=600 FPS=15 BITRATE_MBPS=2 DURATION=10

EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-install)
            SKIP_INSTALL=1
            ;;
        --real-display)
            REAL_DISPLAY=1
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

if [[ (! -x "${JAVA_HOME:-}/bin/java") && -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]]; then
    export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
fi

ADB_BIN="$(resolve_adb_bin)"
if [[ -z "$ADB_BIN" ]]; then
    echo "[FAIL] adb was not found from ANDROID_HOME, ANDROID_SDK_ROOT, ~/Library/Android/sdk, or PATH." >&2
    echo "       Install Android SDK Platform-Tools in Android Studio." >&2
    exit 1
fi
export PATH="$(dirname "$ADB_BIN"):$PATH"

echo "==> Checking ADB devices"
ADB_DEVICES="$("$ADB_BIN" devices -l | tr -d '\r')"
printf '%s\n' "$ADB_DEVICES"

AUTHORIZED_COUNT="$(printf '%s\n' "$ADB_DEVICES" | awk 'NR > 1 && $2 == "device" { count++ } END { print count + 0 }')"
UNAUTHORIZED_COUNT="$(printf '%s\n' "$ADB_DEVICES" | awk 'NR > 1 && $2 == "unauthorized" { count++ } END { print count + 0 }')"
OFFLINE_COUNT="$(printf '%s\n' "$ADB_DEVICES" | awk 'NR > 1 && $2 == "offline" { count++ } END { print count + 0 }')"

if [[ -n "${ANDROID_SERIAL:-}" ]]; then
    SELECTED_STATE="$(printf '%s\n' "$ADB_DEVICES" | awk -v serial="$ANDROID_SERIAL" 'NR > 1 && $1 == serial { print $2; found = 1 } END { if (!found) exit 1 }')" || {
        cat >&2 <<EOF
[FAIL] ANDROID_SERIAL=$ANDROID_SERIAL is set, but adb does not list that serial.
       Run scripts/adb-usb-diagnose.sh, or unset ANDROID_SERIAL and rerun.
EOF
        scripts/adb-usb-diagnose.sh >&2 || true
        exit 4
    }

    if [[ "$SELECTED_STATE" != "device" ]]; then
        cat >&2 <<EOF
[FAIL] ANDROID_SERIAL=$ANDROID_SERIAL is visible, but its adb state is '$SELECTED_STATE'.
       Unlock the phone, approve USB debugging, or reconnect USB before rerunning.
EOF
        scripts/adb-usb-diagnose.sh >&2 || true
        exit 4
    fi
fi

if [[ "$AUTHORIZED_COUNT" -eq 0 ]]; then
    if [[ "$UNAUTHORIZED_COUNT" -gt 0 ]]; then
        cat >&2 <<'EOF'
[FAIL] A phone is connected but USB debugging is not authorized.
       Unlock the phone, approve the USB debugging prompt, then rerun this script.
       If no prompt appears, revoke USB debugging authorizations on the phone and reconnect USB.
EOF
    elif [[ "$OFFLINE_COUNT" -gt 0 ]]; then
        cat >&2 <<'EOF'
[FAIL] A phone is visible to ADB but is offline.
       Keep the phone unlocked, reconnect USB, then run adb kill-server and adb start-server if needed.
EOF
    else
        cat >&2 <<'EOF'
[FAIL] No authorized Android device is connected.
       Connect the phone over USB, enable Developer Options > USB debugging, and approve the prompt.
EOF
    fi
    scripts/adb-usb-diagnose.sh >&2 || true
    exit 2
fi

if [[ "$AUTHORIZED_COUNT" -gt 1 && -z "${ANDROID_SERIAL:-}" ]]; then
    cat >&2 <<EOF
[FAIL] Multiple authorized Android devices are connected.
       Set ANDROID_SERIAL=<serial> before rerunning, or disconnect extra devices.
EOF
    printf '%s\n' "$ADB_DEVICES" | awk 'NR > 1 && $2 == "device" { print "       " $1 }' >&2
    exit 3
fi

if [[ "$REAL_DISPLAY" -eq 1 ]]; then
    echo "==> Checking stale virtual displays"
    swift run --package-path MacHost phase0-spike --audit-displays --fail-on-stale-displays
else
    STALE_VIRTUAL_DISPLAY_COUNT="$(scripts/display-audit.sh --count)"
    if [[ "$STALE_VIRTUAL_DISPLAY_COUNT" -gt 0 ]]; then
        echo "[WARN] Found $STALE_VIRTUAL_DISPLAY_COUNT stale Android Monitor virtual display(s); synthetic runtime verification can continue."
        echo "       Log out or restart macOS before running --real-display or Start Display."
    fi
fi

if [[ "$SKIP_INSTALL" -eq 1 ]]; then
    echo "==> Skipping Android receiver install"
else
    echo "==> Preflighting Android receiver signature"
    set +e
    SIGNATURE_AUDIT_OUTPUT="$(scripts/audit-receiver-signature.sh --fail-on-mismatch 2>&1)"
    SIGNATURE_AUDIT_STATUS=$?
    set -e
    printf '%s\n' "$SIGNATURE_AUDIT_OUTPUT"
    if [[ "$SIGNATURE_AUDIT_STATUS" -eq 5 ]]; then
        cat >&2 <<'EOF'
[FAIL] The installed Android receiver is signed with a different certificate.
       adb install -r cannot replace it.

       To keep using the installed client:
         scripts/verify-device-runtime.sh --skip-install

       To replace it with this build:
         scripts/replace-android-receiver.sh --confirm-uninstall
EOF
        exit 5
    elif [[ "$SIGNATURE_AUDIT_STATUS" -eq 3 ]]; then
        echo "[INFO] Android receiver is not installed yet; proceeding with install."
    elif [[ "$SIGNATURE_AUDIT_STATUS" -ne 0 ]]; then
        echo "[WARN] Signature preflight could not complete; proceeding with install attempt."
    fi

    echo "==> Installing Android receiver"
    scripts/install-android-receiver.sh
fi

echo "==> Running phone stream test"
STREAM_ARGS=(
    scripts/phase0-stream-test.sh
    --width "$WIDTH"
    --height "$HEIGHT"
    --fps "$FPS"
    --bitrate-mbps "$BITRATE_MBPS"
    --duration "$DURATION"
)
if [[ "$REAL_DISPLAY" -ne 1 ]]; then
    STREAM_ARGS+=(--synthetic-only)
fi

"${STREAM_ARGS[@]}"

echo "[OK] Device runtime verification passed."

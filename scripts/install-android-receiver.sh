#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ (! -x "${JAVA_HOME:-}/bin/java") && -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]]; then
    export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
fi

configured_sdk_dir() {
    local file="$1"
    if [[ -f "$file" ]]; then
        sed -n 's/^sdk\.dir=//p' "$file" | tail -n 1
    fi
}

ROOT_SDK_DIR="$(configured_sdk_dir local.properties)"
RECEIVER_SDK_DIR="$(configured_sdk_dir AndroidReceiver/local.properties)"
SDK_DIR=""
for candidate in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$ROOT_SDK_DIR" "$RECEIVER_SDK_DIR" "$HOME/Library/Android/sdk"; do
    if [[ -n "$candidate" && -d "$candidate" ]]; then
        SDK_DIR="$candidate"
        break
    fi
done
if [[ -z "$SDK_DIR" ]]; then
    SDK_DIR="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
fi

if [[ ! -d "$ROOT_SDK_DIR" || ! -d "$RECEIVER_SDK_DIR" ]]; then
    scripts/setup-android-env.sh --sdk-dir "$SDK_DIR"
fi

INSTALL_LOG="$(mktemp "${TMPDIR:-/tmp}/android-monitor-install.XXXXXX.log")"
cleanup() {
    rm -f "$INSTALL_LOG"
}
trap cleanup EXIT

set +e
./gradlew runReceiverDebug --console=plain 2>&1 | tee "$INSTALL_LOG"
status=${PIPESTATUS[0]}
set -e

if [[ "$status" -ne 0 ]]; then
    if grep -q 'INSTALL_FAILED_USER_RESTRICTED' "$INSTALL_LOG"; then
        echo
        echo "==> Phone blocked USB install; staging APK for manual install"
        scripts/stage-apk.sh || true
    elif grep -q 'INSTALL_PARSE_FAILED_INCONSISTENT_CERTIFICATES' "$INSTALL_LOG"; then
        cat <<'EOF'

==> The installed Android receiver has a different signing certificate
    To keep using the existing app, run:
      scripts/verify-device-runtime.sh --skip-install

    To replace it with this build from Android Studio:
      1. Run "Uninstall Android Receiver"
      2. Run "Run Android Receiver" or "Verify Device Runtime"
EOF
        echo
        echo "==> Auditing receiver APK signatures"
        scripts/audit-receiver-signature.sh || true
    fi

    echo
    echo "==> Install failed; collecting ADB/USB diagnostics"
    scripts/adb-usb-diagnose.sh || true
fi

exit "$status"

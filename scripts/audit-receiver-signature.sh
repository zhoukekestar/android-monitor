#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
. "$ROOT_DIR/scripts/lib/adb-path.sh"

PACKAGE_NAME="com.androidmonitor.receiver"
APK_PATH="$ROOT_DIR/AndroidReceiver/app/build/outputs/apk/debug/android-receiver-debug.apk"
FAIL_ON_MISMATCH=0

if [[ (! -x "${JAVA_HOME:-}/bin/java") && -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]]; then
    export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
fi

usage() {
    cat <<'EOF'
audit-receiver-signature.sh

Compares the signing certificate of the current AndroidReceiver APK with the
AndroidReceiver package installed on the selected phone. This is read-only and
does not install, uninstall, or launch anything.

Options:
  --apk <path>      APK to compare. Default: AndroidReceiver debug APK.
  --package <name>  Android package name. Default: com.androidmonitor.receiver
  --fail-on-mismatch
                  Exit non-zero when certificates differ. Default: warn only.
  --help            Show this message.

Environment:
  ANDROID_SERIAL=<serial>  Required when multiple authorized devices are connected.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apk)
            if [[ $# -lt 2 ]]; then
                echo "[FAIL] --apk requires a path" >&2
                exit 2
            fi
            APK_PATH="$2"
            shift
            ;;
        --package)
            if [[ $# -lt 2 ]]; then
                echo "[FAIL] --package requires a value" >&2
                exit 2
            fi
            PACKAGE_NAME="$2"
            shift
            ;;
        --fail-on-mismatch)
            FAIL_ON_MISMATCH=1
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
    cat >&2 <<EOF
[FAIL] APK not found: $APK_PATH
       Build it first with:
       ./gradlew :android-receiver:assembleDebug --console=plain
EOF
    exit 1
fi

ADB_BIN="$(resolve_adb_bin)"
if [[ -z "$ADB_BIN" ]]; then
    echo "[FAIL] adb was not found from ANDROID_HOME, ANDROID_SDK_ROOT, ~/Library/Android/sdk, or PATH." >&2
    exit 1
fi

resolve_apksigner() {
    if command -v apksigner >/dev/null 2>&1; then
        command -v apksigner
        return 0
    fi

    local sdk_dir
    sdk_dir="$(cd "$(dirname "$ADB_BIN")/.." && pwd)"
    if [[ -d "$sdk_dir/build-tools" ]]; then
        find "$sdk_dir/build-tools" -type f -name apksigner -print | sort | tail -n 1
    fi
}

APKSIGNER_BIN="$(resolve_apksigner)"
if [[ -z "$APKSIGNER_BIN" || ! -x "$APKSIGNER_BIN" ]]; then
    echo "[FAIL] apksigner was not found. Install Android SDK Build-Tools in Android Studio." >&2
    exit 1
fi

cert_digest() {
    "$APKSIGNER_BIN" verify --print-certs "$1" | awk -F': ' '/certificate SHA-256 digest/ { print $NF; exit }'
}

cert_report() {
    "$APKSIGNER_BIN" verify --print-certs "$1" | sed -n \
        -e '/certificate DN/p' \
        -e '/certificate SHA-256 digest/p' \
        -e '/certificate SHA-1 digest/p'
}

echo "==> Checking authorized Android device"
require_single_authorized_adb_device "$ADB_BIN"

echo "==> Locating installed receiver package"
REMOTE_PATH="$("$ADB_BIN" shell pm path "$PACKAGE_NAME" 2>/dev/null | tr -d '\r' | sed -n 's/^package://p' | head -n 1)"
if [[ -z "$REMOTE_PATH" ]]; then
    echo "[FAIL] $PACKAGE_NAME is not installed on the selected phone." >&2
    exit 3
fi
echo "$REMOTE_PATH"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/android-monitor-signature-audit.XXXXXX")"
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

INSTALLED_APK="$TMP_DIR/installed.apk"
echo "==> Pulling installed APK read-only"
"$ADB_BIN" pull "$REMOTE_PATH" "$INSTALLED_APK" >/dev/null

echo "==> Current APK certificate"
cert_report "$APK_PATH"
CURRENT_DIGEST="$(cert_digest "$APK_PATH")"

echo "==> Installed APK certificate"
cert_report "$INSTALLED_APK"
INSTALLED_DIGEST="$(cert_digest "$INSTALLED_APK")"

if [[ -z "$CURRENT_DIGEST" || -z "$INSTALLED_DIGEST" ]]; then
    echo "[FAIL] Could not read certificate digest from one of the APKs." >&2
    exit 4
fi

if [[ "$CURRENT_DIGEST" == "$INSTALLED_DIGEST" ]]; then
    echo "[OK] Current and installed APK certificates match."
else
    cat <<EOF
[WARN] Current and installed APK certificates differ.
       adb install -r cannot replace the installed package.

Next:
  - To keep using the installed client, run:
    scripts/verify-device-runtime.sh --skip-install
  - To replace it with this build, run:
    scripts/replace-android-receiver.sh --confirm-uninstall
EOF
    if [[ "$FAIL_ON_MISMATCH" -eq 1 ]]; then
        exit 5
    fi
fi

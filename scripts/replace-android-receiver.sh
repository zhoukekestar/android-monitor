#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CONFIRM_UNINSTALL=0
DRY_RUN=0
AUDIT_RECEIVER_SIGNATURE_SCRIPT="${AUDIT_RECEIVER_SIGNATURE_SCRIPT:-scripts/audit-receiver-signature.sh}"
GRADLEW="${GRADLEW:-./gradlew}"
VERIFY_DEVICE_RUNTIME_SCRIPT="${VERIFY_DEVICE_RUNTIME_SCRIPT:-scripts/verify-device-runtime.sh}"

usage() {
    cat <<'EOF'
replace-android-receiver.sh

Explicitly replaces the Android receiver on the selected phone:
  1. Requires --confirm-uninstall.
  2. Uninstalls com.androidmonitor.receiver from the phone.
  3. Installs and launches the current debug APK.
  4. Runs the default phone-connected Display verification gate.

Use this only when adb install reports INSTALL_PARSE_FAILED_INCONSISTENT_CERTIFICATES
and you are ready to replace the existing working phone app.

Options:
  --confirm-uninstall   Required. Allows uninstalling the existing receiver.
  --dry-run             Print the replacement commands without running them.
  --help                Show this message.

Environment:
  ANDROID_SERIAL=<serial>  Required when multiple authorized devices are connected.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --confirm-uninstall)
            CONFIRM_UNINSTALL=1
            ;;
        --dry-run)
            DRY_RUN=1
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

if [[ "$CONFIRM_UNINSTALL" -ne 1 ]]; then
    cat >&2 <<'EOF'
[FAIL] Refusing to uninstall the existing Android receiver without explicit confirmation.
       Re-run with:
       scripts/replace-android-receiver.sh --confirm-uninstall
EOF
    exit 2
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
    cat <<EOF
[DRY-RUN] Would run:
  $AUDIT_RECEIVER_SIGNATURE_SCRIPT --fail-on-mismatch
  $GRADLEW uninstallReceiverDebug --console=plain
  $VERIFY_DEVICE_RUNTIME_SCRIPT
EOF
    exit 0
fi

if [[ (! -x "${JAVA_HOME:-}/bin/java") && -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]]; then
    export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
fi

echo "==> Confirming receiver signature mismatch"
set +e
"$AUDIT_RECEIVER_SIGNATURE_SCRIPT" --fail-on-mismatch
signature_status=$?
set -e
case "$signature_status" in
    5)
        echo "[OK] Signature mismatch confirmed; replacement is required for this build."
        ;;
    0)
        cat >&2 <<'EOF'
[FAIL] Installed and current receiver signatures match. Refusing to uninstall.
       Use scripts/verify-device-runtime.sh instead.
EOF
        exit 6
        ;;
    3)
        echo "[INFO] Receiver is not currently installed; skipping uninstall."
        ;;
    *)
        cat >&2 <<EOF
[FAIL] Signature audit failed with status $signature_status. Refusing to uninstall.
EOF
        exit "$signature_status"
        ;;
esac

echo "==> Uninstalling existing Android receiver"
if [[ "$signature_status" -eq 5 ]]; then
    "$GRADLEW" uninstallReceiverDebug --console=plain
fi

echo "==> Installing and verifying current Android receiver"
"$VERIFY_DEVICE_RUNTIME_SCRIPT"

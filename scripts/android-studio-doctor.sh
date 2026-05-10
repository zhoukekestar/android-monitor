#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

REPAIR_LOCAL_PROPERTIES=0

usage() {
    cat <<'EOF'
android-studio-doctor.sh

Runs Android Studio, Gradle, ADB, signature, and display diagnostics. By
default this is read-only. Pass --repair-local-properties to rewrite local SDK
configuration with scripts/setup-android-env.sh.

Options:
  --repair-local-properties  Rewrite root and AndroidReceiver local.properties.
  --help                     Show this message.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repair-local-properties)
            REPAIR_LOCAL_PROPERTIES=1
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

run_section() {
    local title="$1"
    shift

    echo
    echo "==> $title"
    set +e
    "$@"
    local status=$?
    set -e
    if [[ "$status" -eq 0 ]]; then
        echo "[OK] $title"
    else
        echo "[WARN] $title exited with status $status"
    fi
}

echo "Android Monitor Android Studio Doctor"
echo "Root: $ROOT_DIR"

echo
echo "==> Java"
if [[ -x "${JAVA_HOME:-}/bin/java" ]]; then
    echo "JAVA_HOME=$JAVA_HOME"
    "$JAVA_HOME/bin/java" -version 2>&1 | sed -n '1,3p'
else
    echo "[WARN] JAVA_HOME is empty or invalid: ${JAVA_HOME:-<unset>}"
    echo "       Android Studio JBR is recommended for command-line Gradle."
fi

echo
echo "==> Android SDK local.properties"
if [[ -f local.properties ]]; then
    sed -n 's/^sdk\.dir=/root sdk.dir=/p' local.properties
else
    echo "[WARN] root local.properties is missing. Run scripts/setup-android-env.sh"
fi
if [[ -f AndroidReceiver/local.properties ]]; then
    sed -n 's/^sdk\.dir=/AndroidReceiver sdk.dir=/p' AndroidReceiver/local.properties
else
    echo "[WARN] AndroidReceiver/local.properties is missing. Run scripts/setup-android-env.sh"
fi

if [[ "$REPAIR_LOCAL_PROPERTIES" -eq 1 ]]; then
    run_section "Repair Android Studio local SDK config" scripts/setup-android-env.sh
else
    echo "[INFO] Doctor is read-only. Pass --repair-local-properties to rewrite SDK config."
fi

run_section "Android monitor Gradle tasks" env JAVA_HOME="$JAVA_HOME" ./gradlew tasks --group "android monitor" --console=plain
run_section "ADB and USB diagnostics" scripts/adb-usb-diagnose.sh
run_section "Receiver signature audit" scripts/audit-receiver-signature.sh
run_section "Display cleanup audit" scripts/display-audit.sh

cat <<'EOF'

Next actions:
  - If ADB is unauthorized: unlock the phone and approve USB debugging.
  - If signatures differ: use Verify Installed Device Runtime, or run Replace Android Receiver Dry Run before replacing the app.
  - If stale displays are reported: log out or restart macOS before starting Display mode.
EOF

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

LOG_DIR="${TMPDIR:-/tmp}/android-monitor"
LOG_FILE="$LOG_DIR/build.log"
APK_PATH="AndroidReceiver/app/build/outputs/apk/debug/android-receiver-debug.apk"
mkdir -p "$LOG_DIR"

if [[ (! -x "${JAVA_HOME:-}/bin/java") && -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]]; then
    export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
fi

if ! {
    scripts/setup-android-env.sh
    ./gradlew :android-receiver:assembleDebug --console=plain
} >"$LOG_FILE" 2>&1; then
    echo "[FAIL] Build failed."
    echo "Log: $LOG_FILE"
    echo
    tail -n 80 "$LOG_FILE"
    exit 1
fi

cat <<EOF
[OK] Build complete.
APK:
  $APK_PATH
Log:
  $LOG_FILE
EOF

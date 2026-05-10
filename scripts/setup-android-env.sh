#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

EXPLICIT_SDK_DIR=0
SDK_DIR=""
if [[ $# -gt 0 ]]; then
    case "$1" in
        --sdk-dir)
            if [[ $# -lt 2 ]]; then
                echo "[FAIL] --sdk-dir requires a path." >&2
                exit 2
            fi
            SDK_DIR="$2"
            EXPLICIT_SDK_DIR=1
            ;;
        --help|-h)
            cat <<'EOF'
setup-android-env.sh

Writes local Android SDK configuration for both supported Android Studio entry
points:
  - repository root
  - AndroidReceiver/ standalone project

Usage:
  scripts/setup-android-env.sh
  scripts/setup-android-env.sh --sdk-dir /path/to/Android/sdk
EOF
            exit 0
            ;;
        *)
            echo "[FAIL] Unknown option: $1" >&2
            exit 2
            ;;
    esac
fi

if [[ "$EXPLICIT_SDK_DIR" -eq 0 ]]; then
    for candidate in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Library/Android/sdk"; do
        if [[ -n "$candidate" && -d "$candidate" ]]; then
            SDK_DIR="$candidate"
            break
        fi
    done

    if [[ -z "$SDK_DIR" ]]; then
        SDK_DIR="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
    fi
fi

if [[ ! -d "$SDK_DIR" ]]; then
    cat >&2 <<EOF
[FAIL] Android SDK directory does not exist: $SDK_DIR
       Install Android Studio/SDK, or rerun with:
       scripts/setup-android-env.sh --sdk-dir /path/to/Android/sdk
EOF
    exit 1
fi

if [[ ! -x "$SDK_DIR/platform-tools/adb" ]]; then
    cat >&2 <<EOF
[WARN] adb was not found at:
       $SDK_DIR/platform-tools/adb
       Install Android SDK Platform-Tools in Android Studio.
EOF
fi

printf 'sdk.dir=%s\n' "$SDK_DIR" > local.properties
printf 'sdk.dir=%s\n' "$SDK_DIR" > AndroidReceiver/local.properties

echo "[OK] Wrote local.properties files for Android Studio."
echo "     SDK: $SDK_DIR"

if [[ (! -x "${JAVA_HOME:-}/bin/java") && -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]]; then
    echo "[INFO] Current JAVA_HOME is empty or invalid."
    echo "       For command-line Gradle, use Android Studio JBR:"
    echo '       export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"'
fi

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAC_DIR="$ROOT_DIR/MacHost"
APP_DIR="$MAC_DIR/build/Android Monitor Host.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
APK_PATH="$ROOT_DIR/AndroidReceiver/app/build/outputs/apk/debug/android-receiver-debug.apk"
JAVA_HOME_DEFAULT="/Applications/Android Studio.app/Contents/jbr/Contents/Home"

echo "==> Building AndroidReceiver debug APK"
if [[ -x "$JAVA_HOME_DEFAULT/bin/java" ]]; then
    (
        cd "$ROOT_DIR"
        JAVA_HOME="$JAVA_HOME_DEFAULT" ./gradlew :android-receiver:assembleDebug
    )
elif [[ ! -s "$APK_PATH" ]]; then
    echo "[FAIL] Android Studio JBR was not found and no existing APK is available: $APK_PATH" >&2
    exit 1
else
    echo "[WARN] Android Studio JBR was not found; reusing existing APK: $APK_PATH"
fi

if [[ ! -s "$APK_PATH" ]]; then
    echo "[FAIL] AndroidReceiver APK was not built: $APK_PATH" >&2
    exit 1
fi

echo "==> Building MacHost release products"
(
    cd "$MAC_DIR"
    swift build -c release --product phase0-spike
    swift build -c release --product android-monitor-host
    swift build -c release --product status-panel-server
)

echo "==> Creating app bundle"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$MAC_DIR/.build/release/android-monitor-host" "$MACOS_DIR/Android Monitor Host"
cp "$MAC_DIR/.build/release/phase0-spike" "$MACOS_DIR/phase0-spike"
cp "$MAC_DIR/.build/release/status-panel-server" "$MACOS_DIR/status-panel-server"
cp "$APK_PATH" "$RESOURCES_DIR/android-receiver-debug.apk"
chmod +x "$MACOS_DIR/Android Monitor Host" "$MACOS_DIR/phase0-spike" "$MACOS_DIR/status-panel-server"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Android Monitor Host</string>
    <key>CFBundleIdentifier</key>
    <string>local.android-monitor.host</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Android Monitor Host</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

if [[ -n "${ANDROID_MONITOR_CODE_SIGN_IDENTITY:-}" ]]; then
    echo "==> Signing app bundle with identity: $ANDROID_MONITOR_CODE_SIGN_IDENTITY"
    codesign --force --timestamp=none --sign "$ANDROID_MONITOR_CODE_SIGN_IDENTITY" "$MACOS_DIR/phase0-spike"
    codesign --force --timestamp=none --sign "$ANDROID_MONITOR_CODE_SIGN_IDENTITY" "$MACOS_DIR/status-panel-server"
    codesign --force --timestamp=none --sign "$ANDROID_MONITOR_CODE_SIGN_IDENTITY" "$MACOS_DIR/Android Monitor Host"
    codesign --force --timestamp=none --sign "$ANDROID_MONITOR_CODE_SIGN_IDENTITY" "$APP_DIR"
elif command -v codesign >/dev/null 2>&1; then
    echo "==> Applying ad-hoc signature"
    codesign --force --deep --sign - "$APP_DIR" || echo "[WARN] Ad-hoc signing failed; app bundle was still created."
fi

echo "[OK] App bundle: $APP_DIR"

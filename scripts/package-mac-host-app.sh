#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAC_DIR="$ROOT_DIR/MacHost"
APP_DIR="$MAC_DIR/build/Android Monitor Host.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

echo "==> Building MacHost release products"
(
    cd "$MAC_DIR"
    swift build -c release --product phase0-spike
    swift build -c release --product android-monitor-host
    swift build -c release --product status-panel-server
)

echo "==> Creating app bundle"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp "$MAC_DIR/.build/release/android-monitor-host" "$MACOS_DIR/Android Monitor Host"
cp "$MAC_DIR/.build/release/phase0-spike" "$MACOS_DIR/phase0-spike"
cp "$MAC_DIR/.build/release/status-panel-server" "$MACOS_DIR/status-panel-server"
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

echo "[OK] App bundle: $APP_DIR"

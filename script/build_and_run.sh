#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
APP_NAME="BOMInventory"
BUNDLE_ID="com.local.BOMInventory"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_MACOS="$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_MACOS" "$APP_BUNDLE/Contents/Resources"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$BUILD_BINARY" "$APP_MACOS/$APP_NAME"
cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>BOM Inventory</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSBluetoothAlwaysUsageDescription</key><string>Connect to your Niimbot B1 to print component labels over Bluetooth.</string>
<key>NSCameraUsageDescription</key><string>Scan component barcodes and QR codes to search your inventory.</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Refresh Finder and Launch Services after changing bundle resources.
/usr/bin/touch "$APP_BUNDLE"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_BUNDLE"
case "$MODE" in
run) /usr/bin/open -n "$APP_BUNDLE" ;;
--debug) lldb -- "$APP_MACOS/$APP_NAME" ;;
--logs) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
--telemetry) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\"" ;;
--verify) /usr/bin/open -n "$APP_BUNDLE"; sleep 1; pgrep -x "$APP_NAME" >/dev/null ;;
*) echo "usage: $0 [--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac

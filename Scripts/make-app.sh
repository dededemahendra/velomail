#!/bin/bash
# Assembles VeloMail.app from the SwiftPM executable.
#
# A bare SwiftPM binary is not a macOS app: without a bundle and Info.plist it
# cannot become a foreground application, own a menu bar, or host
# ASWebAuthenticationSession. This wraps it in the minimum real bundle. It is a
# local development build -- not signed, not notarised.
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/VeloMail.app"

swift build -c "$CONFIG" --product VeloMail
BIN="$(swift build -c "$CONFIG" --product VeloMail --show-bin-path)/VeloMail"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/VeloMail"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Velo Mail</string>
    <key>CFBundleDisplayName</key><string>Velo Mail</string>
    <key>CFBundleExecutable</key><string>VeloMail</string>
    <key>CFBundleIdentifier</key><string>co.sistercreatives.velomail</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <!-- Regular, not accessory: it needs a Dock icon and a menu bar. -->
    <key>LSUIElement</key><false/>
</dict>
</plist>
PLIST

echo "built $APP"

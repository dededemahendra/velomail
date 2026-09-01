#!/bin/bash
# Assembles VeloMail.app from the SwiftPM executable.
#
# A bare SwiftPM binary is not a macOS app: without a bundle and Info.plist it
# cannot become a foreground application, own a menu bar, or host
# ASWebAuthenticationSession. This wraps it in the minimum real bundle. It is a
# local development build -- not signed, not notarised.
set -euo pipefail

# Release by default: a debug binary is three times the size and carries
# symbols nobody shipping needs. Pass "debug" for a build you intend to attach
# a debugger to.
CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/VeloMail.app"

swift build -c "$CONFIG" --product VeloMail
BIN="$(swift build -c "$CONFIG" --product VeloMail --show-bin-path)/VeloMail"

# The icon is drawn, not stored: Sources/VeloIcon renders every representation
# macOS asks for. Built separately and never linked into the app.
swift build -c "$CONFIG" --product velo-icon
ICON_BIN="$(swift build -c "$CONFIG" --product velo-icon --show-bin-path)/velo-icon"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/VeloMail"

# Stripping local symbols and debug entries halves it again. Kept out of the
# debug path, where those symbols are the entire point.
#
# Re-signing afterwards is not optional: stripping rewrites the binary and
# invalidates the ad-hoc signature the toolchain applied, and on Apple Silicon
# the kernel then kills the process outright with
# "SIGKILL (Code Signature Invalid)" -- which presents as an app that launches
# and shows no window.
if [ "$CONFIG" = "release" ]; then
    strip -rSTx "$APP/Contents/MacOS/VeloMail" 2>/dev/null || true
fi
# Icon before signing, along with the Info.plist below: a signature covers the
# bundle's resources, so anything added afterwards is outside it. These used to
# be written after `codesign` for the plist, which left it unsigned.
ICON_TMP="$(mktemp -d)"
# On EXIT rather than inline: `set -e` means a failed render or iconutil aborts
# the script on the spot, and an inline cleanup line would never be reached.
trap 'rm -rf "$ICON_TMP"' EXIT
"$ICON_BIN" "$ICON_TMP/AppIcon.iconset" >/dev/null
iconutil -c icns "$ICON_TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Velo Mail</string>
    <key>CFBundleDisplayName</key><string>Velo Mail</string>
    <key>CFBundleExecutable</key><string>VeloMail</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
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

codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true
codesign --verify --deep "$APP" 2>/dev/null || echo "warning: bundle signature did not verify"

printf "built %s (%s, %s)\n" "$APP" "$CONFIG" \
    "$(du -h "$APP/Contents/MacOS/VeloMail" | cut -f1)"

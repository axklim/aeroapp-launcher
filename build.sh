#!/bin/sh
# Builds AeroAppLauncher.app into the given directory (default ~/Applications).
#
# The bundle is signed ad-hoc, which needs no developer account. Unlike aerotab,
# nothing here fails quietly when the code hash changes: the launcher asks for no
# Accessibility permission. The one grant it can hold — Automation, for
# `applescript` new-window triggers — is simply prompted for again after a rebuild.
set -eu

APP_NAME="AeroAppLauncher"
BUNDLE_ID="com.axklim.aeroapp-launcher"
VERSION="${AEROAPP_LAUNCHER_VERSION:-0.1.0}"

SRC_DIR=$(cd "$(dirname "$0")" && pwd)
INSTALL_DIR="${1:-$HOME/Applications}"
APP_DIR="$INSTALL_DIR/$APP_NAME.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"

# The version is compiled in rather than read from Info.plist at runtime: invoked
# through the bin/ symlink, the binary does not know which bundle it came from.
GEN_DIR=$(mktemp -d)
trap 'rm -rf "$GEN_DIR"' EXIT
printf 'let appVersion = "%s"\n' "$VERSION" > "$GEN_DIR/Version.swift"

swiftc -O \
    -o "$APP_DIR/Contents/MacOS/$APP_NAME" \
    "$SRC_DIR"/Sources/Core/*.swift \
    "$SRC_DIR"/Sources/App/*.swift \
    "$GEN_DIR/Version.swift"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Opens a new window of the app you summon, when it already has windows on another workspace.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP_DIR"

echo "Built $APP_DIR"

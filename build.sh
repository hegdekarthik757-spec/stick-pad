#!/bin/bash
# Builds Stick Pad and packages it as a double-clickable .app bundle.
#   ./build.sh          build into ./build/Stick Pad.app
#   ./build.sh --run    build, then launch it
#   ./build.sh --install  build, then copy into /Applications
#   ./build.sh --test   run the test suite only
set -euo pipefail

cd "$(dirname "$0")"

if [[ "${1:-}" == "--test" ]]; then
    exec swift run StickPadTests
fi

APP_NAME="Stick Pad"
EXECUTABLE="StickPad"
BUNDLE_ID="com.stickpad.app"
VERSION="1.0"
OUT="build"
APP="$OUT/$APP_NAME.app"

echo "==> Compiling ($EXECUTABLE, release)"
swift build -c release --product StickPad
BIN="$(swift build -c release --show-bin-path)/$EXECUTABLE"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$EXECUTABLE"

echo "==> Rendering app icon"
ICONSET="$OUT/AppIcon.iconset"
rm -rf "$ICONSET"
swift Tools/makeicon.swift "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$EXECUTABLE</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
    <key>NSHumanReadableCopyright</key><string>Your notes, encrypted on this Mac.</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || \
    echo "    (ad-hoc signing skipped — the app still runs)"

if [[ "${1:-}" == "--install" ]]; then
    echo "==> Installing to /Applications"
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/$APP_NAME.app"
    APP="/Applications/$APP_NAME.app"
fi

echo "==> Built: $APP"

if [[ "${1:-}" == "--run" || "${1:-}" == "--install" ]]; then
    echo "==> Launching"
    open "$APP"
fi

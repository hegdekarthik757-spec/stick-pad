#!/bin/bash
# Builds Stick Pad and packages it as a double-clickable .app bundle.
#   ./build.sh          build into ./build/Stick Pad.app
#   ./build.sh --run    build, then launch it
#   ./build.sh --install  build, then copy into /Applications
#   ./build.sh --test   run the test suite only
#   ./build.sh --dmg    build, then package a drag-to-install disk image
#   ./build.sh --pkg    build, then package an installer .pkg
#   ./build.sh --dist   build both the .dmg and the .pkg
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

# Universal, so the app runs on both Apple silicon and Intel Macs. Building
# only for the host would leave an Intel Mac unable to launch it at all.
ARCHS=(--arch arm64 --arch x86_64)

echo "==> Compiling ($EXECUTABLE, release, universal)"
swift build -c release --product StickPad "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/$EXECUTABLE"

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

# Clears quarantine and similar attributes picked up when sources were
# downloaded. (com.apple.provenance is system-managed and stays put; it rides
# along in the .pkg payload as an AppleDouble entry, which is normal — every
# installed Mac app carries it.)
xattr -cr "$APP" 2>/dev/null || true

echo "==> Verifying architectures"
lipo -info "$APP/Contents/MacOS/$EXECUTABLE"

echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || \
    echo "    (ad-hoc signing skipped — the app still runs)"

package_dmg() {
    local staging="$OUT/dmg"
    local dmg="$OUT/$APP_NAME $VERSION.dmg"
    echo "==> Packaging disk image"
    rm -rf "$staging" "$dmg"
    mkdir -p "$staging"
    cp -R "$APP" "$staging/"
    # The Applications symlink is what makes it a drag-to-install window.
    ln -s /Applications "$staging/Applications"
    hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$staging" \
        -ov -format UDZO "$dmg"
    rm -rf "$staging"
    echo "    $dmg"
}

package_pkg() {
    local pkg="$OUT/$APP_NAME $VERSION.pkg"
    echo "==> Packaging installer"
    rm -f "$pkg"
    productbuild --component "$APP" /Applications \
        --identifier "$BUNDLE_ID.pkg" --version "$VERSION" "$pkg" >/dev/null
    echo "    $pkg"
}

case "${1:-}" in
    --dmg)  package_dmg ;;
    --pkg)  package_pkg ;;
    --dist) package_dmg; package_pkg ;;
esac

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

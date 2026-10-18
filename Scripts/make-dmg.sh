#!/bin/zsh
# Builds a signed Release of Orbit and packs it into build/Orbit-<version>.dmg.
# Usage: Scripts/make-dmg.sh (from the repository root; `make dmg` runs it)
#
# The app is signed with the Apple Development certificate of the team in Config/Local.xcconfig.
# It isn't notarized, so on first launch users approve it in System Settings → Privacy & Security.

set -euo pipefail

DERIVED=build/Release/DerivedData
STAGING=build/Release/dmg
APP_NAME=Orbit.app

xcodebuild -project Orbit.xcodeproj -scheme Orbit -configuration Release \
    -derivedDataPath "$DERIVED" -destination 'generic/platform=macOS' \
    -allowProvisioningUpdates -quiet build

APP="$DERIVED/Build/Products/Release/$APP_NAME"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="build/Orbit-$VERSION.dmg"

codesign --verify --deep --strict "$APP"
for bundle in "$APP" "$APP/Contents/PlugIns/OrbitFinderExtension.appex"; do
    if codesign -d --entitlements - "$bundle" 2>/dev/null | grep -q get-task-allow; then
        echo "error: $bundle is signed with get-task-allow" >&2
        exit 1
    fi
done

rm -rf "$STAGING"
mkdir -p "$STAGING"
# ditto keeps the code signature intact (extended attributes, symlinks).
ditto "$APP" "$STAGING/$APP_NAME"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "Orbit $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov -quiet "$DMG"

# Launch Services registered the Release build and its staging copy: their extension would take over
# the one of the Debug build (same bundle ID), and the Debug app would report the extension as turned off.
# A copy has to be unregistered while it still exists, or its record stays behind.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
for copy in "$APP" "$STAGING/$APP_NAME"; do
    pluginkit -r "$PWD/$copy/Contents/PlugIns/OrbitFinderExtension.appex" 2>/dev/null || true
    "$LSREGISTER" -u "$PWD/$copy" 2>/dev/null || true
done
rm -rf "$STAGING"

echo "Created $DMG"

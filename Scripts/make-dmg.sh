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
rm -rf "$STAGING"

echo "Created $DMG"

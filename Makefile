DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

PROJECT  := Orbit.xcodeproj
SCHEME   := Orbit
DERIVED  := build/DerivedData
APP      := $(DERIVED)/Build/Products/Debug/Orbit.app
XCODEBUILD_BASE := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination 'platform=macOS' -quiet -allowProvisioningUpdates
XCODEBUILD := $(XCODEBUILD_BASE) -derivedDataPath $(DERIVED)

.PHONY: generate build check test run reload logs extension dmg clean

generate:
	xcodegen generate --quiet

build: generate
	$(XCODEBUILD) build

# Compile-only check that doesn't need a signing team. Builds into its own folder:
# unsigned products over the Debug build break its signature and Finder drops the extension.
check: generate
	$(XCODEBUILD_BASE) -derivedDataPath build/CheckDerivedData CODE_SIGNING_ALLOWED=NO build

test:
	swift test --package-path Packages/OrbitKit

run: build
	open $(APP)

# Load a freshly built extension: Finder doesn't relaunch a killed extension until Finder itself restarts.
reload:
	-killall OrbitFinderExtension
	killall Finder

logs:
	log stream --level debug --predicate 'subsystem BEGINSWITH "dev.orbit"'

extension:
	pluginkit -m -v -i dev.orbit.mac.FinderExtension

# Signed Release build packed into build/Orbit-<version>.dmg.
dmg: generate
	Scripts/make-dmg.sh

clean:
	rm -rf build

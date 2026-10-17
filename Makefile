DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

PROJECT  := Orbit.xcodeproj
SCHEME   := Orbit
DERIVED  := build/DerivedData
APP      := $(DERIVED)/Build/Products/Debug/Orbit.app
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -derivedDataPath $(DERIVED) -destination 'platform=macOS' -quiet -allowProvisioningUpdates

.PHONY: generate build check test run reload logs extension clean

generate:
	xcodegen generate --quiet

build: generate
	$(XCODEBUILD) build

# Compile-only check that doesn't need a signing team.
check: generate
	$(XCODEBUILD) CODE_SIGNING_ALLOWED=NO build

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

clean:
	rm -rf build

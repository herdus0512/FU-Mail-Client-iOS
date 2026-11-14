# Build from the terminal with Xcode. Only this Makefile points at Xcode (DEVELOPER_DIR): the Mac
# app keeps building with the Command Line Tools, and xcode-select is left alone.
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

# Your Apple IDs, kept out of the repository: copy local.mk.example to local.mk and fill it in.
-include local.mk

PROJECT := FUMail.xcodeproj
SCHEME := FUMail
BUNDLE_ID := com.h3rdus.fumail
DERIVED := build/DerivedData
ARCHIVE := build/FUMail.xcarchive
SIM ?= iPhone 17
# Each upload needs a higher build number: minutes since 1970, so it always goes up.
BUILD_NUMBER := $(or $(BUILD_NUMBER),$(shell echo $$(( $$(date +%s) / 60 ))))

.PHONY: all test build run sim-ipad archive testflight check-ids clean

all: test build

# The core: JSON, rules, state and client, against a pretend Mac (no simulator needed).
test:
	cd FUMailKit && swift test

# The app for the simulator (no signing needed).
build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'generic/platform=iOS Simulator' \
		-derivedDataPath $(DERIVED) build | grep -E "error|warning:|BUILD" ; exit $${PIPESTATUS[0]}

# Builds, then opens the app in the simulator (make run SIM="iPad Air 11-inch (M4)" for an iPad).
run: build
	open -a Simulator
	xcrun simctl boot "$(SIM)" 2>/dev/null || true
	xcrun simctl bootstatus "$(SIM)" -b >/dev/null
	xcrun simctl install "$(SIM)" $(DERIVED)/Build/Products/Debug-iphonesimulator/FUMail.app
	xcrun simctl launch "$(SIM)" $(BUNDLE_ID)

sim-ipad:
	$(MAKE) run SIM="iPad Air 11-inch (M4)"

check-ids:
	@test -n "$(TEAM_ID)" || { echo "Fill in TEAM_ID in local.mk first (cp local.mk.example local.mk)."; exit 1; }

# A release build for the App Store, left unsigned: signing for development would need a registered
# device, and TestFlight doesn't. `testflight` signs it for distribution.
archive: check-ids
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -destination 'generic/platform=iOS' \
		-derivedDataPath $(DERIVED) -archivePath $(ARCHIVE) \
		DEVELOPMENT_TEAM=$(TEAM_ID) CODE_SIGNING_ALLOWED=NO CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) archive \
		| grep -E "error|warning:|ARCHIVE" ; exit $${PIPESTATUS[0]}

# Tests, archives, signs and uploads to App Store Connect. Signing and uploading go through the Apple ID
# signed in to Xcode (Settings → Accounts; Xcode needn't be open): Apple lets the Account Holder make
# the distribution certificate, which an App Manager API key may not. The build shows in TestFlight after Apple
# processes it (5–15 minutes), and goes to the internal group by itself.
testflight: test archive
	@mkdir -p build
	@printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0"><dict>' \
		'<key>method</key><string>app-store-connect</string>' \
		'<key>destination</key><string>upload</string>' \
		'<key>teamID</key><string>$(TEAM_ID)</string>' \
		'<key>signingStyle</key><string>automatic</string>' \
		'<key>uploadSymbols</key><true/>' \
		'<key>manageAppVersionAndBuildNumber</key><false/>' \
		'</dict></plist>' > build/ExportOptions.plist
	xcodebuild -exportArchive -archivePath $(ARCHIVE) -exportOptionsPlist build/ExportOptions.plist \
		-exportPath build/export -allowProvisioningUpdates 2>&1 | grep -vE "Progress|^\s*$$" ; exit $${PIPESTATUS[0]}
	@echo "Uploaded $$(cat VERSION) ($(BUILD_NUMBER)). It appears in TestFlight once Apple has processed it."

clean:
	rm -rf build FUMailKit/.build

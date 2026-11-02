export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer

BUILD_DIR := build
# Sign with the project's self-signed certificate when it's in the keychain, so the
# audio-capture permission survives rebuilds; otherwise fall back to ad-hoc signing.
SIGN_IDENTITY := $(shell security find-identity -p codesigning 2>/dev/null | grep -q "Sound Space Self-Signed" && echo "Sound Space Self-Signed" || echo "-")
XCODEBUILD := xcodebuild -project VolumeCustomizer.xcodeproj -configuration Debug -derivedDataPath $(BUILD_DIR) -quiet \
	CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)"
APP := $(BUILD_DIR)/Build/Products/Debug/VolumeCustomizer.app

.PHONY: project app open test release clean

project:
	xcodegen generate --quiet

app: project
	$(XCODEBUILD) -scheme VolumeCustomizer build

open: app
	-pkill -x VolumeCustomizer && sleep 1
	open $(APP)

test: project
	$(XCODEBUILD) -scheme VolumeCustomizer test

release:
	scripts/release.sh

clean:
	rm -rf $(BUILD_DIR) dist VolumeCustomizer.xcodeproj

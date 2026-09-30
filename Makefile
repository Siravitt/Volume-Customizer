export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer

BUILD_DIR := build
XCODEBUILD := xcodebuild -project SoundSpace.xcodeproj -configuration Debug -derivedDataPath $(BUILD_DIR) -quiet
APP := $(BUILD_DIR)/Build/Products/Debug/SoundSpace.app
SPIKE_APP := $(BUILD_DIR)/Build/Products/Debug/Spike.app

.PHONY: project app open test spike open-spike clean

project:
	xcodegen generate --quiet

app: project
	$(XCODEBUILD) -scheme SoundSpace build

open: app
	-pkill -x SoundSpace && sleep 1
	open $(APP)

test: project
	$(XCODEBUILD) -scheme SoundSpace test

spike: project
	$(XCODEBUILD) -scheme Spike build

open-spike: spike
	open $(SPIKE_APP)

clean:
	rm -rf $(BUILD_DIR) SoundSpace.xcodeproj

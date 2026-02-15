APP_NAME = FreeFlow
BUNDLE_ID = com.hackclub.freeflow
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
CODESIGN_IDENTITY ?= VoiceToText Dev
CONTENTS = $(APP_BUNDLE)/Contents
MACOS_DIR = $(CONTENTS)/MacOS

SOURCES = $(wildcard Sources/*.swift)
ARCH = $(shell uname -m)

.PHONY: all clean run

all: $(MACOS_DIR)/$(APP_NAME)

$(MACOS_DIR)/$(APP_NAME): $(SOURCES) Info.plist
	@mkdir -p $(MACOS_DIR)
	swiftc \
		-parse-as-library \
		-o $(MACOS_DIR)/$(APP_NAME) \
		-sdk $(shell xcrun --show-sdk-path) \
		-target $(ARCH)-apple-macosx13.0 \
		$(SOURCES)
	@cp Info.plist $(CONTENTS)/
	@codesign --force --sign "$(CODESIGN_IDENTITY)" --entitlements FreeFlow.entitlements $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE)"

clean:
	rm -rf $(BUILD_DIR)

run: all
	open $(APP_BUNDLE)

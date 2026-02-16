APP_NAME = FreeFlow
BUNDLE_ID = com.zachlatta.freeflow
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
CODESIGN_IDENTITY ?= FreeFlow Dev
CONTENTS = $(APP_BUNDLE)/Contents
MACOS_DIR = $(CONTENTS)/MacOS

SOURCES = $(wildcard Sources/*.swift)
RESOURCES = $(CONTENTS)/Resources
ARCH = $(shell uname -m)
ICON_SOURCE = Resources/AppIcon-Source.png
ICON_ICNS = Resources/AppIcon.icns

.PHONY: all clean run icon

all: $(MACOS_DIR)/$(APP_NAME)

$(MACOS_DIR)/$(APP_NAME): $(SOURCES) Info.plist $(ICON_ICNS)
	@mkdir -p $(MACOS_DIR) $(RESOURCES)
	swiftc \
		-parse-as-library \
		-o $(MACOS_DIR)/$(APP_NAME) \
		-sdk $(shell xcrun --show-sdk-path) \
		-target $(ARCH)-apple-macosx13.0 \
		$(SOURCES)
	@cp Info.plist $(CONTENTS)/
	@cp $(ICON_ICNS) $(RESOURCES)/
	@codesign --force --sign "$(CODESIGN_IDENTITY)" --entitlements FreeFlow.entitlements $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE)"

icon: $(ICON_ICNS)

$(ICON_ICNS): $(ICON_SOURCE)
	@mkdir -p $(BUILD_DIR)/AppIcon.iconset
	@sips -z 16 16 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_16x16.png > /dev/null
	@sips -z 32 32 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_16x16@2x.png > /dev/null
	@sips -z 32 32 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_32x32.png > /dev/null
	@sips -z 64 64 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_32x32@2x.png > /dev/null
	@sips -z 128 128 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_128x128.png > /dev/null
	@sips -z 256 256 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_128x128@2x.png > /dev/null
	@sips -z 256 256 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_256x256.png > /dev/null
	@sips -z 512 512 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_256x256@2x.png > /dev/null
	@sips -z 512 512 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_512x512.png > /dev/null
	@sips -z 1024 1024 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_512x512@2x.png > /dev/null
	@iconutil -c icns -o $@ $(BUILD_DIR)/AppIcon.iconset
	@rm -rf $(BUILD_DIR)/AppIcon.iconset
	@echo "Generated $@"

clean:
	rm -rf $(BUILD_DIR)

run: all
	open $(APP_BUNDLE)

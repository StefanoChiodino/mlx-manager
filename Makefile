APP_NAME     := MLXManager
BUNDLE_DIR   := build/$(APP_NAME).app
CONTENTS     := $(BUNDLE_DIR)/Contents
MACOS_DIR    := $(CONTENTS)/MacOS
RES_DIR      := $(CONTENTS)/Resources
BINARY       := .build/release/$(APP_NAME)App
INSTALL_PATH := /Applications/$(APP_NAME).app
LAUNCH_AGENT_ID   := com.stefano.mlx-manager
LAUNCH_AGENT_DST  := $(HOME)/Library/LaunchAgents/$(LAUNCH_AGENT_ID).plist

.PHONY: all build bundle sign install uninstall launch-agent remove-launch-agent clean

all: build bundle sign

build:
	swift build -c release

bundle: build
	mkdir -p $(MACOS_DIR) $(RES_DIR)
	cp $(BINARY) $(MACOS_DIR)/$(APP_NAME)
	cp Resources/Info.plist $(CONTENTS)/Info.plist
	iconutil -c icns Resources/AppIcon.iconset -o $(RES_DIR)/AppIcon.icns
	mkdir -p /Applications/MLXManager.app/Contents/Resources/
	cp $(RES_DIR)/AppIcon.icns /Applications/MLXManager.app/Contents/Resources/
	cp Sources/MLXManagerApp/presets.yaml $(RES_DIR)/presets.yaml
	cp Resources/LaunchAgent.plist $(RES_DIR)/LaunchAgent.plist

sign: bundle
	codesign --force --deep -s - $(BUNDLE_DIR)

install: bundle sign
	cp -r $(BUNDLE_DIR) $(INSTALL_PATH)

uninstall:
	rm -rf $(INSTALL_PATH)

launch-agent:
	cp Resources/LaunchAgent.plist $(LAUNCH_AGENT_DST)
	launchctl load $(LAUNCH_AGENT_DST)

remove-launch-agent:
	-launchctl unload $(LAUNCH_AGENT_DST) 2>/dev/null
	rm -f $(LAUNCH_AGENT_DST)

clean:
	rm -rf build/

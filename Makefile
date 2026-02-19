.PHONY: build run clean build-swift build-python install uninstall

APP_NAME := DictateApp
APP_BUNDLE := $(APP_NAME).app
APP_DIR := $(APP_BUNDLE)/Contents
INSTALL_DIR := /Applications

build: build-python build-swift

build-python:
	uv sync

build-swift:
	swift build -c release

run: build
	.build/release/$(APP_NAME)

run-debug: build-python
	swift build && .build/debug/$(APP_NAME)

$(APP_BUNDLE): build
	@echo "Creating $(APP_BUNDLE)..."
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_DIR)/MacOS
	mkdir -p $(APP_DIR)/Resources
	cp .build/release/$(APP_NAME) $(APP_DIR)/MacOS/$(APP_NAME)
	cp -a .venv $(APP_DIR)/Resources/venv
	cp $(APP_NAME).icns $(APP_DIR)/Resources/$(APP_NAME).icns
	@echo '<?xml version="1.0" encoding="UTF-8"?>' > $(APP_DIR)/Info.plist
	@echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> $(APP_DIR)/Info.plist
	@echo '<plist version="1.0">' >> $(APP_DIR)/Info.plist
	@echo '<dict>' >> $(APP_DIR)/Info.plist
	@echo '  <key>CFBundleExecutable</key>' >> $(APP_DIR)/Info.plist
	@echo '  <string>$(APP_NAME)</string>' >> $(APP_DIR)/Info.plist
	@echo '  <key>CFBundleIdentifier</key>' >> $(APP_DIR)/Info.plist
	@echo '  <string>com.dictate-app</string>' >> $(APP_DIR)/Info.plist
	@echo '  <key>CFBundleName</key>' >> $(APP_DIR)/Info.plist
	@echo '  <string>$(APP_NAME)</string>' >> $(APP_DIR)/Info.plist
	@echo '  <key>CFBundleIconFile</key>' >> $(APP_DIR)/Info.plist
	@echo '  <string>$(APP_NAME)</string>' >> $(APP_DIR)/Info.plist
	@echo '  <key>CFBundlePackageType</key>' >> $(APP_DIR)/Info.plist
	@echo '  <string>APPL</string>' >> $(APP_DIR)/Info.plist
	@echo '  <key>CFBundleVersion</key>' >> $(APP_DIR)/Info.plist
	@echo '  <string>1.0</string>' >> $(APP_DIR)/Info.plist
	@echo '  <key>LSUIElement</key>' >> $(APP_DIR)/Info.plist
	@echo '  <true/>' >> $(APP_DIR)/Info.plist
	@echo '  <key>NSMicrophoneUsageDescription</key>' >> $(APP_DIR)/Info.plist
	@echo '  <string>DictateApp needs microphone access to transcribe your speech.</string>' >> $(APP_DIR)/Info.plist
	@echo '</dict>' >> $(APP_DIR)/Info.plist
	@echo '</plist>' >> $(APP_DIR)/Info.plist
	@echo "$(APP_BUNDLE) created."

install: $(APP_BUNDLE)
	@echo "Installing to $(INSTALL_DIR)..."
	rm -rf $(INSTALL_DIR)/$(APP_BUNDLE)
	cp -a $(APP_BUNDLE) $(INSTALL_DIR)/$(APP_BUNDLE)
	rm -rf $(APP_BUNDLE)
	codesign -f -s - $(INSTALL_DIR)/$(APP_BUNDLE)
	@echo "Installed. Launch from Spotlight or $(INSTALL_DIR)/$(APP_BUNDLE)"
	@echo "Tip: right-click in Dock → Options → Open at Login"

uninstall:
	rm -rf $(INSTALL_DIR)/$(APP_BUNDLE)
	@echo "Uninstalled."

clean:
	swift package clean
	rm -rf .build $(APP_BUNDLE)

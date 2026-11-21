APP_NAME := MacChargingSpeed
SCHEME := MacChargingSpeed
BUILD_DIR := build
APP_PATH := $(BUILD_DIR)/Build/Products/Release/$(APP_NAME).app
DMG_PATH := $(BUILD_DIR)/$(APP_NAME).dmg

.PHONY: generate build install dmg clean open

generate:
	@command -v xcodegen >/dev/null 2>&1 || { echo "Installing xcodegen via Homebrew..."; brew install xcodegen; }
	xcodegen generate

build: generate
	xcodebuild -project $(APP_NAME).xcodeproj \
		-scheme $(SCHEME) \
		-configuration Release \
		-derivedDataPath $(BUILD_DIR) \
		CODE_SIGN_IDENTITY="-" \
		AD_HOC_CODE_SIGNING_ALLOWED=YES \
		build

install: build
	@echo "Installing $(APP_NAME).app to /Applications..."
	@pkill -x $(APP_NAME) 2>/dev/null || true
	@rm -rf "/Applications/$(APP_NAME).app"
	@cp -R "$(APP_PATH)" "/Applications/$(APP_NAME).app"
	@xattr -dr com.apple.quarantine "/Applications/$(APP_NAME).app" 2>/dev/null || true
	@open "/Applications/$(APP_NAME).app"
	@echo "Done! Add the desktop widget via Notification Center -> Edit Widgets -> MacChargingSpeed."

dmg: build
	@rm -rf "$(BUILD_DIR)/dmg-stage" "$(DMG_PATH)"
	@mkdir -p "$(BUILD_DIR)/dmg-stage"
	@cp -R "$(APP_PATH)" "$(BUILD_DIR)/dmg-stage/"
	@ln -s /Applications "$(BUILD_DIR)/dmg-stage/Applications"
	@hdiutil create -volname "$(APP_NAME)" -srcfolder "$(BUILD_DIR)/dmg-stage" -ov -format UDZO "$(DMG_PATH)"
	@echo "Created $(DMG_PATH)"

open: generate
	open $(APP_NAME).xcodeproj

clean:
	rm -rf $(BUILD_DIR) $(APP_NAME).xcodeproj

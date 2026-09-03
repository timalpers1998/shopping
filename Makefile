SIM ?= iPhone 17 Pro
BUNDLE = com.timalpers.shopping
DEST = platform=iOS Simulator,name=$(SIM)
XCB = xcodebuild -project Feed.xcodeproj -scheme Feed -configuration Debug -destination '$(DEST)' -derivedDataPath build -skipPackagePluginValidation -skipMacroValidation

.PHONY: generate build run test clean

generate:
	xcodegen generate

build: generate
	$(XCB) build 2>&1 | tail -30

run: build
	xcrun simctl boot "$(SIM)" 2>/dev/null || true
	open -a Simulator
	xcrun simctl install "$(SIM)" build/Build/Products/Debug-iphonesimulator/Feed.app
	xcrun simctl launch "$(SIM)" $(BUNDLE)

test: generate
	$(XCB) test 2>&1 | tail -40

clean:
	rm -rf build Feed.xcodeproj

.PHONY: setup test-ui test-unit lint

# Run after cloning to configure git hooks
setup:
	git config core.hooksPath .githooks
	@echo "Git hooks configured."

# Run UI tests locally (same as pre-push hook)
test-ui:
	xcodebuild test \
		-project AuralystApp.xcodeproj \
		-scheme AuralystApp \
		-destination "platform=iOS Simulator,name=iPhone 16 Pro" \
		-only-testing:AuralystAppUITests \
		-skipPackagePluginValidation \
		-quiet \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO \
		ENABLE_USER_SCRIPT_SANDBOXING=NO

# Run unit tests locally
test-unit:
	xcodebuild test \
		-project AuralystApp.xcodeproj \
		-scheme AuralystApp \
		-destination "platform=iOS Simulator,name=iPhone 16 Pro" \
		-only-testing:AuralystAppTests \
		-skipPackagePluginValidation \
		-quiet \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO \
		ENABLE_USER_SCRIPT_SANDBOXING=NO

# Run SwiftLint
lint:
	swiftlint

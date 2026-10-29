.PHONY: project build test

# Unsigned verification must not replace the signed app used by build_and_run.sh.
VERIFY_DERIVED_DATA := .build/VerificationDerivedData

project:
	xcodegen generate

build:
	xcodebuild -scheme ZoneBox -configuration Debug -destination 'platform=macOS' -derivedDataPath $(VERIFY_DERIVED_DATA) CODE_SIGNING_ALLOWED=NO build

test:
	@echo "xcodebuild $$(xcodebuild -version | tr '\n' ' ')"
	@echo "sdk $$(xcodebuild -showsdks | awk '/macOS SDKs/{getline; print}')"
	xcodebuild -scheme ZoneBox -configuration Debug -destination 'platform=macOS' -derivedDataPath $(VERIFY_DERIVED_DATA) CODE_SIGNING_ALLOWED=NO test
	bash script/run_update_check_restore_regression.sh
	@! grep -R --include='*.swift' -n 'import SwiftUI' ZoneBox

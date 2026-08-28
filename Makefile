.PHONY: project build test

project:
	xcodegen generate
	python3 script/patch_ax_scheme.py

build:
	xcodebuild -scheme ZoneBox -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build

test:
	xcodebuild -scheme ZoneBox -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO test
	@! grep -R --include='*.swift' -n 'import SwiftUI' ZoneBox

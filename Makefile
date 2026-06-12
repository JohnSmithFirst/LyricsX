# LyricsX Build Configuration
# For local builds, run: make build
# For CI, see .github/workflows/build.yml

SCHEME ?= LyricsX
CONFIGURATION ?= Release
DERIVED_DATA ?= DerivedData

.PHONY: all build clean archive

all: build

build:
	# Build MRProxyHelper dylib (for macOS 15.4+ MediaRemote access via python3)
	mkdir -p Carthage/Build/Mac
	clang -dynamiclib \
		-o "Carthage/Build/Mac/MRProxyHelper.dylib" \
		"LyricsX/Utility/mr_proxy_helper.m" \
		-framework Foundation -framework CoreFoundation \
		-current_version 1.0.0 \
		-compatibility_version 1.0.0 \
		-install_name "@rpath/MRProxyHelper.dylib"
	# Build main app
	xcodebuild build \
		-project LyricsX.xcodeproj \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-derivedDataPath $(DERIVED_DATA) \
		-destination "platform=macOS" \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO \
		DEVELOPMENT_TEAM=""

clean:
	rm -rf $(DERIVED_DATA)
	xcodebuild clean \
		-project LyricsX.xcodeproj \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION)

archive:
	xcodebuild archive \
		-project LyricsX.xcodeproj \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-archivePath LyricsX.xcarchive \
		-destination "platform=macOS" \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO \
		DEVELOPMENT_TEAM=""

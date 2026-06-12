# Pulse build entry points.
#
# This machine has Command Line Tools only (no Xcode). Two CLT 26.5 quirks
# are worked around here:
#   1. Stale PackageDescription private swiftinterfaces break manifest
#      compilation -> SWIFTPM_CUSTOM_LIBS_DIR points at a patched copy
#      (created by `make fix-toolchain`).
#   2. Testing.framework search/runtime paths aren't injected by SwiftPM
#      -> passed explicitly for `make test`.

CLT := /Library/Developer/CommandLineTools
FIX_DIR := $(HOME)/.local/swiftpm-fix
FW := $(CLT)/Library/Developer/Frameworks
TESTLIB := $(CLT)/Library/Developer/usr/lib

SWIFT := SWIFTPM_CUSTOM_LIBS_DIR=$(FIX_DIR) swift
TEST_FLAGS := -Xswiftc -F$(FW) -Xlinker -F$(FW) \
	-Xlinker -rpath -Xlinker $(FW) -Xlinker -rpath -Xlinker $(TESTLIB)

.PHONY: build test run release bundle clean fix-toolchain

build: fix-toolchain
	$(SWIFT) build

test: fix-toolchain
	$(SWIFT) test $(TEST_FLAGS)

run: fix-toolchain
	$(SWIFT) run Pulse

release: fix-toolchain
	$(SWIFT) build -c release

bundle: release
	scripts/bundle.sh

clean:
	swift package clean 2>/dev/null || rm -rf .build

# Copy ManifestAPI and drop the stale *.private.swiftinterface files.
fix-toolchain:
	@if [ ! -d "$(FIX_DIR)/ManifestAPI" ]; then \
		mkdir -p "$(FIX_DIR)"; \
		cp -R "$(CLT)/usr/lib/swift/pm/ManifestAPI" "$(FIX_DIR)/"; \
		rm -f "$(FIX_DIR)"/ManifestAPI/PackageDescription.swiftmodule/*.private.swiftinterface; \
		echo "Patched ManifestAPI installed at $(FIX_DIR)"; \
	fi

CRATE            := radroots-app-ffi
ROOT             := $(CURDIR)/RadrootsCore
OUTDIR           := $(ROOT)/target/xcframework

FRAMEWORK_DEST   := $(CURDIR)/RadrootsKit/Artifacts
GENERATED_SWIFT  := $(CURDIR)/RadrootsKit/Sources/RadrootsKit/Generated
CONFIG_PATH      := $(ROOT)/crates/ffi/uniffi.toml

LIB_DEV          := $(ROOT)/target/aarch64-apple-ios/release/libradroots_studio_app_ffi.a
LIB_SIM_ARM64    := $(ROOT)/target/aarch64-apple-ios-sim/release/libradroots_studio_app_ffi.a
HOST_DYLIB       := $(ROOT)/target/release/libradroots_studio_app_ffi.dylib

HEADERS_DIR      := $(OUTDIR)/headers

.PHONY: all clean build generate package bindings

all: clean build generate package bindings
	@echo "Done."
	@echo "   - XCFramework: $(FRAMEWORK_DEST)/RadrootsFFI.xcframework"
	@echo "   - Swift bindings: $(GENERATED_SWIFT)/*.swift"

clean:
	@echo "Cleaning output dirs..."
	rm -rf $(OUTDIR) $(FRAMEWORK_DEST) $(GENERATED_SWIFT)
	mkdir -p $(OUTDIR) $(FRAMEWORK_DEST) $(GENERATED_SWIFT)

build:
	@echo "Building $(CRATE) for iOS device + simulator..."
	cd $(ROOT) && cargo build -p $(CRATE) --release --target aarch64-apple-ios
	cd $(ROOT) && cargo build -p $(CRATE) --release --target aarch64-apple-ios-sim

	@echo "Building host cdylib for UniFFI (metadata)…"
	cd $(ROOT) && cargo build -p $(CRATE) --release

generate:
	@echo "Generating Swift bindings with UniFFI (host dylib)…"
	cd $(ROOT) && cargo run -p $(CRATE) --bin uniffi-bindgen -- \
		generate --library $(HOST_DYLIB) \
		--language swift \
		--out-dir $(OUTDIR)/generated \
		--config $(CONFIG_PATH)

	@echo "Preparing headers..."
	mkdir -p $(HEADERS_DIR)
	cp $(OUTDIR)/generated/RadrootsFFI.h $(HEADERS_DIR)/
	cp $(OUTDIR)/generated/RadrootsFFI.modulemap $(HEADERS_DIR)/module.modulemap

package:
	@echo "Packaging RadrootsFFI.xcframework..."
	xcodebuild -create-xcframework \
		-library $(LIB_DEV)       -headers $(HEADERS_DIR) \
		-library $(LIB_SIM_ARM64) -headers $(HEADERS_DIR) \
		-output $(FRAMEWORK_DEST)/RadrootsFFI.xcframework

bindings:
	@echo "Copying Swift bindings into RadrootsKit..."
	cp $(OUTDIR)/generated/*.swift $(GENERATED_SWIFT)/

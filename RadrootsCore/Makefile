CRATE             := radroots-app-ffi-swift
WRAPPER_ROOT      := $(CURDIR)
IOS_ROOT          := $(abspath $(WRAPPER_ROOT)/..)
CRATES_ROOT       := $(abspath $(IOS_ROOT)/../crates)
OUTDIR            := $(WRAPPER_ROOT)/target/xcframework

FRAMEWORK_DEST    := $(IOS_ROOT)/RadrootsKit/Artifacts
GENERATED_SWIFT   := $(IOS_ROOT)/RadrootsKit/Sources/RadrootsKit/Generated
CONFIG_PATH       := $(CRATES_ROOT)/app-ffi-swift/uniffi.toml

LIB_DEV           := $(WRAPPER_ROOT)/target/aarch64-apple-ios/release/libradroots_studio_app_ffi_swift.a
LIB_SIM_ARM64     := $(WRAPPER_ROOT)/target/aarch64-apple-ios-sim/release/libradroots_studio_app_ffi_swift.a
HOST_DYLIB        := $(WRAPPER_ROOT)/target/release/libradroots_studio_app_ffi_swift.dylib

HEADERS_DIR       := $(OUTDIR)/headers

.PHONY: all clean build generate package bindings

all: clean build generate package bindings
	@echo "done."
	@echo "  - xcframework: $(FRAMEWORK_DEST)/RadrootsFFI.xcframework"
	@echo "  - swift bindings: $(GENERATED_SWIFT)/*.swift"

clean:
	@echo "cleaning output dirs..."
	rm -rf $(OUTDIR) $(FRAMEWORK_DEST) $(GENERATED_SWIFT)
	mkdir -p $(OUTDIR) $(FRAMEWORK_DEST) $(GENERATED_SWIFT)

build:
	@echo "building $(CRATE) for ios device + simulator..."
	cd $(CRATES_ROOT) && CARGO_TARGET_DIR=$(WRAPPER_ROOT)/target cargo build -p $(CRATE) --release --target aarch64-apple-ios
	cd $(CRATES_ROOT) && CARGO_TARGET_DIR=$(WRAPPER_ROOT)/target cargo build -p $(CRATE) --release --target aarch64-apple-ios-sim

	@echo "building host cdylib for uniffi metadata..."
	cd $(CRATES_ROOT) && CARGO_TARGET_DIR=$(WRAPPER_ROOT)/target cargo build -p $(CRATE) --release

generate:
	@echo "generating swift bindings with uniffi..."
	cd $(CRATES_ROOT) && CARGO_TARGET_DIR=$(WRAPPER_ROOT)/target cargo run -p $(CRATE) --bin uniffi-bindgen -- \
		generate --library $(HOST_DYLIB) \
		--language swift \
		--out-dir $(OUTDIR)/generated \
		--config $(CONFIG_PATH)

	@echo "preparing headers..."
	mkdir -p $(HEADERS_DIR)
	cp $(OUTDIR)/generated/RadrootsFFI.h $(HEADERS_DIR)/
	cp $(OUTDIR)/generated/RadrootsFFI.modulemap $(HEADERS_DIR)/module.modulemap

package:
	@echo "packaging RadrootsFFI.xcframework..."
	xcodebuild -create-xcframework \
		-library $(LIB_DEV)       -headers $(HEADERS_DIR) \
		-library $(LIB_SIM_ARM64) -headers $(HEADERS_DIR) \
		-output $(FRAMEWORK_DEST)/RadrootsFFI.xcframework

bindings:
	@echo "copying swift bindings into RadrootsKit..."
	cp $(OUTDIR)/generated/*.swift $(GENERATED_SWIFT)/

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

-include source.lock
-include Config/ffi-build.env

SOURCE_MODE ?= git
RADROOTS_CRATES_GIT_URL ?= https://github.com/radrootslabs/crates.git
RADROOTS_CRATES_GIT_REV ?= 766c63c07ac7497d75a71aaab010fbc08ee934bc
RADROOTS_APP_FFI_CRATE_VERSION ?= 0.1.0
LOCAL_FFI_MANIFEST ?=

IOS_ROOT := $(abspath $(CURDIR)/..)
KIT_ROOT := $(IOS_ROOT)/RadrootsKit
ARTIFACTS_DIR := $(KIT_ROOT)/Artifacts
GENERATED_SWIFT_DIR := $(KIT_ROOT)/Sources/RadrootsKit/Generated

BUILD_ROOT := $(CURDIR)/.build
SOURCE_ROOT := $(BUILD_ROOT)/source
TARGET_DIR := $(BUILD_ROOT)/target
OUT_DIR := $(BUILD_ROOT)/out
GENERATED_DIR := $(OUT_DIR)/generated
HEADERS_DIR := $(OUT_DIR)/headers

CRATE_NAME := radroots-app-ffi-swift
FFI_OUTPUT_NAME := RadrootsFFI
LIB_STEM := libradroots_studio_app_ffi_swift

GIT_CRATES_DIR := $(SOURCE_ROOT)/radroots-crates
CRATE_ARCHIVE := $(SOURCE_ROOT)/$(CRATE_NAME)-$(RADROOTS_APP_FFI_CRATE_VERSION).crate
CRATE_EXTRACT_DIR := $(SOURCE_ROOT)/$(CRATE_NAME)-$(RADROOTS_APP_FFI_CRATE_VERSION)

ifeq ($(SOURCE_MODE),git)
FFI_MANIFEST := $(GIT_CRATES_DIR)/app-ffi-swift/Cargo.toml
UNIFFI_CONFIG := $(GIT_CRATES_DIR)/app-ffi-swift/uniffi.toml
SOURCE_TARGET := sync-source-git
else ifeq ($(SOURCE_MODE),crates)
FFI_MANIFEST := $(CRATE_EXTRACT_DIR)/Cargo.toml
UNIFFI_CONFIG := $(CRATE_EXTRACT_DIR)/uniffi.toml
SOURCE_TARGET := sync-source-crates
else ifeq ($(SOURCE_MODE),local)
FFI_MANIFEST := $(LOCAL_FFI_MANIFEST)
UNIFFI_CONFIG := $(dir $(LOCAL_FFI_MANIFEST))uniffi.toml
SOURCE_TARGET := sync-source-local
else
$(error SOURCE_MODE must be one of: git, crates, local)
endif

FFI_CRATE_DIR := $(dir $(FFI_MANIFEST))

CARGO := CARGO_TARGET_DIR=$(TARGET_DIR) cargo

LIB_DEVICE := $(TARGET_DIR)/aarch64-apple-ios/release/$(LIB_STEM).a
LIB_SIMULATOR := $(TARGET_DIR)/aarch64-apple-ios-sim/release/$(LIB_STEM).a
LIB_HOST := $(TARGET_DIR)/release/$(LIB_STEM).dylib

.PHONY: all clean distclean print-config sync-source sync-source-git sync-source-crates sync-source-local ensure-toolchain build generate package install

all: sync-source build generate package install
	@echo "done"
	@echo "  - source mode: $(SOURCE_MODE)"
	@echo "  - xcframework: $(ARTIFACTS_DIR)/$(FFI_OUTPUT_NAME).xcframework"
	@echo "  - swift bindings: $(GENERATED_SWIFT_DIR)"

print-config:
	@echo "SOURCE_MODE=$(SOURCE_MODE)"
	@echo "FFI_MANIFEST=$(FFI_MANIFEST)"
	@echo "UNIFFI_CONFIG=$(UNIFFI_CONFIG)"
	@echo "ARTIFACTS_DIR=$(ARTIFACTS_DIR)"
	@echo "GENERATED_SWIFT_DIR=$(GENERATED_SWIFT_DIR)"

clean:
	rm -rf $(TARGET_DIR) $(OUT_DIR) $(ARTIFACTS_DIR)/$(FFI_OUTPUT_NAME).xcframework
	if [ -d $(GENERATED_SWIFT_DIR) ]; then \
		find $(GENERATED_SWIFT_DIR) -maxdepth 1 -type f -name '*.swift' -delete; \
	fi

distclean: clean
	rm -rf $(SOURCE_ROOT)

sync-source: $(SOURCE_TARGET)

sync-source-git:
	mkdir -p $(SOURCE_ROOT)
	if [ ! -d $(GIT_CRATES_DIR)/.git ]; then \
		git clone --filter=blob:none $(RADROOTS_CRATES_GIT_URL) $(GIT_CRATES_DIR); \
	fi
	git -C $(GIT_CRATES_DIR) fetch --tags --force origin
	git -C $(GIT_CRATES_DIR) checkout --detach $(RADROOTS_CRATES_GIT_REV)
	test -f $(FFI_MANIFEST)

sync-source-crates:
	mkdir -p $(SOURCE_ROOT)
	rm -rf $(CRATE_EXTRACT_DIR)
	curl -fLsS https://crates.io/api/v1/crates/$(CRATE_NAME)/$(RADROOTS_APP_FFI_CRATE_VERSION)/download -o $(CRATE_ARCHIVE)
	tar -xzf $(CRATE_ARCHIVE) -C $(SOURCE_ROOT)
	test -f $(FFI_MANIFEST)

sync-source-local:
	if [ -z "$(LOCAL_FFI_MANIFEST)" ]; then \
		echo "LOCAL_FFI_MANIFEST is required when SOURCE_MODE=local"; \
		exit 1; \
	fi
	test -f $(LOCAL_FFI_MANIFEST)
	test -f $(UNIFFI_CONFIG)

ensure-toolchain:
	rustup target add aarch64-apple-ios aarch64-apple-ios-sim

build: ensure-toolchain
	mkdir -p $(TARGET_DIR) $(OUT_DIR)
	$(CARGO) build --manifest-path $(FFI_MANIFEST) --release --target aarch64-apple-ios
	$(CARGO) build --manifest-path $(FFI_MANIFEST) --release --target aarch64-apple-ios-sim
	$(CARGO) build --manifest-path $(FFI_MANIFEST) --release

generate:
	mkdir -p $(GENERATED_DIR) $(HEADERS_DIR)
	cd $(FFI_CRATE_DIR) && CARGO_TARGET_DIR=$(TARGET_DIR) cargo run --manifest-path Cargo.toml --bin uniffi-bindgen -- \
		generate --library $(LIB_HOST) \
		--language swift \
		--out-dir $(GENERATED_DIR) \
		--config $(UNIFFI_CONFIG)
	cp $(GENERATED_DIR)/$(FFI_OUTPUT_NAME).h $(HEADERS_DIR)/
	cp $(GENERATED_DIR)/$(FFI_OUTPUT_NAME).modulemap $(HEADERS_DIR)/module.modulemap

package:
	mkdir -p $(ARTIFACTS_DIR)
	rm -rf $(ARTIFACTS_DIR)/$(FFI_OUTPUT_NAME).xcframework
	xcodebuild -create-xcframework \
		-library $(LIB_DEVICE) -headers $(HEADERS_DIR) \
		-library $(LIB_SIMULATOR) -headers $(HEADERS_DIR) \
		-output $(ARTIFACTS_DIR)/$(FFI_OUTPUT_NAME).xcframework

install:
	mkdir -p $(GENERATED_SWIFT_DIR)
	if [ -d $(GENERATED_SWIFT_DIR) ]; then \
		find $(GENERATED_SWIFT_DIR) -maxdepth 1 -type f -name '*.swift' -delete; \
	fi
	cp $(GENERATED_DIR)/*.swift $(GENERATED_SWIFT_DIR)/

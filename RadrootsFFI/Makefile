SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

-include source.lock
-include Config/ffi-build.env

SOURCE_MODE ?= git
RADROOTS_FIELD_LIB_GIT_URL ?= git@github.com:radrootslabs/app_rt.git
RADROOTS_FIELD_LIB_GIT_REV ?= 922c8a82977fa0e41616ebdf978ef2df78c0063c
RADROOTS_FIELD_FFI_CRATE_VERSION ?= 0.1.0-alpha.1
FFI_FEATURES ?= radroots_app_core/rt,radroots_app_core/nostr-client
LOCAL_FFI_MANIFEST ?=
IPHONEOS_DEPLOYMENT_TARGET ?= 18.0
RUSTUP_TOOLCHAIN ?= 1.92.0-aarch64-apple-darwin

IOS_ROOT := $(abspath $(CURDIR)/..)
APP_ROOT := $(IOS_ROOT)/Radroots
ARTIFACTS_DIR := $(APP_ROOT)/Frameworks
GENERATED_SWIFT_DIR := $(APP_ROOT)/Generated

BUILD_ROOT := $(CURDIR)/.build
SOURCE_ROOT := $(BUILD_ROOT)/source
TARGET_DIR ?= $(CARGO_TARGET_DIR)
ifeq ($(strip $(TARGET_DIR)),)
TARGET_DIR := $(BUILD_ROOT)/target
endif
override TARGET_DIR := $(abspath $(TARGET_DIR))
OUT_DIR := $(BUILD_ROOT)/out
GENERATED_DIR := $(OUT_DIR)/generated
HEADERS_DIR := $(OUT_DIR)/headers

CRATE_NAME := radroots_app_ffi
FFI_OUTPUT_NAME := RadrootsFFI
LIB_STEM := libradroots_app_ffi

GIT_FIELD_LIB_DIR := $(SOURCE_ROOT)/field-lib
CRATE_ARCHIVE := $(SOURCE_ROOT)/$(CRATE_NAME)-$(RADROOTS_FIELD_FFI_CRATE_VERSION).crate
CRATE_EXTRACT_DIR := $(SOURCE_ROOT)/$(CRATE_NAME)-$(RADROOTS_FIELD_FFI_CRATE_VERSION)
CARGO_FEATURE_FLAGS := $(if $(strip $(FFI_FEATURES)),--features $(FFI_FEATURES),)

ifeq ($(SOURCE_MODE),git)
FFI_MANIFEST := $(GIT_FIELD_LIB_DIR)/crates/ffi/Cargo.toml
UNIFFI_CONFIG := $(GIT_FIELD_LIB_DIR)/crates/ffi/uniffi.toml
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

RUSTC_BIN := $(shell rustup which --toolchain $(RUSTUP_TOOLCHAIN) rustc)
CARGO_BIN := rustup run $(RUSTUP_TOOLCHAIN) cargo
CARGO := IPHONEOS_DEPLOYMENT_TARGET=$(IPHONEOS_DEPLOYMENT_TARGET) RUSTC=$(RUSTC_BIN) CARGO_TARGET_DIR=$(TARGET_DIR) $(CARGO_BIN)

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
	@echo "TARGET_DIR=$(TARGET_DIR)"
	@echo "IPHONEOS_DEPLOYMENT_TARGET=$(IPHONEOS_DEPLOYMENT_TARGET)"
	@echo "RUSTUP_TOOLCHAIN=$(RUSTUP_TOOLCHAIN)"
	@echo "RUSTC_BIN=$(RUSTC_BIN)"

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
	if [ ! -d $(GIT_FIELD_LIB_DIR)/.git ]; then \
		git clone --filter=blob:none $(RADROOTS_FIELD_LIB_GIT_URL) $(GIT_FIELD_LIB_DIR); \
	fi
	git -C $(GIT_FIELD_LIB_DIR) fetch --tags --force origin
	git -C $(GIT_FIELD_LIB_DIR) checkout --detach $(RADROOTS_FIELD_LIB_GIT_REV)
	test -f $(FFI_MANIFEST)

sync-source-crates:
	mkdir -p $(SOURCE_ROOT)
	rm -rf $(CRATE_EXTRACT_DIR)
	curl -fLsS https://crates.io/api/v1/crates/$(CRATE_NAME)/$(RADROOTS_FIELD_FFI_CRATE_VERSION)/download -o $(CRATE_ARCHIVE)
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
	rustup target add --toolchain $(RUSTUP_TOOLCHAIN) aarch64-apple-ios aarch64-apple-ios-sim

build: ensure-toolchain
	mkdir -p $(TARGET_DIR) $(OUT_DIR)
	$(CARGO) build --manifest-path $(FFI_MANIFEST) $(CARGO_FEATURE_FLAGS) --release --target aarch64-apple-ios
	$(CARGO) build --manifest-path $(FFI_MANIFEST) $(CARGO_FEATURE_FLAGS) --release --target aarch64-apple-ios-sim
	$(CARGO) build --manifest-path $(FFI_MANIFEST) $(CARGO_FEATURE_FLAGS) --release

generate:
	rm -rf $(GENERATED_DIR) $(HEADERS_DIR)
	mkdir -p $(GENERATED_DIR) $(HEADERS_DIR)
	cd $(FFI_CRATE_DIR) && $(CARGO) run --manifest-path Cargo.toml $(CARGO_FEATURE_FLAGS) --bin uniffi-bindgen -- \
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

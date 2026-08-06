SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

include source.lock

override IPHONEOS_DEPLOYMENT_TARGET := 18.0
override RUSTUP_TOOLCHAIN := 1.97.1-aarch64-apple-darwin

IOS_ROOT := $(abspath $(CURDIR)/..)
APP_ROOT := $(IOS_ROOT)/Radroots
ARTIFACTS_DIR := $(APP_ROOT)/Frameworks
GENERATED_SWIFT_DIR := $(APP_ROOT)/Generated

BUILD_ROOT := $(CURDIR)/.build
SOURCE_ROOT := $(CURDIR)/.radroots/source
TARGET_DIR ?= $(CARGO_TARGET_DIR)
ifeq ($(strip $(TARGET_DIR)),)
TARGET_DIR := $(BUILD_ROOT)/target
endif
override TARGET_DIR := $(abspath $(TARGET_DIR))
OUT_DIR := $(BUILD_ROOT)/out
GENERATED_DIR := $(OUT_DIR)/generated
HEADERS_DIR := $(OUT_DIR)/headers

FFI_OUTPUT_NAME := RadrootsFFI
LIB_STEM := libradroots_mobile_ffi
GIT_FIELD_LIB_DIR := $(SOURCE_ROOT)/lib
PROVENANCE_OUTPUT := RadrootsFFI/provenance.json
SOURCE_WORKSPACE_ROOT := $(GIT_FIELD_LIB_DIR)
FFI_MANIFEST := $(SOURCE_WORKSPACE_ROOT)/crates/mobile_ffi/Cargo.toml
UNIFFI_CONFIG := $(SOURCE_WORKSPACE_ROOT)/crates/mobile_ffi/uniffi.toml

BINDGEN_MANIFEST := $(SOURCE_WORKSPACE_ROOT)/Cargo.toml
RUSTC_BIN := $(shell rustup which --toolchain $(RUSTUP_TOOLCHAIN) rustc)
CARGO_BIN := rustup run $(RUSTUP_TOOLCHAIN) cargo
CARGO := IPHONEOS_DEPLOYMENT_TARGET=$(IPHONEOS_DEPLOYMENT_TARGET) \
	RUSTC=$(RUSTC_BIN) \
	CARGO_TARGET_DIR=$(TARGET_DIR) \
	RADROOTS_SOURCE_SHA=$(RADROOTS_FIELD_LIB_GIT_REV) \
	SOURCE_DATE_EPOCH=$(RADROOTS_FIELD_SOURCE_DATE_EPOCH) \
	$(CARGO_BIN)

LIB_DEVICE := $(TARGET_DIR)/aarch64-apple-ios/release/$(LIB_STEM).a
LIB_SIMULATOR := $(TARGET_DIR)/aarch64-apple-ios-sim/release/$(LIB_STEM).a
LIB_HOST := $(TARGET_DIR)/release/$(LIB_STEM).dylib

.PHONY: all clean distclean print-config sync-source ensure-toolchain build generate package install provenance verify

all: verify
	@echo "done"
	@echo "  - source: $(RADROOTS_FIELD_LIB_GIT_URL)@$(RADROOTS_FIELD_LIB_GIT_REV)"
	@echo "  - xcframework: $(ARTIFACTS_DIR)/$(FFI_OUTPUT_NAME).xcframework"
	@echo "  - swift bindings: $(GENERATED_SWIFT_DIR)"

print-config:
	@echo "SOURCE_WORKSPACE_ROOT=$(SOURCE_WORKSPACE_ROOT)"
	@echo "FFI_MANIFEST=$(FFI_MANIFEST)"
	@echo "BINDGEN_MANIFEST=$(BINDGEN_MANIFEST)"
	@echo "UNIFFI_CONFIG=$(UNIFFI_CONFIG)"
	@echo "ARTIFACTS_DIR=$(ARTIFACTS_DIR)"
	@echo "GENERATED_SWIFT_DIR=$(GENERATED_SWIFT_DIR)"
	@echo "TARGET_DIR=$(TARGET_DIR)"
	@echo "IPHONEOS_DEPLOYMENT_TARGET=$(IPHONEOS_DEPLOYMENT_TARGET)"
	@echo "RUSTUP_TOOLCHAIN=$(RUSTUP_TOOLCHAIN)"
	@echo "RUSTC_BIN=$(RUSTC_BIN)"
	@echo "RADROOTS_FIELD_LIB_GIT_REV=$(RADROOTS_FIELD_LIB_GIT_REV)"
	@echo "RADROOTS_FIELD_SOURCE_DATE_EPOCH=$(RADROOTS_FIELD_SOURCE_DATE_EPOCH)"

clean:
	rm -rf $(TARGET_DIR) $(OUT_DIR) $(ARTIFACTS_DIR)/$(FFI_OUTPUT_NAME).xcframework
	if [ -d $(GENERATED_SWIFT_DIR) ]; then \
		find $(GENERATED_SWIFT_DIR) -maxdepth 1 -type f -name '*.swift' -delete; \
	fi

distclean: clean
	rm -rf $(SOURCE_ROOT)

sync-source:
	mkdir -p $(SOURCE_ROOT)
	if [ ! -d $(GIT_FIELD_LIB_DIR)/.git ]; then \
		git clone --filter=blob:none $(RADROOTS_FIELD_LIB_GIT_URL) $(GIT_FIELD_LIB_DIR); \
	fi
	git -C $(GIT_FIELD_LIB_DIR) fetch --tags --force origin
	git -C $(GIT_FIELD_LIB_DIR) checkout --detach $(RADROOTS_FIELD_LIB_GIT_REV)
	test "$$(git -C $(GIT_FIELD_LIB_DIR) rev-parse HEAD)" = "$(RADROOTS_FIELD_LIB_GIT_REV)"
	git -C $(GIT_FIELD_LIB_DIR) diff --quiet --no-ext-diff
	git -C $(GIT_FIELD_LIB_DIR) diff --cached --quiet --no-ext-diff
	test -f $(FFI_MANIFEST)
	test -f $(BINDGEN_MANIFEST)
	test -f $(UNIFFI_CONFIG)
	test "$$($(CARGO_BIN) pkgid --manifest-path $(FFI_MANIFEST) | sed -E 's/.*@//')" = "$(RADROOTS_FIELD_FFI_CRATE_VERSION)"

ensure-toolchain:
	rustup target add --toolchain $(RUSTUP_TOOLCHAIN) aarch64-apple-ios aarch64-apple-ios-sim

build: sync-source ensure-toolchain
	mkdir -p $(TARGET_DIR) $(OUT_DIR)
	$(CARGO) build --manifest-path $(FFI_MANIFEST) --release --locked --target aarch64-apple-ios
	$(CARGO) build --manifest-path $(FFI_MANIFEST) --release --locked --target aarch64-apple-ios-sim
	$(CARGO) build --manifest-path $(FFI_MANIFEST) --release --locked

generate: build
	rm -rf $(GENERATED_DIR) $(HEADERS_DIR)
	mkdir -p $(GENERATED_DIR) $(HEADERS_DIR)
	$(CARGO) run --manifest-path $(BINDGEN_MANIFEST) -p radroots_mobile_bindgen --locked -- \
		generate $(LIB_HOST) --library \
		--language swift \
		--metadata-no-deps \
		--out-dir $(GENERATED_DIR) \
		--config $(UNIFFI_CONFIG)
	cp $(GENERATED_DIR)/$(FFI_OUTPUT_NAME).h $(HEADERS_DIR)/
	cp $(GENERATED_DIR)/$(FFI_OUTPUT_NAME).modulemap $(HEADERS_DIR)/module.modulemap

package: generate
	mkdir -p $(ARTIFACTS_DIR)
	rm -rf $(ARTIFACTS_DIR)/$(FFI_OUTPUT_NAME).xcframework
	xcodebuild -create-xcframework \
		-library $(LIB_DEVICE) -headers $(HEADERS_DIR) \
		-library $(LIB_SIMULATOR) -headers $(HEADERS_DIR) \
		-output $(ARTIFACTS_DIR)/$(FFI_OUTPUT_NAME).xcframework

install: package
	mkdir -p $(GENERATED_SWIFT_DIR)
	if [ -d $(GENERATED_SWIFT_DIR) ]; then \
		find $(GENERATED_SWIFT_DIR) -maxdepth 1 -type f -name '*.swift' -delete; \
	fi
	cp $(GENERATED_DIR)/*.swift $(GENERATED_SWIFT_DIR)/

provenance: install
	$(CARGO) run --manifest-path $(BINDGEN_MANIFEST) -p xtask --locked -- \
		artifact \
		--product mobile \
		--target ios \
		--language swift \
		--mode write \
		--consumer-root $(IOS_ROOT) \
		--source-root $(SOURCE_WORKSPACE_ROOT) \
		--output $(PROVENANCE_OUTPUT) \
		--source-date-epoch $(RADROOTS_FIELD_SOURCE_DATE_EPOCH) \
		--builder-id radroots_ios_app
	$(CARGO) run --manifest-path $(BINDGEN_MANIFEST) -p xtask --locked -- \
		artifact \
		--product mobile \
		--target ios \
		--language swift \
		--mode check \
		--consumer-root $(IOS_ROOT) \
		--source-root $(SOURCE_WORKSPACE_ROOT) \
		--output $(PROVENANCE_OUTPUT) \
		--source-date-epoch $(RADROOTS_FIELD_SOURCE_DATE_EPOCH) \
		--builder-id radroots_ios_app

verify: provenance
	test "$$(shasum -a 256 $(LIB_DEVICE) | awk '{print $$1}')" = "$(RADROOTS_FIELD_FFI_DEVICE_SHA256)"
	test "$$(shasum -a 256 $(LIB_SIMULATOR) | awk '{print $$1}')" = "$(RADROOTS_FIELD_FFI_SIMULATOR_SHA256)"
	test "$$(shasum -a 256 $(GENERATED_SWIFT_DIR)/RadrootsKitBindings.swift | awk '{print $$1}')" = "$(RADROOTS_FIELD_FFI_SWIFT_SHA256)"

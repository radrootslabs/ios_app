SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

-include source.lock
-include Config/ffi-build.env

SOURCE_MODE ?= git
RADROOTS_FIELD_LIB_GIT_URL ?= https://github.com/radrootslabs/app_rt.git
RADROOTS_FIELD_LIB_GIT_REV ?= b770841d2d2ea1cafc1d4a644d596cb8727624d9
RADROOTS_FIELD_FFI_CRATE_VERSION ?= 0.1.0-alpha.1
RADROOTS_FIELD_SOURCE_DATE_EPOCH ?= 1785777481
LOCAL_FFI_MANIFEST ?=
IPHONEOS_DEPLOYMENT_TARGET ?= 18.0
RUSTUP_TOOLCHAIN ?= 1.97.1-aarch64-apple-darwin
CARGO_CONFIG_ARGS ?=

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

FFI_OUTPUT_NAME := RadrootsFFI
LIB_STEM := libradroots_app_ffi
GIT_FIELD_LIB_DIR := $(SOURCE_ROOT)/app-rt

ifeq ($(SOURCE_MODE),git)
SOURCE_WORKSPACE_ROOT := $(GIT_FIELD_LIB_DIR)
FFI_MANIFEST := $(SOURCE_WORKSPACE_ROOT)/crates/ffi/Cargo.toml
UNIFFI_CONFIG := $(SOURCE_WORKSPACE_ROOT)/crates/ffi/uniffi.toml
SOURCE_TARGET := sync-source-git
else ifeq ($(SOURCE_MODE),local)
FFI_MANIFEST := $(LOCAL_FFI_MANIFEST)
SOURCE_WORKSPACE_ROOT := $(abspath $(dir $(LOCAL_FFI_MANIFEST))/../..)
UNIFFI_CONFIG := $(SOURCE_WORKSPACE_ROOT)/crates/ffi/uniffi.toml
SOURCE_TARGET := sync-source-local
else
$(error SOURCE_MODE must be one of: git, local)
endif

BINDGEN_MANIFEST := $(SOURCE_WORKSPACE_ROOT)/Cargo.toml
RUSTC_BIN := $(shell rustup which --toolchain $(RUSTUP_TOOLCHAIN) rustc)
CARGO_BIN := rustup run $(RUSTUP_TOOLCHAIN) cargo $(CARGO_CONFIG_ARGS)
CARGO := IPHONEOS_DEPLOYMENT_TARGET=$(IPHONEOS_DEPLOYMENT_TARGET) \
	RUSTC=$(RUSTC_BIN) \
	CARGO_TARGET_DIR=$(TARGET_DIR) \
	RADROOTS_SOURCE_SHA=$(RADROOTS_FIELD_LIB_GIT_REV) \
	SOURCE_DATE_EPOCH=$(RADROOTS_FIELD_SOURCE_DATE_EPOCH) \
	$(CARGO_BIN)

LIB_DEVICE := $(TARGET_DIR)/aarch64-apple-ios/release/$(LIB_STEM).a
LIB_SIMULATOR := $(TARGET_DIR)/aarch64-apple-ios-sim/release/$(LIB_STEM).a
LIB_HOST := $(TARGET_DIR)/release/$(LIB_STEM).dylib

.PHONY: all clean distclean print-config sync-source sync-source-git sync-source-local ensure-toolchain build generate package install

all: sync-source build generate package install
	@echo "done"
	@echo "  - source mode: $(SOURCE_MODE)"
	@echo "  - xcframework: $(ARTIFACTS_DIR)/$(FFI_OUTPUT_NAME).xcframework"
	@echo "  - swift bindings: $(GENERATED_SWIFT_DIR)"

print-config:
	@echo "SOURCE_MODE=$(SOURCE_MODE)"
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
	@echo "CARGO_CONFIG_ARGS=$(CARGO_CONFIG_ARGS)"
	@echo "RADROOTS_FIELD_LIB_GIT_REV=$(RADROOTS_FIELD_LIB_GIT_REV)"
	@echo "RADROOTS_FIELD_SOURCE_DATE_EPOCH=$(RADROOTS_FIELD_SOURCE_DATE_EPOCH)"

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
	test -f $(BINDGEN_MANIFEST)

sync-source-local:
	if [ -z "$(LOCAL_FFI_MANIFEST)" ]; then \
		echo "LOCAL_FFI_MANIFEST is required when SOURCE_MODE=local"; \
		exit 1; \
	fi
	test -f $(FFI_MANIFEST)
	test -f $(UNIFFI_CONFIG)
	test -f $(BINDGEN_MANIFEST)

ensure-toolchain:
	rustup target add --toolchain $(RUSTUP_TOOLCHAIN) aarch64-apple-ios aarch64-apple-ios-sim

build: ensure-toolchain
	mkdir -p $(TARGET_DIR) $(OUT_DIR)
	$(CARGO) build --manifest-path $(FFI_MANIFEST) --release --locked --target aarch64-apple-ios
	$(CARGO) build --manifest-path $(FFI_MANIFEST) --release --locked --target aarch64-apple-ios-sim
	$(CARGO) build --manifest-path $(FFI_MANIFEST) --release --locked

generate:
	rm -rf $(GENERATED_DIR) $(HEADERS_DIR)
	mkdir -p $(GENERATED_DIR) $(HEADERS_DIR)
	$(CARGO) run --manifest-path $(BINDGEN_MANIFEST) -p radroots_app_bindgen --locked -- \
		generate $(LIB_HOST) --library \
		--language swift \
		--metadata-no-deps \
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

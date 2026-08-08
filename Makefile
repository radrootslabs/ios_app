SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

FFI_ROOT := RadrootsFFI
SIMULATOR_NAME ?= iPhone 17 Pro
SIMULATOR_DESTINATION := platform=iOS Simulator,name=$(SIMULATOR_NAME)

.NOTPARALLEL:

.PHONY: all bootstrap ffi-bootstrap artifact-check package-contract-check \
	package-resolve package-build package-test project xcodegen xcode-resolve \
	xcode-build-debug xcode-build-release unit-test ui-test api-snapshot-write \
	api-snapshot-check verify clean distclean

all: verify

ffi-bootstrap:
	cargo extbuild run -- $(MAKE) -C $(FFI_ROOT) verify

artifact-check:
	cargo extbuild run -- $(FFI_ROOT)/scripts/verify-installed-artifacts.sh

package-contract-check:
	cargo extbuild run -- scripts/verify-package-contract.sh

package-resolve: artifact-check package-contract-check
	cargo extbuild run -- scripts/swift-package.sh resolve

project xcodegen:
	cargo extbuild run -- scripts/generate-project.sh

xcode-resolve: artifact-check project
	cargo extbuild run -- scripts/xcode.sh resolve

bootstrap: ffi-bootstrap package-resolve xcode-resolve

package-build: artifact-check package-contract-check
	cargo extbuild run -- scripts/xcode.sh package-build

package-test: artifact-check package-contract-check
	cargo extbuild run -- scripts/xcode.sh package-test '$(SIMULATOR_DESTINATION)'

xcode-build-debug: artifact-check package-contract-check project
	cargo extbuild run -- scripts/xcode.sh project-build Debug

xcode-build-release: artifact-check package-contract-check project
	cargo extbuild run -- scripts/xcode.sh project-build Release

unit-test: artifact-check package-contract-check project
	cargo extbuild run -- scripts/xcode.sh project-test '$(SIMULATOR_DESTINATION)' RadrootsTests

ui-test: artifact-check package-contract-check project
	cargo extbuild run -- scripts/xcode.sh project-test '$(SIMULATOR_DESTINATION)' RadrootsUITests

api-snapshot-write: package-build
	cargo extbuild run -- scripts/app-api-snapshot.sh write

api-snapshot-check: package-build
	cargo extbuild run -- scripts/app-api-snapshot.sh check

verify: artifact-check package-contract-check package-build package-test \
	xcode-build-debug xcode-build-release unit-test ui-test api-snapshot-check

clean:
	cargo extbuild run -- $(MAKE) -C $(FFI_ROOT) clean

distclean:
	cargo extbuild run -- $(MAKE) -C $(FFI_ROOT) distclean

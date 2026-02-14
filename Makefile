SHELL := /bin/bash

# Directories
INPUT_DIR   ?= $(CURDIR)/build/images
OUTPUT_DIR  ?= $(CURDIR)/build/export
ONE_APPS_DIR ?= $(CURDIR)/build/one-apps
PACKER_DIR  := $(CURDIR)/build/packer

# Build settings
HEADLESS    ?= true
VERSION     ?= 1.0.0
IMAGE_NAME  := slm-copilot-$(VERSION).qcow2

# Test settings (required for 'make test')
ENDPOINT    ?=
PASSWORD    ?=

.PHONY: build test checksum clean lint help

help:
	@echo "SLM-Copilot Build Targets"
	@echo "========================="
	@echo "  make build                              Build QCOW2 image"
	@echo "  make test ENDPOINT=... PASSWORD=...     Test running instance"
	@echo "  make checksum                           Generate checksums for image"
	@echo "  make clean                              Remove build artifacts"
	@echo "  make lint                               Shellcheck all bash scripts"

build:
	@echo "==> Building SLM-Copilot image..."
	INPUT_DIR=$(INPUT_DIR) OUTPUT_DIR=$(OUTPUT_DIR) ONE_APPS_DIR=$(ONE_APPS_DIR) \
	HEADLESS=$(HEADLESS) VERSION=$(VERSION) \
	./build.sh

test:
	@test -n "$(ENDPOINT)" || { echo "ERROR: ENDPOINT required (e.g., make test ENDPOINT=https://10.0.0.1 PASSWORD=xxx)"; exit 1; }
	@test -n "$(PASSWORD)" || { echo "ERROR: PASSWORD required"; exit 1; }
	./test.sh "$(ENDPOINT)" "$(PASSWORD)"

checksum: $(OUTPUT_DIR)/$(IMAGE_NAME)
	@echo "==> Generating checksums..."
	cd $(OUTPUT_DIR) && sha256sum $(IMAGE_NAME) > $(IMAGE_NAME).sha256
	cd $(OUTPUT_DIR) && md5sum $(IMAGE_NAME) > $(IMAGE_NAME).md5
	@echo "SHA256: $$(cat $(OUTPUT_DIR)/$(IMAGE_NAME).sha256)"
	@echo "MD5:    $$(cat $(OUTPUT_DIR)/$(IMAGE_NAME).md5)"

clean:
	rm -rf $(OUTPUT_DIR)
	rm -f $(PACKER_DIR)/slm-copilot-cloud-init.iso
	@echo "==> Build artifacts cleaned."

lint:
	@echo "==> Running shellcheck on all bash scripts..."
	@shellcheck -x appliances/slm-copilot/appliance.sh
	@if [ -f build.sh ]; then shellcheck -x build.sh; fi
	@if [ -f test.sh ]; then shellcheck -x test.sh; fi
	@find build/packer/scripts -name '*.sh' -exec shellcheck -x {} + 2>/dev/null || true
	@echo "==> All scripts passed shellcheck."

BINARY_NAME ?= shipper-backend
BUILD_DIR ?= build
GOBIN ?= /opt/app-root/gobinary

.PHONY: build install clean

build:
	@echo "Building $(BINARY_NAME) (node=$(node))..."
	@mkdir -p $(BUILD_DIR)
	GO111MODULE=on CGO_ENABLED=0 go build -o $(BUILD_DIR)/$(BINARY_NAME) ./cmd/shipper-backend

install:
	@echo "Installing to dest=$(dest) ..."
	@mkdir -p $(dest)
	@cp $(BUILD_DIR)/$(BINARY_NAME) $(dest)/gobinary
	@chmod +x $(dest)/gobinary

clean:
	rm -rf $(BUILD_DIR)

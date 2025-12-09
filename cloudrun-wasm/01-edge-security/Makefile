# Makefile for Demo 1: Edge Security (PII Scrubbing)
# Rust + proxy-wasm-rust-sdk
# Self-contained with local infrastructure and scripts

.PHONY: all full build test clean deploy destroy
.PHONY: fmt lint check setup help test-live

# Wasm target
TARGET := wasm32-unknown-unknown

# Use rustup's cargo if available (needed for wasm32 target)
CARGO := $(shell if [ -x "$$HOME/.cargo/bin/cargo" ]; then echo "$$HOME/.cargo/bin/cargo"; else echo "cargo"; fi)

# Output paths
WASM_FILE := target/$(TARGET)/release/edge_security.wasm

# Default target
all: build test deploy test-live

## all: Complete workflow - build, test, deploy, and verify (default target)

## quick: Build and test only (no deployment)
quick: build test

# =============================================================================
# Build Targets
# =============================================================================

## full: Alias for 'all' (complete workflow)
full: all

## build: Build the Wasm binary
build:
	@echo "Building Edge Security Wasm plugin..."
	$(CARGO) build --target $(TARGET) --release
	@echo "Built: $(WASM_FILE)"
	@ls -lh $(WASM_FILE)

# =============================================================================
# Test Targets
# =============================================================================

## test: Run unit tests
test:
	@echo "Running tests..."
	$(CARGO) test

## test-verbose: Run tests with verbose output
test-verbose:
	@echo "Running tests (verbose)..."
	$(CARGO) test -- --nocapture

# =============================================================================
# Code Quality Targets
# =============================================================================

## lint: Run clippy linter
lint:
	@echo "Running clippy..."
	$(CARGO) clippy --target $(TARGET) -- -D warnings

## fmt: Format code
fmt:
	@echo "Formatting code..."
	$(CARGO) fmt

## fmt-check: Check code formatting
fmt-check:
	@echo "Checking code formatting..."
	$(CARGO) fmt -- --check

## check: Run all checks (fmt, lint, test)
check: fmt-check lint test

# =============================================================================
# Deploy Targets
# =============================================================================

## deploy: Deploy to Cloud Run using Cloud Build (requires GCP credentials)
deploy: build
	@./scripts/02-deploy.sh

## deploy-skip-build: Deploy without rebuilding (use existing image)
deploy-skip-build:
	@./scripts/02-deploy.sh --skip-build

## test-live: Test deployed Cloud Run service (with authentication)
test-live:
	@./scripts/03-test.sh

## destroy: Destroy all Demo 1 GCP infrastructure
destroy:
	@./scripts/99-remove.sh

# =============================================================================
# Setup Targets
# =============================================================================

## setup: Set up development environment
setup:
	@./scripts/setup-dev.sh

## setup-verify: Verify development environment
setup-verify:
	@./scripts/setup-dev.sh --verify

# =============================================================================
# Utility Targets
# =============================================================================

## clean: Clean build artifacts
clean:
	@echo "Cleaning..."
	$(CARGO) clean
	@echo "Clean complete"

## size: Show Wasm file size
size: build
	@echo "Wasm file size:"
	@ls -lh $(WASM_FILE)
	@echo ""
	@echo "Sections:"
	@wasm-objdump -h $(WASM_FILE) 2>/dev/null || echo "(install wabt for detailed info)"

## doc: Generate documentation
doc:
	@echo "Generating documentation..."
	$(CARGO) doc --no-deps --open

# =============================================================================
# Help
# =============================================================================

## help: Show this help
help:
	@echo "Demo 1: Edge Security (PII Scrubbing)"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## /  /'
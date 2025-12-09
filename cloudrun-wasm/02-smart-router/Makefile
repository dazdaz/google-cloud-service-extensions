# Makefile for Demo 2: Smart Router (A/B Testing)
# Rust + proxy-wasm
# Self-contained with local infrastructure and scripts

.PHONY: all full build build-wasm test clean deploy deploy-skip-build destroy
.PHONY: fmt lint check doc docker-up docker-down docker-logs setup test-live help

# Output file
WASM_FILE := smart_router.wasm
WASM_BUILD_DIR := target/wasm32-unknown-unknown/release/

# Cargo build options
CARGO_OPTS := --target wasm32-unknown-unknown --release --package smart-router

# Ensure Homebrew-installed CLIs (e.g., gcloud) are reachable even in non-login shells
GCLOUD := $(shell \
	if command -v gcloud >/dev/null 2>&1; then \
		command -v gcloud; \
	elif [ -x /opt/homebrew/bin/gcloud ]; then \
		echo /opt/homebrew/bin/gcloud; \
	elif [ -x /usr/local/bin/gcloud ]; then \
		echo /usr/local/bin/gcloud; \
	fi \
)

ifeq ($(strip $(GCLOUD)),)
$(error gcloud CLI not found. Install the Google Cloud SDK or update PATH before running make.)
endif

# Ensure Cargo is reachable
CARGO := $(shell \
	if command -v cargo >/dev/null 2>&1; then \
		command -v cargo; \
	elif [ -x ~/.cargo/bin/cargo ]; then \
		echo ~/.cargo/bin/cargo; \
	elif [ -x /opt/homebrew/bin/cargo ]; then \
		echo /opt/homebrew/bin/cargo; \
	fi \
)

ifeq ($(strip $(CARGO)),)
$(error cargo CLI not found. Install Rust or update PATH before running make.)
endif

GCLOUD_DIR := $(patsubst %/,%,$(dir $(GCLOUD)))
EXTRA_PATHS := /opt/homebrew/bin:/usr/local/bin:/usr/local/sbin
export PATH := $(GCLOUD_DIR):$(EXTRA_PATHS):$(PATH)

# GCP Configuration
PROJECT_ID := $(shell $(GCLOUD) config get-value project 2>/dev/null)
REGION := us-central1
ARTIFACT_REPO := demo2-smart-router

# Use rustup's cargo for WASM builds
REPO_ROOT := $(shell cd ../.. && pwd)

# Default target
all: build test deploy test-live

## all: Complete workflow - build, test, deploy, and verify (default target)

## quick: Build and test only (no deployment)
quick: build test

# =============================================================================
# Build Targets
# =============================================================================

## build: Build Wasm + backend + OCI image via Cloud Build
build:
	@echo "Building via Cloud Build (Wasm + backend + OCI image)..."
	$(GCLOUD) builds submit $(REPO_ROOT) \
		--config=cloudbuild.yaml \
		--project=$(PROJECT_ID) \
		--substitutions=_REGION=$(REGION),_ARTIFACT_REPO=$(ARTIFACT_REPO)
	@echo "Build complete. Images pushed to $(REGION)-docker.pkg.dev/$(PROJECT_ID)/$(ARTIFACT_REPO)/"

## build-wasm: Build the Wasm binary locally with Cargo (for development)
build-wasm:
	@if ! which brew >/dev/null 2>&1; then \
		echo "Homebrew not found. Please install Homebrew first."; \
		exit 1; \
	fi
	@if ! brew list rust 2>/dev/null | grep -q rust; then \
		if ! brew list rustup 2>/dev/null | grep -q rust; then \
			echo "Rust not found. Install via Homebrew: brew install rust"; \
			exit 1; \
		fi; \
	fi
	@if ! which cargo >/dev/null 2>&1; then \
		echo "Cargo not found. Ensure Rust installation is complete."; \
		exit 1; \
	fi
	@if ! rustc --version | grep -q "rustc"; then \
		echo "Rust toolchain not found."; \
		exit 1; \
	fi
	@if ! rustup target list --installed | grep -q wasm32-unknown-unknown; then \
		echo "WASM target not installed. Run: rustup target add wasm32-unknown-unknown"; \
		exit 1; \
	fi
	@echo "Building Smart Router Wasm plugin locally..."
	RUSTFLAGS="-C link-arg=-zstack-size=32768 -C panic=abort -C debuginfo=0" $(CARGO) build $(CARGO_OPTS)
	@cp $(WASM_BUILD_DIR)/smart_router.wasm $(WASM_FILE)
	@echo "Built: $(WASM_FILE)"
	@ls -lh $(WASM_FILE)

# =============================================================================
# Test Targets
# =============================================================================

## test: Run unit tests
test:
	@echo "Running tests..."
	$(CARGO) test

## test-cover: Run tests with coverage
test-cover:
	@echo "Running tests with coverage..."
	$(CARGO) tarpaulin --fail-under 80

## test-integration: Run integration tests with Docker
test-integration:
	@./scripts/test.sh --integration

## test-all: Run all tests
test-all:
	@./scripts/test.sh --all

# =============================================================================
# Code Quality Targets
# =============================================================================

## lint: Run clippy linter
lint:
	@echo "Running linter..."
	$(CARGO) clippy --target wasm32-unknown-unknown

## fmt: Format code
fmt:
	@echo "Formatting code..."
	$(CARGO) fmt

## fmt-check: Check code formatting
fmt-check:
	@echo "Checking code formatting..."
	$(CARGO) fmt --check

## vet: Run cargo check
vet:
	@echo "Running cargo check..."
	$(CARGO) check

## check: Run all checks (fmt, clippy, test)
check: fmt-check vet lint test

## tidy: Update dependencies
tidy:
	@echo "Updating dependencies..."
	$(CARGO) update



# =============================================================================
# Deploy Targets
# =============================================================================

## deploy: Deploy to Cloud Run (uses pre-built images from make build)
deploy:
	@./scripts/deploy.sh --skip-build

## deploy-full: Build and deploy in one step
deploy-full:
	@./scripts/deploy.sh

## destroy: Destroy all Demo 2 GCP infrastructure
destroy:
	@./scripts/99-remove.sh --force

## test-live: Test deployed service via Load Balancer (with WASM filter)
test-live:
	@echo "Testing deployed service..."
	@echo ""
	@echo "=========================================="
	@echo "LOAD BALANCER with WASM Smart Router"
	@echo "=========================================="
	@LB_IP=$$($(GCLOUD) compute addresses describe demo2-smart-router-lb-ip \
		--global --format='value(address)' 2>/dev/null || echo ""); \
	if [ -n "$$LB_IP" ]; then \
		echo "Load Balancer IP: $$LB_IP"; \
		echo ""; \
		echo "1. Health check:"; \
		curl -s -k "https://$$LB_IP/health" 2>/dev/null | jq . || echo "  (LB health check failed - is WASM plugin deployed?)"; \
		echo ""; \
		echo "2. Version endpoint (standard user -> v1):"; \
		LB_TIME=$$(curl -s -k -o /tmp/lb_response.txt -w "%{time_total}" -D /tmp/lb_headers.txt "https://$$LB_IP/api/version" 2>/dev/null); \
		cat /tmp/lb_response.txt | jq . 2>/dev/null || cat /tmp/lb_response.txt; \
		echo ""; \
		echo "   ⏱️  Latency: $${LB_TIME}s"; \
		echo ""; \
		echo "3. Version endpoint (beta user -> v2):"; \
		LB_BETA_TIME=$$(curl -s -k -o /tmp/lb_beta_response.txt -w "%{time_total}" \
			-H "User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 17_0)" \
			-H "X-Geo-Country: DE" \
			-H "Cookie: beta-tester=true" \
			-D /tmp/lb_beta_headers.txt "https://$$LB_IP/api/version" 2>/dev/null); \
		cat /tmp/lb_beta_response.txt | jq . 2>/dev/null || cat /tmp/lb_beta_response.txt; \
		echo ""; \
		echo "   ⏱️  Latency: $${LB_BETA_TIME}s"; \
		echo ""; \
		echo "4. Response headers (WASM routing):"; \
		grep -iE "x-route|x-smart" /tmp/lb_beta_headers.txt 2>/dev/null || echo "   (No routing headers found - check WASM plugin logs)"; \
		echo ""; \
		echo "Note: Direct Cloud Run access is blocked (internal-and-cloud-load-balancing ingress)."; \
		echo "All traffic must go through the Load Balancer."; \
	else \
		echo "Load Balancer not found."; \
		echo ""; \
		echo "Run 'make deploy' to deploy the full stack."; \
	fi

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
clean: clean-wasm
	@echo "Clean complete"

## clean-wasm: Clean WASM file and build artifacts
clean-wasm:
	@echo "Cleaning WASM file and build artifacts..."
	rm -f $(WASM_FILE)
	$(CARGO) clean

## size: Show Wasm file size
size: build-wasm
	@echo "Wasm file size:"
	@ls -lh $(WASM_FILE)

## deps: Download dependencies
deps:
	@echo "Downloading dependencies..."
	$(CARGO) fetch

# =============================================================================
# Help
# =============================================================================

## help: Show this help
help:
	@echo "Demo 2: Smart Router (A/B Testing)"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## /  /'

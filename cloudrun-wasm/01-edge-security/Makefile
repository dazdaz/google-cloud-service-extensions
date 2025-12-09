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

## test-all: Run all tests (unit + integration via Cloud Build)
test-all:
	@./scripts/test.sh --all

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
	@./scripts/deploy.sh

## deploy-skip-build: Deploy without rebuilding (use existing image)
deploy-skip-build:
	@./scripts/deploy.sh --skip-build

## test-live: Test deployed Cloud Run service (with authentication)
test-live:
	@echo "Testing deployed service with authentication..."
	@echo ""
	@echo "=========================================="
	@echo "1. CLOUD RUN DIRECT (no WASM filter)"
	@echo "=========================================="
	@SERVICE_URL=$$(gcloud run services describe demo1-edge-security-backend \
		--region=us-central1 --format='value(status.url)' 2>/dev/null) && \
	echo "Service URL: $$SERVICE_URL" && \
	echo "" && \
	echo "Health check:" && \
	curl -s -H "Authorization: Bearer $$(gcloud auth print-identity-token)" "$$SERVICE_URL/health" | jq . && \
	echo "" && \
	echo "User endpoint (PII NOT scrubbed - direct to backend):" && \
	DIRECT_TIME=$$(curl -s -o /tmp/direct_response.json -w "%{time_total}" -H "Authorization: Bearer $$(gcloud auth print-identity-token)" "$$SERVICE_URL/api/user") && \
	cat /tmp/direct_response.json | jq . && \
	echo "" && \
	echo "⏱️  Direct latency: $${DIRECT_TIME}s"
	@echo ""
	@echo "=========================================="
	@echo "2. LOAD BALANCER (with WASM filter)"
	@echo "=========================================="
	@LB_IP=$$(gcloud compute addresses describe demo1-edge-security-lb-ip \
		--global --format='value(address)' 2>/dev/null || echo ""); \
	if [ -n "$$LB_IP" ]; then \
		echo "Load Balancer IP: $$LB_IP"; \
		echo ""; \
		ID_TOKEN=$$(gcloud auth print-identity-token); \
		echo "Health check (via LB):"; \
		curl -s -k -H "Authorization: Bearer $$ID_TOKEN" "https://$$LB_IP/health" 2>/dev/null | jq . || echo "  (LB health check failed - is WASM plugin deployed?)"; \
		echo ""; \
		echo "User endpoint (PII SHOULD be scrubbed by WASM):"; \
		LB_TIME=$$(curl -s -k -H "Authorization: Bearer $$ID_TOKEN" -o /tmp/lb_response.txt -w "%{time_total}" -D /tmp/lb_headers.txt "https://$$LB_IP/api/user" 2>/dev/null); \
		cat /tmp/lb_response.txt | jq . 2>/dev/null || cat /tmp/lb_response.txt; \
		echo ""; \
		echo "⏱️  LB + WASM latency: $${LB_TIME}s"; \
		echo ""; \
		echo "Response headers (WASM indicator):"; \
		grep -i "x-wasm" /tmp/lb_headers.txt 2>/dev/null || echo "  (No WASM headers found)"; \
	else \
		echo "Load Balancer not found."; \
		echo ""; \
		echo "To deploy the Load Balancer with WASM plugin:"; \
		echo "  1. cd infrastructure/gcp"; \
		echo "  2. terraform init && terraform apply"; \
		echo "  3. Deploy WASM plugin (see wasm-plugin.yaml)"; \
	fi

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
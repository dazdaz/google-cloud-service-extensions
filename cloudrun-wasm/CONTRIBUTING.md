# CONTRIBUTING.md - Developer Setup & Guides

This document provides step-by-step guides for setting up your development environment and common development tasks.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
3. [How to Build Each Demo](#how-to-build-each-demo)
4. [How to Test Locally](#how-to-test-locally)
5. [How to Add a New Feature](#how-to-add-a-new-feature)
6. [How to Create a New Branch](#how-to-create-a-new-branch)
7. [Critical Data Flows](#critical-data-flows)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools

| Tool | Version | Purpose | Installation |
|------|---------|---------|--------------|
| Rust | 1.75+ | Demo 1 development | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh` |
| wasm32 target | - | Rust Wasm compilation | `rustup target add wasm32-unknown-unknown` |
| TinyGo | 0.30+ | Demo 2 development | [tinygo.org/getting-started](https://tinygo.org/getting-started/) |
| Go | 1.21+ | TinyGo dependency | [go.dev/dl](https://go.dev/dl/) |
| Make | 3.8+ | Build automation | Pre-installed on macOS/Linux |
| curl | 7+ | API testing | Pre-installed on macOS/Linux |

### Verify Installation

```bash
# Run the verification script
./scripts/setup-dev.sh --verify

# Or manually check:
rustc --version          # rustc 1.75.0 or higher
rustup target list --installed | grep wasm32  # wasm32-unknown-unknown
tinygo version           # tinygo version 0.30.0
go version               # go version go1.21.x
```

---

## Initial Setup

### Step 1: Clone the Repository

```bash
git clone https://github.com/yourorg/cloudrun-wasm.git
cd cloudrun-wasm
```

### Step 2: Run Setup Script

```bash
# This installs git hooks and verifies tools
./scripts/setup-dev.sh
```

### Step 3: Build All Demos

```bash
make all
```

### Step 4: Verify Setup

```bash
# Test Demo 1 (should return redacted data)
curl http://localhost:10000/api/user

# Test Demo 2 (should route based on headers)
curl -H "Cookie: beta-tester=true" http://localhost:10001/api/version
```

---

## How to Build Each Demo

### Demo 1: Edge Security (Rust/proxy-wasm)

```bash
cd 01-edge-security

# Build the Wasm binary
make build

# Output: target/wasm32-unknown-unknown/release/edge_security.wasm

# Run tests
make test
```

**Build Details:**
```bash
# Manual build command
cargo build --target wasm32-unknown-unknown --release

# The Wasm file will be ~50-100KB
ls -lh target/wasm32-unknown-unknown/release/*.wasm
```

### Demo 2: Smart Router (TinyGo/proxy-wasm)

```bash
cd 02-smart-router

# Build with TinyGo
make build

# Output: smart_router.wasm

# Run tests
make test
```

**Build Details:**
```bash
# Manual build command
tinygo build -o smart_router.wasm -scheduler=none -target=wasi ./main.go

# The Wasm file will be ~100-200KB
ls -lh smart_router.wasm
```

### Cloud Run Backend

```bash
cd infrastructure/backend

# Build Docker image
docker build -t mock-backend .

# Run locally
docker run -p 8080:8080 mock-backend

# Test endpoints
curl http://localhost:8080/api/user
curl http://localhost:8080/v1/api/version
curl http://localhost:8080/v2/api/version
```

---

## How to Test Locally

### Testing Demo 1: PII Scrubbing

```bash
# Test with a response containing PII (deployed on Cloud Run)
curl http://localhost:10000/api/user

# Expected: SSN and credit card numbers are redacted
# Actual output example:
# {
#   "name": "John Doe",
#   "ssn": "XXX-XX-XXXX",
#   "card": "XXXX-XXXX-XXXX-1111"
# }

# Test with clean data (should pass through unchanged)
curl http://localhost:10000/api/user-clean
```

### Testing Demo 2: Smart Routing

```bash
# Test: Standard user -> routes to v1 (deployed on Cloud Run)
curl http://localhost:10001/api/version
# Expected: {"version": "v1"}

# Test: Beta user -> routes to v2
curl -H "User-Agent: iPhone/17.0" \
     -H "X-Geo-Country: DE" \
     -H "Cookie: beta-tester=true" \
     http://localhost:10001/api/version
# Expected: {"version": "v2-beta"}

# Test: Partial match -> still v1
curl -H "User-Agent: iPhone/17.0" \
     http://localhost:10001/api/version
# Expected: {"version": "v1"}
```

### Running Unit Tests

```bash
# All demos
make test

# Individual demos
cd 01-edge-security && make all
cd 02-smart-router && make all
```

---

## How to Add a New Feature

### Adding a New PII Pattern (Demo 1)

1. **Open the patterns file:**
   ```bash
   code 01-edge-security/src/patterns.rs
   ```

2. **Add the new pattern:**
   ```rust
   // In patterns.rs
   pub const PATTERNS: &[(&str, &str)] = &[
       (r"\d{4}-\d{4}-\d{4}-\d{4}", "XXXX-XXXX-XXXX-XXXX"),  // Credit Card
       (r"\d{3}-\d{2}-\d{4}", "XXX-XX-XXXX"),                  // SSN
       (r"NEW_PATTERN_HERE", "REPLACEMENT"),                   // Your new pattern
   ];
   ```

3. **Add a test:**
   ```rust
   #[test]
   fn test_new_pattern() {
       let input = b"sensitive: NEW_DATA";
       let result = redact_pii(input).unwrap();
       assert!(result.contains(b"REPLACEMENT"));
   }
   ```

4. **Build and test:**
   ```bash
   make build test
   ```

### Adding a New Routing Rule (Demo 2)

1. **Open the router:**
   ```bash
   code 02-smart-router/router/router.go
   ```

2. **Add new rule:**
   ```go
   func DetermineRoute(headers map[string]string) string {
       // Existing rules...
       
       // New rule: VIP users always get v2
       if strings.Contains(headers["Cookie"], "vip=true") {
           return "v2"
       }
       
       return "v1"
   }
   ```

3. **Add test:**
   ```go
   func TestRoutesVIPUser(t *testing.T) {
       headers := map[string]string{
           "Cookie": "session=abc; vip=true",
       }
       result := DetermineRoute(headers)
       if result != "v2" {
           t.Errorf("Expected v2 for VIP, got %s", result)
       }
   }
   ```

### Adding a New Backend Endpoint

1. **Open the Flask app:**
   ```bash
   code infrastructure/backend/app.py
   ```

2. **Add new endpoint:**
   ```python
   @app.route('/api/new-endpoint')
   def new_endpoint():
       return jsonify({
           "message": "New endpoint response",
           "timestamp": datetime.now().isoformat()
       })
   ```

3. **Deploy and test:**
   ```bash
   # Deploy to Cloud Run
   cd infrastructure/backend
   make deploy
   
   # Test the endpoint
   curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
     https://YOUR-SERVICE-URL.run.app/api/new-endpoint
   ```

---

## How to Create a New Branch

### Standard Feature Branch

```bash
# Ensure you're on main and up to date
git checkout main
git pull origin main

# Create feature branch
git checkout -b feature/demo1-add-email-redaction

# Make your changes
# ...

# Stage and commit
git add .
git commit -m "feat(demo1): add email address redaction pattern

Adds regex pattern to detect and redact email addresses
in response bodies.

Closes #15"

# Push and create PR
git push -u origin feature/demo1-add-email-redaction
```

### Hotfix Branch

```bash
git checkout main
git pull origin main
git checkout -b fix/demo2-cookie-parsing

# Make fix
# ...

git commit -m "fix(demo2): handle URL-encoded cookie values"
git push -u origin fix/demo2-cookie-parsing
```

---

## Critical Data Flows

### Request Flow Through Both Demos

```
┌───────────────┐
│    Client     │
└───────┬───────┘
        │ HTTP Request
        ▼
┌───────────────────────────────────────┐
│           Envoy Proxy                 │
│  ┌─────────────────────────────────┐  │
│  │      Wasm VM (Demo 2)           │  │
│  │  ┌───────────────────────────┐  │  │
│  │  │  Smart Router             │  │  │
│  │  │                           │  │  │
│  │  │  on_request_headers()     │◄─┼──┼── Check headers/cookies
│  │  │  -> Route to v1 or v2     │  │  │
│  │  │                           │  │  │
│  │  └───────────────────────────┘  │  │
│  └─────────────────────────────────┘  │
│                  │                    │
│                  ▼                    │
│  ┌─────────────────────────────────┐  │
│  │      Cloud Run Backend          │  │
│  │      (Flask - v1 or v2)         │  │
│  └─────────────────────────────────┘  │
│                  │                    │
│                  ▼                    │
│  ┌─────────────────────────────────┐  │
│  │      Wasm VM (Demo 1)           │  │
│  │  ┌───────────────────────────┐  │  │
│  │  │  PII Scrubbing            │  │  │
│  │  │                           │  │  │
│  │  │  on_response_body()       │◄─┼──┼── Scan for PII
│  │  │  -> Redact sensitive      │  │  │
│  │  │                           │  │  │
│  │  └───────────────────────────┘  │  │
│  └─────────────────────────────────┘  │
│                  │                    │
└──────────────────┼────────────────────┘
                   │
                   ▼
            ┌───────────────┐
            │    Client     │
            │   (clean!)    │
            └───────────────┘
```

---

## Troubleshooting

### Common Issues

#### "wasm32-unknown-unknown target not found"

```bash
# Solution: Add the target
rustup target add wasm32-unknown-unknown
```

#### "Envoy fails to load Wasm plugin"

```bash
# Check GCP Service Extensions logs
gcloud logging read 'resource.type="networkservices.googleapis.com/WasmPluginVersion"' \
  --limit=20 --format='table(timestamp,severity,jsonPayload.message)'

# Common causes:
# 1. Wasm file not properly uploaded to GCS
# 2. Wasm file compiled for wrong target
# 3. proxy-wasm ABI version mismatch

# Solution: Rebuild with correct target
cargo build --target wasm32-unknown-unknown --release
```

#### "TinyGo: package not found"

```bash
# Ensure GOPATH is set
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin

# Install proxy-wasm SDK
go get github.com/tetratelabs/proxy-wasm-go-sdk
```

#### "Backend not responding"

```bash
# Check Cloud Run logs
gcloud run services logs read BACKEND-SERVICE-NAME --limit=50

# Verify backend is running
gcloud run services describe BACKEND-SERVICE-NAME

# Check service health
curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  https://YOUR-SERVICE-URL.run.app/health
```

#### "Tests pass locally but fail in CI"

```bash
# Ensure you're using the same Rust version
rustup override set 1.75.0

# Clean and rebuild
cargo clean
cargo build --release
cargo test
```

### Getting Help

1. Check the [Troubleshooting](#troubleshooting) section above
2. Search existing GitHub issues
3. Create a new issue with:
   - OS and version
   - Tool versions (`./scripts/setup-dev.sh --verify`)
   - Full error message
   - Steps to reproduce

---

## IDE Setup

### VS Code Extensions

Recommended extensions for this project:

```json
{
  "recommendations": [
    "rust-lang.rust-analyzer",
    "golang.go",
    "serayuzgur.crates",
    "tamasfe.even-better-toml",
    "ms-azuretools.vscode-docker",
    "ms-python.python"
  ]
}
```

### Workspace Settings

`.vscode/settings.json`:
```json
{
  "rust-analyzer.cargo.target": "wasm32-unknown-unknown",
  "rust-analyzer.checkOnSave.command": "clippy",
  "go.lintTool": "golangci-lint",
  "editor.formatOnSave": true,
  "python.linting.enabled": true
}
# TODO.md - Implementation Checklist

This file tracks all implementation tasks for the GCP WASM demos. 

## ✅ Implementation Complete!

All tasks have been implemented. See the summary below.

---

## Task Labels

| Label | Domain | Description |
|-------|--------|-------------|
| `b#` | Backend | All server-side: Wasm plugins (Service Extensions), Cloud Run, Infrastructure |
| `d#` | Documentation | README updates, comments, API docs |

---

## 🏗️ Architecture Overview

Both demos use **GCP Service Extensions** (Wasm in Load Balancer) + **Cloud Run** (Backend).

```
┌────────────────────────────────────────────────────────────────────────────┐
│                              EDGE (Load Balancer)                          │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │              Google Cloud Application Load Balancer                  │  │
│  │  ┌────────────────────────────────────────────────────────────────┐  │  │
│  │  │              Service Extensions (Wasm Sandbox)                 │  │  │
│  │  │                                                                │  │  │
│  │  │   REQUEST PATH ──►  Demo 2: Smart Router (b#)                  │  │  │
│  │  │                     - Header inspection                        │  │  │
│  │  │                     - A/B test routing                         │  │  │
│  │  │                     - Canary deployments                       │  │  │
│  │  │                                                                │  │  │
│  │  │   RESPONSE PATH ◄── Demo 1: PII Scrubbing (b#)                 │  │  │
│  │  │                     - Body scanning                            │  │  │
│  │  │                     - Credit card redaction                    │  │  │
│  │  │                     - SSN/Email masking                        │  │  │
│  │  └────────────────────────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                     │                                      │
│                                     ▼                                      │
└────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      │ HTTP/gRPC
                                      ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                           BACKEND (Cloud Run)                              │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                    Cloud Run Service (b#)                            │  │
│  │                                                                      │  │
│  │   - Receives traffic from Load Balancer                              │  │
│  │   - Returns JSON responses (may contain PII for Demo 1)              │  │
│  │   - Hosts v1 and v2 versions for A/B testing (Demo 2)                │  │
│  │                                                                      │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## 🔐 Demo 1: Edge Security (PII Scrubbing)

> **Location**: EDGE - GCP Load Balancer via Service Extensions
> **Language**: Rust + proxy-wasm SDK
> **Extension Point**: Response Path (`on_http_response_body`)
> **Cloud Run**: Returns user data with PII; Wasm scrubs it before reaching client

| ID | Status | Task | Notes |
|----|--------|------|-------|
| b1 | [x] | Create Cargo.toml with proxy-wasm-rust-sdk dependency | `01-edge-security/Cargo.toml` |
| b2 | [x] | Implement `RootContext` for plugin initialization | `01-edge-security/src/lib.rs` |
| b3 | [x] | Implement `HttpContext` for request handling | `01-edge-security/src/lib.rs` |
| b4 | [x] | Create PII pattern regex engine | `01-edge-security/src/patterns.rs` |
| b5 | [x] | Implement body scanning and redaction | `01-edge-security/src/lib.rs` |
| b6 | [x] | Add `X-PII-Redacted` response header | `01-edge-security/src/lib.rs` |
| b7 | [x] | Write unit tests for each PII pattern | `01-edge-security/src/patterns.rs` |
| b8 | [x] | Create demo-specific README.md | `01-edge-security/README.md` |

---

## 🔀 Demo 2: Smart Router (A/B Testing & Canary)

> **Location**: EDGE - GCP Load Balancer via Service Extensions
> **Language**: TinyGo + proxy-wasm-go-sdk
> **Extension Point**: Request Path (`on_http_request_headers`)
> **Cloud Run**: Hosts v1 and v2 backend versions; Wasm routes traffic

| ID | Status | Task | Notes |
|----|--------|------|-------|
| b9 | [x] | Create go.mod with proxy-wasm-go-sdk dependency | `02-smart-router/go.mod` |
| b10 | [x] | Define RoutingRule and Condition structs | `02-smart-router/router/types.go` |
| b11 | [x] | Implement `pluginContext` for initialization | `02-smart-router/main.go` |
| b12 | [x] | Implement `httpContext` for request handling | `02-smart-router/main.go` |
| b13 | [x] | Create header inspection logic | `02-smart-router/router/router.go` |
| b14 | [x] | Implement cookie parsing utility | `02-smart-router/router/cookie.go` |
| b15 | [x] | Add routing decision logic | `02-smart-router/router/router.go` |
| b16 | [x] | Set `X-Routed-By` and `X-Route-Reason` headers | `02-smart-router/main.go` |
| b17 | [x] | Write unit tests for routing rules | `02-smart-router/router/router_test.go` |
| b18 | [x] | Create demo-specific README.md | `02-smart-router/README.md` |

---

## ☁️ Cloud Run Backend

> Shared backend service for both demos

| ID | Status | Task | Notes |
|----|--------|------|-------|
| b19 | [x] | Create mock backend server (Python/Flask) | `infrastructure/backend/app.py` |
| b20 | [x] | Add endpoint returning PII data for Demo 1 | `/api/user`, `/api/user-clean` |
| b21 | [x] | Add versioned endpoints for Demo 2 A/B testing | `/v1/api/version`, `/v2/api/version` |
| b22 | [x] | Create Dockerfile for backend | `infrastructure/backend/Dockerfile` |
| b23 | [x] | Create Cloud Run deployment config | `infrastructure/backend/service.yaml` |
| b24 | [x] | Add health check endpoint | `/health` |
| b25 | [x] | Create backend-specific README.md | `infrastructure/backend/README.md` |

---

## 🏗️ Infrastructure

> Shared infrastructure for local development and GCP deployment

### Local Development (Envoy)

| ID | Status | Task | Notes |
|----|--------|------|-------|
| b26 | [x] | Create base Envoy configuration | `infrastructure/envoy/envoy.yaml` |
| b27 | [x] | Create Envoy config for Demo 1 | `infrastructure/envoy/envoy-demo1.yaml` |
| b28 | [x] | Create Envoy config for Demo 2 | `infrastructure/envoy/envoy-demo2.yaml` |
| b29 | [x] | Create Dockerfile for Envoy | `infrastructure/docker/Dockerfile.envoy` |

### Build & Test Scripts

| ID | Status | Task | Notes |
|----|--------|------|-------|
| b31 | [x] | Create root Makefile | `Makefile` |
| b32 | [x] | Create setup-dev.sh script | `scripts/setup-dev.sh` |
| b33 | [x] | Create build-all.sh script | `scripts/build-all.sh` |
| b34 | [x] | Create test-all.sh script | `scripts/test-all.sh` |

### GCP Deployment

| ID | Status | Task | Notes |
|----|--------|------|-------|
| b35 | [x] | Create GCP Load Balancer config | `infrastructure/gcp/load-balancer.tf` |
| b36 | [x] | Create WasmPlugin resource for Demo 1 | `infrastructure/gcp/wasm-plugin-demo1.yaml` |
| b37 | [x] | Create WasmPlugin resource for Demo 2 | `infrastructure/gcp/wasm-plugin-demo2.yaml` |
| b38 | [x] | Create deployment script for Cloud Run | `scripts/deploy-cloudrun.sh` |

---

## 📝 Documentation Updates

| ID | Status | Task | Notes |
|----|--------|------|-------|
| d1 | [x] | Create PROJECT_OVERVIEW.md | Architecture diagrams |
| d2 | [x] | Create CODE_PRINCIPLES.md | Coding standards |
| d3 | [x] | Create CONTRIBUTING.md | Developer guides |
| d4 | [x] | Create DATA_STRUCTURES.md | Schemas and fixtures |
| d5 | [x] | Create README.md | Quick start |
| d6 | [x] | Create TODO.md | This file |
| d7 | [x] | Add .vscode/settings.json | `.vscode/settings.json` |
| d8 | [x] | Add .gitignore | `.gitignore` |
| d9 | [x] | Update README after implementation | Updated with actual file paths |

---

## 📊 Summary

### By Domain

| Domain | Label | Total | Done | Remaining |
|--------|-------|-------|------|-----------|
| Backend | b# | 38 | 38 | 0 |
| Documentation | d# | 9 | 9 | 0 |
| **Total** | | **47** | **47** | **0** |

### ✅ All Tasks Complete!

---

## 🎯 How Cloud Run Fits In

| Demo | Wasm Location | Cloud Run Role |
|------|---------------|----------------|
| **Demo 1** | Response Path (LB) | Returns user data with PII; Wasm scrubs before client receives |
| **Demo 2** | Request Path (LB) | Hosts v1 & v2; Wasm routes based on user attributes |

### Traffic Flow

```
Client Request
      │
      ▼
┌─────────────────────┐
│   Load Balancer     │  ◄── EDGE
│   (Service Ext.)    │
│                     │
│   Demo 2: Router    │  ◄── Wasm decides which backend version
│   (request path)    │
└─────────────────────┘
      │
      ▼
┌─────────────────────┐
│    Cloud Run        │  ◄── BACKEND (Shared)
│    (b19-b25)        │
│                     │
│   v1 or v2 API      │
│   Returns JSON      │
└─────────────────────┘
      │
      ▼
┌─────────────────────┐
│   Load Balancer     │  ◄── EDGE
│   (Service Ext.)    │
│                     │
│   Demo 1: PII       │  ◄── Wasm scrubs sensitive data
│   (response path)   │
└─────────────────────┘
      │
      ▼
Client Response (sanitized)
```

---

## 🚀 Getting Started

```bash
# Verify tools
./scripts/setup-dev.sh --verify

# Build all demos
make build

# Start local environment
make docker-up

# Test Demo 1: PII Scrubbing
curl http://localhost:10000/api/user

# Test Demo 2: Smart Routing
curl -H "Cookie: beta-tester=true" \
     -H "User-Agent: iPhone" \
     -H "X-Geo-Country: DE" \
     http://localhost:10001/api/version

# Stop environment
scripts/99clean.sh

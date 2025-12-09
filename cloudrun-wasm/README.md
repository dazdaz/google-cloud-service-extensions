# GCP WASM Service Extensions Demos

Two demonstration projects showcasing WebAssembly (Wasm) with **GCP Service Extensions** for edge computing on Google Cloud Application Load Balancer.

[![Rust](https://img.shields.io/badge/Rust-1.75+-orange.svg)](https://www.rust-lang.org/)
[![TinyGo](https://img.shields.io/badge/TinyGo-0.30+-blue.svg)](https://tinygo.org/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## 🎯 What's Inside

| Demo | Description | Language | Location |
|------|-------------|----------|----------|
| [**01-Edge Security**](01-edge-security/) | PII/PCI data scrubbing at the edge | Rust | Load Balancer (Service Extensions) |
| [**02-Smart Router**](02-smart-router/) | A/B testing & canary routing | Rust | Load Balancer (Service Extensions) |

---

## 🏗️ Architecture Overview

Both demos use **GCP Service Extensions** to run Wasm plugins inside the Load Balancer, with **Cloud Run** as the backend service.

```
┌──────────────────────────────────────────────────────────────────────────┐
│                       GCP Application Load Balancer                      │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │                  Service Extensions (Wasm Sandbox)                 │  │
│  │                                                                    │  │
│  │   REQUEST PATH:   Demo 2 - Smart Router                            │  │
│  │                   • Inspect headers/cookies                        │  │
│  │                   • Route to v1 or v2 backend                      │  │
│  │                                                                    │  │
│  │   RESPONSE PATH:  Demo 1 - PII Scrubbing                           │  │
│  │                   • Scan response body                             │  │
│  │                   • Redact credit cards, SSN, emails               │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                     │                                    │
└─────────────────────────────────────┼────────────────────────────────────┘
                                      │
                                      ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                            Cloud Run Backend                             │
│                                                                          │
│   • Receives traffic from Load Balancer (after Wasm processing)          │
│   • Returns JSON responses (may contain PII for Demo 1 testing)          │
│   • Hosts v1 and v2 versions for A/B testing (Demo 2)                    │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

### How Cloud Run Fits In

| Demo | Cloud Run Role |
|------|----------------|
| **Demo 1: PII Scrubbing** | Returns user data with PII (SSN, credit cards). Wasm scrubs it on the way out. |
| **Demo 2: Smart Router** | Hosts multiple versions (v1, v2). Wasm routes traffic based on user attributes. |

---

## 🚀 Quick Start

### Prerequisites

```bash
# Manually install on macOS:
brew install rust rustup

# Setup Rust for Wasm
rustup-init
rustup target add wasm32-unknown-unknown
```

### Build & Run All Demos

```bash
# Clone the repository
git clone https://github.com/yourorg/cloudrun-wasm.git
cd cloudrun-wasm

# Build all demos
make build

# Deploy to Cloud Run
make deploy

# Alternatively
cd 01-edge-security && make all
cd 02-smart-router && make all

# Test Demo 1: PII Scrubbing (via Load Balancer)
curl -k https://YOUR-LB-IP/api/user
# Output: SSN and credit cards are redacted!

# Test Demo 2: Smart Routing (via Load Balancer)
curl -k \
     -H "Cookie: beta-tester=true" \
     -H "User-Agent: iPhone" \
     -H "X-Geo-Country: DE" \
     https://YOUR-LB-IP/api/version
# Output: Routed to v2-beta!
```

---

## 📖 Documentation

| Document | Description |
|----------|-------------|
| [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md) | Architecture diagrams & design decisions |
| [CODE_PRINCIPLES.md](CODE_PRINCIPLES.md) | Coding standards & style guide |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Setup guides & how-to instructions |
| [DATA_STRUCTURES.md](DATA_STRUCTURES.md) | Type definitions & test fixtures |
| [TODO.md](TODO.md) | Implementation checklist |

---

## 📁 Project Structure

```
cloudrun-wasm/
├── 01-edge-security/               # Demo 1: PII Scrubbing (Rust)
│   ├── src/lib.rs                  # Main plugin logic
│   ├── src/patterns.rs             # PII regex patterns
│   ├── Cargo.toml                  # Rust dependencies
│   ├── Makefile                    # Build automation
│   └── README.md                   # Demo documentation
│
├── 02-smart-router/                # Demo 2: A/B Testing (Rust)
│   ├── src/lib.rs                  # Main plugin logic
│   ├── Cargo.toml                  # Rust dependencies
│   ├── Makefile                    # Build automation
│   └── README.md                   # Demo documentation
│
├── infrastructure/
│   ├── envoy/                      # Envoy configurations
│   │   ├── envoy.yaml              # Base config
│   │   ├── envoy-demo1.yaml        # Demo 1 (response filter)
│   │   └── envoy-demo2.yaml        # Demo 2 (request filter)
│   │
│   ├── docker/                     # Docker files
│   │   └── Dockerfile.envoy        # Envoy with Wasm
│   │
│   ├── backend/                    # Cloud Run backend
│   │   ├── app.py                  # Flask API server
│   │   ├── Dockerfile              # Python container
│   │   ├── service.yaml            # Cloud Run config
│   │   └── README.md               # API docs
│   │
│   └── gcp/                        # GCP deployment
│       ├── load-balancer.tf        # Terraform config
│       ├── wasm-plugin-demo1.yaml  # Demo 1 WasmPlugin
│       └── wasm-plugin-demo2.yaml  # Demo 2 WasmPlugin
│
├── scripts/
│   ├── setup-dev.sh                # Dev environment setup
│   ├── build-all.sh                # Build all Wasm modules
│   ├── test-all.sh                 # Run all tests
│   └── deploy-cloudrun.sh          # Deploy to GCP
│
├── .vscode/                        # VS Code configuration
│   ├── settings.json               # Workspace settings
│   └── extensions.json             # Recommended extensions
│
├── Makefile                        # Root build automation
├── .gitignore                      # Git ignore rules
└── *.md                            # Documentation files
```

---

## 🔧 Why Wasm at the Edge?

| Benefit | Description |
|---------|-------------|
| **🔒 Secure** | Sandboxed execution - plugins can't crash the host |
| **⚡ Fast** | Microsecond latency, no network hop to external service |
| **🌍 Portable** | Write once, run on Envoy (local) or GCP LB (production) |
| **🔧 Flexible** | Modify requests/responses without backend code changes |

---

## 🦀 Why Rust Over Go for Wasm at the Edge?

In the context of server-side WebAssembly (Wasm) at the edge (e.g., using runtimes like Wasmtime, Wasmer, or WasmEdge on platforms such as Fastly Compute@Edge, Cloudflare Workers, or custom load balancers), **Rust is generally faster than Go**. This stems from Rust's zero-cost abstractions, lack of garbage collection (GC), and more mature Wasm compilation via LLVM, which produce smaller, more efficient binaries. Go's Wasm support, while functional, includes a full runtime (GC and scheduler), leading to larger binaries (often 2-10x bigger) and higher overhead, especially for compute-intensive tasks.

### Performance Comparison

Performance differences vary by workload:

- **Startup time**: Go is slower due to runtime initialization
- **Execution speed**: Rust edges out by 20-50% on average for CPU-bound tasks, but can be 5-10x faster in GC-heavy or memory-intensive scenarios
- **Memory usage**: Rust uses 30-70% less memory, reducing edge resource costs
- **Real-world edge impact**: In benchmarks on edge runtimes, Rust achieves near-native speeds (1.5-3x faster than JS), while Go lags due to GC pauses

### Key Benchmarks

| Benchmark/Source | Task/Workload | Rust Wasm Time | Go Wasm Time | Rust Advantage | Runtime/Notes |
|------------------|---------------|----------------|--------------|----------------|---------------|
| Ecostack (2022, Edge browser sim) | Array sorting (1M elements) | ~6,200 ms | ~9,500 ms | ~53% faster (1.53x speedup) | Browser-like edge; Rust leads in all browsers tested |
| Karn Wong (2024, server-side Wasm) | Mixed compute (loops, math) | ~1.05x native | ~14.17x native (1317% slower) | 13x faster relative to native | Wasmtime/Wasmer; Go's GC causes massive overhead |
| ReliaSoftware (2025, general Wasm) | Algorithms (n-body, spectral-norm) | Baseline | N/A | 30%+ faster | Benchmarks Game; Rust consistently 1.3x+ ahead |
| Markaicode (2025, microservices/edge) | HTTP handling + DB ops | ~15-20% higher throughput | Baseline | 15-20% faster | Edge sim (Wasmtime); Rust slight edge in I/O |

### Why Rust is Faster in Wasm Edge Scenarios

1. **No GC Overhead**: Go's GC (even in TinyGo) introduces pauses and allocations, amplified in Wasm's sandboxed environment. Rust's ownership model avoids this, enabling tighter loops and lower latency (<1ms vs. Go's 5-50ms pauses).

2. **Binary Size & Cold Starts**: Rust Wasm modules are ~100-500 KB; Go's are 1-10 MB, leading to slower edge deploys and instantiation (e.g., 100-500ms for Go vs. <50ms for Rust in Wasmtime).

3. **Runtime Compatibility**: Edge platforms like Fastly use Wasmtime (Rust-native), optimizing Rust better. Go performs worse in Cranelift/LLVM backends due to runtime bloat.

4. **Edge-Specific Gains**: In latency-sensitive edge computing (e.g., auth or personalization), Rust reduces TTFB by 20-40%.

### When Go Might Close the Gap

- **I/O-Bound Tasks**: Go's goroutines shine for concurrent networking; Rust needs async crates (e.g., Tokio), but still wins on raw speed.
- **Development Speed**: Go compiles faster to Wasm (~2x quicker builds), but runtime perf suffers.
- **Use TinyGo**: Reduces Go's binary size by 80% and overhead by ~50%, narrowing the gap to 2-3x vs. Rust.

**For your use case (e.g., LB extensions), start with Rust for perf-critical logic.**

---

## 📊 Use Cases

### Demo 1: Edge Security (PII Scrubbing)
> "Scrub sensitive data before it leaves your network"

**Problem**: Backend returns user data that might contain PII. You need to ensure it never reaches the client.

**Solution**: Wasm plugin scans response body and redacts:
- Credit card numbers → `XXXX-XXXX-XXXX-1234`
- SSNs → `XXX-XX-XXXX`
- Email addresses → `[EMAIL REDACTED]`

### Demo 2: Smart Router (A/B Testing)
> "Route traffic at the edge, not in your app"

**Problem**: You want to send specific users (iPhone + Germany + beta flag) to a new backend version.

**Solution**: Wasm plugin inspects request headers and routes to:
- `v1` backend for standard users
- `v2` backend for beta testers matching criteria

---

## 🧪 Testing

```bash
# Run all tests
make test

# Individual demos
cd 01-edge-security && make all
cd 02-smart-router && make all

# Integration tests with Envoy
make integration-test

# Run all tests via script
./scripts/test-all.sh
```

---

## 🔧 Development

### Make Commands

```bash
make build            # Build all Wasm modules
make test             # Run all tests
make clean            # Clean build artifacts
make lint             # Run linters
make deploy           # Deploy to GCP (requires auth)
```

### Demo-specific Commands

```bash
# Demo 1: Edge Security
cd 01-edge-security
make build            # Build Wasm
make test             # Run tests
make deploy           # Deploy to Cloud Run

# Demo 2: Smart Router
cd 02-smart-router
make build            # Build Wasm
make test             # Run tests
make deploy           # Deploy to Cloud Run
```

---

## 🚀 GCP Deployment

### Prerequisites
- GCP Project with billing enabled
- `gcloud` CLI authenticated
- Artifact Registry enabled

### Deploy

```bash
# Deploy backend to Cloud Run
./scripts/deploy-cloudrun.sh

# Apply Terraform for Load Balancer
cd infrastructure/gcp
terraform init
terraform apply

# Deploy Wasm plugins
gcloud service-extensions wasm-plugins create demo1-pii \
  --config-file=wasm-plugin-demo1.yaml

gcloud service-extensions wasm-plugins create demo2-router \
  --config-file=wasm-plugin-demo2.yaml
```

---

## 📚 Learn More

- [Proxy-Wasm Specification](https://github.com/proxy-wasm/spec)
- [GCP Service Extensions](https://cloud.google.com/service-extensions/docs)
- [Envoy Wasm Filters](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/wasm_filter)
- [proxy-wasm-rust-sdk](https://github.com/proxy-wasm/proxy-wasm-rust-sdk)
- [proxy-wasm-go-sdk](https://github.com/tetratelabs/proxy-wasm-go-sdk)

---

## 📄 License

MIT License - See [LICENSE](LICENSE) for details.

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'feat: add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

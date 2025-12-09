# CODE_PRINCIPLES.md - Global Coding Standards

This document defines the foundational rules that apply to all code in this repository.

---

## Table of Contents

1. [Language Standards](#language-standards)
2. [Git Workflow](#git-workflow)
3. [Code Style](#code-style)
4. [Documentation](#documentation)
5. [Testing](#testing)
6. [Security](#security)
7. [Performance](#performance)

---

## Language Standards

### Rust (Demo 1: Edge Security)

| Rule | Standard |
|------|----------|
| Edition | Rust 2021 |
| MSRV | 1.75.0 |
| Formatting | `rustfmt` with default settings |
| Linting | `clippy` with `#![deny(clippy::all)]` |
| Error Handling | Use `Result<T, E>` - avoid `unwrap()` in production code |
| Memory | Zero unsafe blocks unless absolutely necessary and documented |

**Cargo.toml Requirements:**
```toml
[package]
edition = "2021"
rust-version = "1.75"

[lints.rust]
unsafe_code = "deny"

[lints.clippy]
all = "deny"
pedantic = "warn"
```

### TinyGo (Demo 2: Smart Router)

| Rule | Standard |
|------|----------|
| Version | TinyGo 0.30+ |
| Target | `wasm` or `wasi` |
| Formatting | `gofmt` |
| Linting | `golangci-lint` |
| Error Handling | Always check and handle errors |

**go.mod Requirements:**
```go
module github.com/yourorg/demo-smart-router

go 1.21
```

### Python (Cloud Run Backend)

| Rule | Standard |
|------|----------|
| Version | Python 3.11+ |
| Formatting | `black` with default settings |
| Linting | `ruff` or `flake8` |
| Type Hints | Required for function signatures |
| Framework | Flask 3.0+ |

**requirements.txt Requirements:**
```
flask>=3.0.0
gunicorn>=21.0.0
```

---

## Git Workflow

### Branch Naming

```
<type>/<short-description>

Types:
- feature/   New functionality
- fix/       Bug fixes
- docs/      Documentation only
- refactor/  Code restructuring
- test/      Test additions/modifications
- infra/     Infrastructure changes
```

**Examples:**
- `feature/demo1-ssn-detection`
- `fix/demo2-cookie-parsing`
- `docs/contributing-setup-guide`

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:** `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`

**Examples:**
```
feat(demo1): add SSN pattern detection

Implements regex-based Social Security Number detection
in the response body scanner.

Closes #42
```

```
fix(demo2): correct cookie parsing for beta flag

The previous regex was not handling URL-encoded cookies.
```

### Pull Request Process

1. Create feature branch from `main`
2. Make changes with atomic commits
3. Run `make test` locally
4. Open PR with description template
5. Wait for CI to pass
6. Request review
7. Squash and merge

---

## Code Style

### General Principles

1. **Clarity over Cleverness** - Write code that is easy to read
2. **DRY but not WET** - Don't repeat yourself, but don't over-abstract prematurely
3. **Single Responsibility** - Each function/module does one thing well
4. **Explicit is Better** - Avoid magic; make behavior obvious

### Naming Conventions

| Element | Rust | Go | Python |
|---------|------|-----|--------|
| Functions | `snake_case` | `camelCase` | `snake_case` |
| Constants | `SCREAMING_SNAKE` | `SCREAMING_SNAKE` | `SCREAMING_SNAKE` |
| Types/Structs | `PascalCase` | `PascalCase` | `PascalCase` |
| Variables | `snake_case` | `camelCase` | `snake_case` |
| Files | `snake_case.rs` | `snake_case.go` | `snake_case.py` |

### Comments Policy

**DO Comment:**
- Why something is done (not what)
- Complex algorithms
- Non-obvious side effects
- Public API documentation
- TODO/FIXME with issue reference

**DON'T Comment:**
- Obvious code (`// increment counter` before `counter++`)
- Commented-out code (delete it, use git history)
- Self-explanatory functions

**Example (Rust):**
```rust
/// Scans the response body for PII patterns and redacts them.
/// 
/// # Arguments
/// * `body` - The HTTP response body as bytes
/// 
/// # Returns
/// The sanitized body with PII replaced by placeholder text
/// 
/// # Note
/// This function allocates a new String. For high-throughput
/// scenarios, consider using the streaming variant.
pub fn redact_pii(body: &[u8]) -> Result<Vec<u8>, Error> {
    // We use a lazy static regex to avoid recompilation on each call.
    // This is critical for microsecond-level performance in the data path.
    // ...
}
```

---

## Documentation

### Required Documentation

| File | Purpose | Location |
|------|---------|----------|
| `README.md` | Quick start, what this is | Each demo root |
| `CHANGELOG.md` | Version history | Repository root |
| Inline docs | API documentation | Source files |

### README Structure

Each demo README must include:

```markdown
# Demo Name

One-line description.

## Quick Start

\`\`\`bash
# Minimal commands to run the demo
\`\`\`

## What It Does

Brief explanation with diagram if helpful.

## Prerequisites

- Tool 1 (version)
- Tool 2 (version)

## Usage

Detailed usage instructions.

## Testing

How to run tests.

## Architecture

Link to PROJECT_OVERVIEW.md section.
```

---

## Testing

### Test Requirements

| Demo | Unit Tests | Integration Tests | E2E Tests |
|------|------------|-------------------|-----------|
| Demo 1 | Required | Required (Envoy) | Optional |
| Demo 2 | Required | Required (Envoy) | Optional |
| Backend | Required | Required | Optional |

### Rust Testing

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_redacts_credit_card() {
        let input = b"Card: 1234-5678-9012-3456";
        let expected = b"Card: XXXX-XXXX-XXXX-XXXX";
        assert_eq!(redact_pii(input).unwrap(), expected);
    }
}
```

### Go Testing

```go
func TestRoutesBetaUser(t *testing.T) {
    headers := map[string]string{
        "User-Agent": "iPhone",
        "X-Geo-Country": "DE",
        "Cookie": "beta-tester=true",
    }
    result := determineRoute(headers)
    if result != "v2" {
        t.Errorf("Expected v2, got %s", result)
    }
}
```

### Python Testing

```python
import pytest
from app import app

@pytest.fixture
def client():
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client

def test_user_endpoint_returns_pii(client):
    response = client.get('/api/user')
    assert response.status_code == 200
    data = response.get_json()
    assert 'ssn' in data
    assert 'card_number' in data['payment']
```

### Test Naming

- `test_<function>_<scenario>_<expected>`
- Example: `test_redact_pii_with_ssn_returns_masked`

---

## Security

### Sensitive Data

1. **Never log PII** - Not even in debug mode
2. **No secrets in code** - Use environment variables
3. **Validate all input** - Especially in Wasm plugins
4. **Fail closed** - If unsure, reject the request

### Wasm-Specific Security

```rust
// GOOD: Bounded memory allocation
let mut buffer = Vec::with_capacity(MAX_BODY_SIZE);

// BAD: Unbounded allocation (DoS vector)
let mut buffer = Vec::new();
body.read_to_end(&mut buffer)?;
```

### Dependency Management

- Pin all dependency versions
- Run `cargo audit` / `govulncheck` in CI
- Update dependencies monthly

---

## Performance

### Proxy-Wasm Performance Rules

1. **Minimize allocations** - Reuse buffers where possible
2. **Avoid regex compilation in hot path** - Use lazy_static
3. **Stream processing** - Don't buffer entire body if not needed
4. **Early exit** - Return `Action::Continue` as soon as possible

### Performance Budgets

| Operation | Target | Max |
|-----------|--------|-----|
| Header inspection | 10μs | 100μs |
| Body scan (4KB) | 50μs | 500μs |
| Memory per request | 1KB | 10KB |

### Measurement

```rust
// For local testing only - remove in production
let start = std::time::Instant::now();
// ... operation ...
log::debug!("Operation took {:?}", start.elapsed());
```

---

## Linting Configuration

### Rust (`.cargo/config.toml`)

```toml
[build]
rustflags = ["-D", "warnings"]
```

### Go (`.golangci.yml`)

```yaml
linters:
  enable:
    - gofmt
    - govet
    - errcheck
    - staticcheck
    - gosimple
    - ineffassign
    - unused
```

### Python (`pyproject.toml`)

```toml
[tool.ruff]
line-length = 88
select = ["E", "F", "W", "I", "N"]

[tool.black]
line-length = 88
```

### Pre-commit Hooks

Install with:
```bash
./scripts/setup-dev.sh
```

This enables:
- Format checking
- Lint checking
- Test execution (fast tests only)

---

## Summary Checklist

Before submitting code:

- [ ] Code formatted (`cargo fmt` / `gofmt` / `black`)
- [ ] Lints pass (`cargo clippy` / `golangci-lint` / `ruff`)
- [ ] Tests pass (`cargo test` / `go test` / `pytest`)
- [ ] Documentation updated
- [ ] No `unwrap()` or `panic!()` in production paths
- [ ] Commit messages follow convention
- [ ] PR description explains the change
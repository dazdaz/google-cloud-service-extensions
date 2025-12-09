# DATA_STRUCTURES.md - Schemas & Examples

This document contains all static data references, type definitions, schemas, and mock data used across the demos.

---

## Table of Contents

1. [Demo 1: Edge Security Schemas](#demo-1-edge-security-schemas)
2. [Demo 2: Smart Router Schemas](#demo-2-smart-router-schemas)
3. [Cloud Run Backend Schemas](#cloud-run-backend-schemas)
4. [Envoy Configuration Schemas](#envoy-configuration-schemas)
5. [Test Fixtures](#test-fixtures)

---

## Demo 1: Edge Security Schemas

### PII Pattern Configuration

```rust
// 01-edge-security/src/patterns.rs

/// A pattern definition for PII detection and redaction
pub struct PiiPattern {
    /// Human-readable name of the pattern
    pub name: &'static str,
    /// Regular expression pattern to match
    pub regex: &'static str,
    /// Replacement string (use $1, $2 for capture groups)
    pub replacement: &'static str,
    /// Whether this pattern is enabled by default
    pub enabled: bool,
}

/// Default PII patterns shipped with the plugin
pub const DEFAULT_PATTERNS: &[PiiPattern] = &[
    PiiPattern {
        name: "credit_card",
        regex: r"\b(\d{4})-(\d{4})-(\d{4})-(\d{4})\b",
        replacement: "XXXX-XXXX-XXXX-$4",
        enabled: true,
    },
    PiiPattern {
        name: "ssn",
        regex: r"\b(\d{3})-(\d{2})-(\d{4})\b",
        replacement: "XXX-XX-XXXX",
        enabled: true,
    },
    PiiPattern {
        name: "email",
        regex: r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b",
        replacement: "[EMAIL REDACTED]",
        enabled: true,
    },
    PiiPattern {
        name: "phone_us",
        regex: r"\b(\d{3})[.\-](\d{3})[.\-](\d{4})\b",
        replacement: "(XXX) XXX-$3",
        enabled: false,  // Disabled by default - too many false positives
    },
];
```

### Plugin Configuration (JSON)

```json
{
  "plugin_config": {
    "version": "1.0.0",
    "log_level": "info",
    "patterns": {
      "credit_card": true,
      "ssn": true,
      "email": true,
      "phone_us": false
    },
    "custom_patterns": [
      {
        "name": "internal_id",
        "regex": "INTERNAL-[A-Z0-9]{8}",
        "replacement": "INTERNAL-XXXXXXXX"
      }
    ],
    "bypass_paths": [
      "/health",
      "/metrics",
      "/api/internal/*"
    ],
    "max_body_size_bytes": 1048576
  }
}
```

### Redaction Result Schema

```rust
/// Result of a redaction operation
pub struct RedactionResult {
    /// Whether any redactions were made
    pub redacted: bool,
    /// Number of patterns matched
    pub match_count: u32,
    /// Names of patterns that matched
    pub matched_patterns: Vec<String>,
    /// The sanitized content
    pub content: Vec<u8>,
}
```

---

## Demo 2: Smart Router Schemas

### Routing Rule Definition

```go
// 02-smart-router/router/types.go

package router

// RoutingRule defines a condition and target for routing
type RoutingRule struct {
    // Name is a human-readable identifier
    Name string `json:"name"`
    
    // Priority determines evaluation order (lower = first)
    Priority int `json:"priority"`
    
    // Conditions that must ALL match
    Conditions []Condition `json:"conditions"`
    
    // Target backend to route to if conditions match
    Target string `json:"target"`
    
    // Headers to add to the request
    AddHeaders map[string]string `json:"add_headers,omitempty"`
    
    // Headers to remove from the request
    RemoveHeaders []string `json:"remove_headers,omitempty"`
}

// Condition defines a single matching rule
type Condition struct {
    // Type of condition: "header", "cookie", "path", "query"
    Type string `json:"type"`
    
    // Key to check (header name, cookie name, etc.)
    Key string `json:"key"`
    
    // Operator: "equals", "contains", "regex", "exists"
    Operator string `json:"operator"`
    
    // Value to match against
    Value string `json:"value,omitempty"`
}

// RoutingDecision is the result of evaluating rules
type RoutingDecision struct {
    // Target backend
    Target string `json:"target"`
    
    // Rule that matched (empty if default)
    MatchedRule string `json:"matched_rule"`
    
    // Headers to add
    AddHeaders map[string]string `json:"add_headers"`
    
    // Headers to remove
    RemoveHeaders []string `json:"remove_headers"`
}
```

### Plugin Configuration (JSON)

```json
{
  "plugin_config": {
    "version": "1.0.0",
    "log_level": "info",
    "default_target": "v1",
    "rules": [
      {
        "name": "beta-testers",
        "priority": 1,
        "conditions": [
          {
            "type": "header",
            "key": "User-Agent",
            "operator": "contains",
            "value": "iPhone"
          },
          {
            "type": "header",
            "key": "X-Geo-Country",
            "operator": "equals",
            "value": "DE"
          },
          {
            "type": "cookie",
            "key": "beta-tester",
            "operator": "equals",
            "value": "true"
          }
        ],
        "target": "v2",
        "add_headers": {
          "X-Routed-By": "smart-router",
          "X-Route-Reason": "beta-tester-match"
        }
      },
      {
        "name": "canary-10-percent",
        "priority": 2,
        "conditions": [
          {
            "type": "header",
            "key": "X-Request-Hash",
            "operator": "regex",
            "value": "^[0-9]$"
          }
        ],
        "target": "v2",
        "add_headers": {
          "X-Routed-By": "smart-router",
          "X-Route-Reason": "canary"
        }
      }
    ]
  }
}
```

---

## Cloud Run Backend Schemas

### User API Response (with PII - for Demo 1 testing)

```json
{
  "id": "user-12345",
  "name": "John Doe",
  "email": "john.doe@example.com",
  "phone": "555-123-4567",
  "ssn": "123-45-6789",
  "payment": {
    "card_number": "4111-1111-1111-1111",
    "expiry": "12/25",
    "billing_address": {
      "street": "123 Main St",
      "city": "Anytown",
      "state": "CA",
      "zip": "12345"
    }
  },
  "created_at": "2024-01-15T10:30:00Z"
}
```

### User API Response (after redaction by Demo 1)

```json
{
  "id": "user-12345",
  "name": "John Doe",
  "email": "[EMAIL REDACTED]",
  "phone": "555-123-4567",
  "ssn": "XXX-XX-XXXX",
  "payment": {
    "card_number": "XXXX-XXXX-XXXX-1111",
    "expiry": "12/25",
    "billing_address": {
      "street": "123 Main St",
      "city": "Anytown",
      "state": "CA",
      "zip": "12345"
    }
  },
  "created_at": "2024-01-15T10:30:00Z"
}
```

### Version API Response (v1 - for Demo 2 testing)

```json
{
  "version": "v1",
  "environment": "production",
  "build": "2024.01.15.001",
  "features": {
    "new_dashboard": false,
    "beta_analytics": false
  }
}
```

### Version API Response (v2-beta - for Demo 2 testing)

```json
{
  "version": "v2-beta",
  "environment": "beta",
  "build": "2024.01.20.042",
  "features": {
    "new_dashboard": true,
    "beta_analytics": true,
    "experimental_ai": true
  }
}
```

### Health Check Response

```json
{
  "status": "healthy",
  "version": "1.0.0",
  "uptime_seconds": 3600
}
```

---

## Envoy Configuration Schemas

### Base Envoy Configuration

```yaml
# infrastructure/envoy/envoy.yaml

static_resources:
  listeners:
    - name: main
      address:
        socket_address:
          address: 0.0.0.0
          port_value: 10000
      filter_chains:
        - filters:
            - name: envoy.filters.network.http_connection_manager
              typed_config:
                "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
                stat_prefix: ingress_http
                codec_type: AUTO
                route_config:
                  name: local_route
                  virtual_hosts:
                    - name: backend
                      domains: ["*"]
                      routes:
                        - match:
                            prefix: "/"
                          route:
                            cluster: backend_service
                http_filters:
                  - name: envoy.filters.http.wasm
                    typed_config:
                      "@type": type.googleapis.com/envoy.extensions.filters.http.wasm.v3.Wasm
                      config:
                        name: "my_plugin"
                        root_id: "my_root_id"
                        vm_config:
                          runtime: "envoy.wasm.runtime.v8"
                          code:
                            local:
                              filename: "/etc/envoy/plugin.wasm"
                        configuration:
                          "@type": type.googleapis.com/google.protobuf.StringValue
                          value: |
                            {"log_level": "debug"}
                  - name: envoy.filters.http.router
                    typed_config:
                      "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router

  clusters:
    - name: backend_service
      type: STRICT_DNS
      lb_policy: ROUND_ROBIN
      load_assignment:
        cluster_name: backend_service
        endpoints:
          - lb_endpoints:
              - endpoint:
                  address:
                    socket_address:
                      address: backend
                      port_value: 8080
```

### Wasm Plugin Configuration Schema

```yaml
# Wasm filter configuration schema
wasm_filter:
  name: string                    # Plugin display name
  root_id: string                 # Root context identifier
  vm_config:
    runtime: string               # "envoy.wasm.runtime.v8" or "envoy.wasm.runtime.wasmtime"
    code:
      local:
        filename: string          # Path to .wasm file
      # OR
      remote:
        http_uri:
          uri: string             # URL to fetch .wasm
          timeout: duration
        sha256: string            # Expected hash
    allow_precompiled: bool       # Allow AOT compiled modules
  configuration:                  # Plugin-specific config
    "@type": type.googleapis.com/google.protobuf.StringValue
    value: string                 # JSON config string
```

---

## Test Fixtures

### Demo 1: PII Test Cases

```json
{
  "test_cases": [
    {
      "name": "credit_card_simple",
      "input": "Card: 4111-1111-1111-1111",
      "expected": "Card: XXXX-XXXX-XXXX-1111",
      "patterns_matched": ["credit_card"]
    },
    {
      "name": "ssn_in_json",
      "input": "{\"ssn\": \"123-45-6789\"}",
      "expected": "{\"ssn\": \"XXX-XX-XXXX\"}",
      "patterns_matched": ["ssn"]
    },
    {
      "name": "multiple_patterns",
      "input": "SSN: 123-45-6789, Card: 4111-1111-1111-1111",
      "expected": "SSN: XXX-XX-XXXX, Card: XXXX-XXXX-XXXX-1111",
      "patterns_matched": ["ssn", "credit_card"]
    },
    {
      "name": "no_pii",
      "input": "Hello, World!",
      "expected": "Hello, World!",
      "patterns_matched": []
    },
    {
      "name": "email_redaction",
      "input": "Contact: user@example.com",
      "expected": "Contact: [EMAIL REDACTED]",
      "patterns_matched": ["email"]
    }
  ]
}
```

### Demo 2: Routing Test Cases

```json
{
  "test_cases": [
    {
      "name": "full_beta_match",
      "headers": {
        "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0)",
        "X-Geo-Country": "DE",
        "Cookie": "session=abc123; beta-tester=true"
      },
      "expected_target": "v2",
      "expected_rule": "beta-testers"
    },
    {
      "name": "partial_match_iphone_only",
      "headers": {
        "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0)",
        "X-Geo-Country": "US"
      },
      "expected_target": "v1",
      "expected_rule": ""
    },
    {
      "name": "canary_hash_match",
      "headers": {
        "User-Agent": "Chrome/120.0",
        "X-Request-Hash": "5"
      },
      "expected_target": "v2",
      "expected_rule": "canary-10-percent"
    },
    {
      "name": "default_routing",
      "headers": {
        "User-Agent": "Chrome/120.0"
      },
      "expected_target": "v1",
      "expected_rule": ""
    }
  ]
}
```

---

## HTTP Headers Reference

### Request Headers Used

| Header | Demo | Purpose |
|--------|------|---------|
| `User-Agent` | 2 | Device detection for routing |
| `X-Geo-Country` | 2 | Geographic routing |
| `Cookie` | 2 | Beta tester flag |
| `X-Request-Hash` | 2 | Canary deployment hash |
| `Content-Type` | 1, 2 | Body format detection |
| `Content-Length` | 1 | Body size for buffering |

### Response Headers Added

| Header | Demo | Purpose |
|--------|------|---------|
| `X-PII-Redacted` | 1 | Indicates redaction occurred |
| `X-Redaction-Count` | 1 | Number of patterns matched |
| `X-Routed-By` | 2 | Attribution to router |
| `X-Route-Reason` | 2 | Why this route was chosen |
| `X-Backend-Version` | 2 | Which backend responded |

---

## Environment Variables

### Demo 1

| Variable | Default | Description |
|----------|---------|-------------|
| `EDGE_SECURITY_LOG_LEVEL` | `info` | Log verbosity |
| `EDGE_SECURITY_MAX_BODY` | `1048576` | Max body size to scan |

### Demo 2

| Variable | Default | Description |
|----------|---------|-------------|
| `SMART_ROUTER_LOG_LEVEL` | `info` | Log verbosity |
| `SMART_ROUTER_DEFAULT` | `v1` | Default backend target |

### Cloud Run Backend

| Variable | Default | Description |
|----------|---------|-------------|
| `FLASK_ENV` | `production` | Flask environment |
| `PORT` | `8080` | Server port |
| `LOG_LEVEL` | `info` | Log verbosity |

### Infrastructure

| Variable | Default | Description |
|----------|---------|-------------|
| `ENVOY_LOG_LEVEL` | `info` | Envoy log verbosity |
| `BACKEND_PORT` | `8080` | Backend port |
| `ENVOY_PORT` | `10000` | Envoy listener port |
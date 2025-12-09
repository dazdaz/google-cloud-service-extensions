# Service Extensions Load Balancer Compatibility

Service Extensions allow you to inject custom logic (via WebAssembly plugins or gRPC callouts) into the data path to modify HTTP/HTTPS headers and payloads. However, they are **not supported on all load balancers** in Google Cloud.

Service Extensions are strictly limited to the **Envoy-based "Application" (Layer 7) load balancers**.

## Compatibility Matrix

| Load Balancer Type | gcloud Configuration (Scheme & Scope) | Protocol | Service Extensions? |
|---|---|---|---|
| Global External ALB | `--load-balancing-scheme=EXTERNAL_MANAGED`<br>`--global` | HTTP/HTTPS | ✅ Yes |
| Regional External ALB | `--load-balancing-scheme=EXTERNAL_MANAGED`<br>`--region=[REGION]` | HTTP/HTTPS | ✅ Yes |
| Regional Internal ALB | `--load-balancing-scheme=INTERNAL_MANAGED`<br>`--region=[REGION]` | HTTP/HTTPS | ✅ Yes |
| Cross-region Internal ALB | `--load-balancing-scheme=INTERNAL_MANAGED`<br>`--global` | HTTP/HTTPS | ✅ Yes |
| Media CDN | `gcloud edge-cache services ...`<br>(distinct resource) | HTTP/HTTPS | ✅ Yes |
| Classic External ALB | `--load-balancing-scheme=EXTERNAL` | HTTP/HTTPS | ❌ No |
| Proxy Network LB | `--load-balancing-scheme=EXTERNAL_MANAGED` | TCP/SSL | ❌ No |
| Passthrough Network LB | `--load-balancing-scheme=EXTERNAL`<br>(or `INTERNAL`) | TCP/UDP | ❌ No |

## Requirements for Service Extensions Support

For Service Extensions to work, your configuration must meet **two criteria simultaneously**:

1. **Scheme**: The load balancer must use a `_MANAGED` scheme (Envoy-based)
2. **Layer**: The protocol must be Layer 7 (HTTP/HTTPS/HTTP2)

### Why Some Load Balancers Are Not Supported

| Load Balancer Type | Technical Name / Scheme | Why It Fails |
|---|---|---|
| Classic Application Load Balancer | `EXTERNAL` | Legacy architecture (GFE 1.0) does not support the programmable Envoy data path |
| External Proxy Network LB | `EXTERNAL_MANAGED` | Even though it uses the "Managed" scheme, the protocol is TCP/SSL (Layer 4), which cannot process HTTP-level extensions |
| Classic Proxy Network LB | `EXTERNAL` | Legacy Layer 4 architecture |
| Passthrough Network LBs | `EXTERNAL` or `INTERNAL` | These pass traffic directly to backend VMs without proxying headers/payloads |

## How to Check Your Current Load Balancers

Run this command to list all backend services and see their scheme and scope:

```bash
gcloud compute backend-services list \
  --format="table(name, loadBalancingScheme, region, protocol)"
```

**What to look for in the output:**

- ✅ **Compatible**: `EXTERNAL_MANAGED` or `INTERNAL_MANAGED` combined with `HTTP`, `HTTPS`, or `HTTP2`
- ❌ **Incompatible**: Anything listing `EXTERNAL` (Classic), or protocols like `TCP`/`UDP`

## Terraform / API Compatibility Check

If you are auditing your infrastructure code (Terraform), look for the `google_compute_backend_service` resource:

### ✅ Compatible

```hcl
load_balancing_scheme = "EXTERNAL_MANAGED"  # with HTTP/HTTPS protocol
load_balancing_scheme = "INTERNAL_MANAGED"  # with HTTP/HTTPS protocol
```

### ❌ Incompatible

```hcl
load_balancing_scheme = "EXTERNAL"  # This is the "Classic" ALB
```

Any resource where `protocol` is `TCP`, `UDP`, or `SSL` is also incompatible.

## Note on Media CDN

While not a standard "Load Balancer" resource, Media CDN supports Service Extensions via the `EdgeCacheService` resource, specifically for Edge Plugins.

## Migration Path

If you are currently using a **Classic Application Load Balancer** (`EXTERNAL` scheme) and need Service Extensions, you must migrate to the **Global External Application Load Balancer** (newer Envoy-based architecture with `EXTERNAL_MANAGED` scheme).

## Related Resources

- [Service Extensions Overview](https://cloud.google.com/service-extensions/docs/overview)
- [Load Balancing Schemes](https://cloud.google.com/load-balancing/docs/backend-service#load_balancing_scheme)
- [Migrating to the Global External Application Load Balancer](https://cloud.google.com/load-balancing/docs/https/migrate-to-global)
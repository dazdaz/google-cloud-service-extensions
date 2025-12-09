# Demo 2 Backend: Smart Router (A/B Testing)

A Flask-based mock backend service that provides versioned endpoints for testing the Smart Router Wasm filter.

## Quick Start

```bash
# Build Docker image
docker build -t demo2-backend .

# Run locally
docker run -p 8080:8080 demo2-backend

# Test endpoints
curl http://localhost:8080/health
curl http://localhost:8080/v1/api/version
curl http://localhost:8080/v2/api/version
```

## Endpoints

### Health Check

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check for Load Balancer probing |

**Response:**
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "demo": "02-smart-router",
  "uptime_seconds": 3600
}
```

### Versioned Endpoints

These endpoints support A/B testing via the Smart Router Wasm filter.

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/version` | GET | Default version endpoint (v1) |
| `/v1/api/version` | GET | Explicit v1 (stable) endpoint |
| `/v2/api/version` | GET | Beta (v2) endpoint |
| `/v1/api/data` | GET | v1 data endpoint |
| `/v2/api/data` | GET | v2 data with enhanced features |

**v1 Response:**
```json
{
  "version": "v1",
  "environment": "production",
  "features": {
    "new_dashboard": false,
    "beta_analytics": false
  },
  "routing_info": {
    "routed_by": "direct",
    "route_reason": "none"
  }
}
```

**v2 Response (when routed by Wasm):**
```json
{
  "version": "v2-beta",
  "environment": "beta",
  "features": {
    "new_dashboard": true,
    "beta_analytics": true,
    "experimental_ai": true
  },
  "routing_info": {
    "routed_by": "smart-router",
    "route_reason": "beta-tester-match"
  }
}
```

## Routing Criteria

The Smart Router Wasm filter routes to v2 when ALL of these conditions match:
- User-Agent contains "iPhone"
- X-Geo-Country header equals "DE"
- Cookie contains "beta-tester=true"

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8080` | Server port |
| `FLASK_ENV` | `production` | Flask environment |
| `LOG_LEVEL` | `info` | Logging level |

## Development

```bash
# Install dependencies
pip install -r requirements.txt

# Run with Flask development server
FLASK_ENV=development python app.py

# Run with gunicorn
gunicorn --bind 0.0.0.0:8080 app:app
```

## Related Documentation

- [Demo 2 README](../../README.md)
- [Project Overview](../../../../PROJECT_OVERVIEW.md)
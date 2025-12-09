# Demo 1 Backend: Edge Security (PII Scrubbing)

A Flask-based mock backend service that provides PII-containing endpoints for testing the Edge Security Wasm filter.

## Quick Start

```bash
# Build Docker image
docker build -t demo1-backend .

# Run locally
docker run -p 8080:8080 demo1-backend

# Test endpoints
curl http://localhost:8080/health
curl http://localhost:8080/api/user
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
  "demo": "01-edge-security",
  "uptime_seconds": 3600
}
```

### PII Data Endpoints

These endpoints return data with PII for testing the Edge Security Wasm filter.

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/user` | GET | Single user with PII (SSN, credit card, email) |
| `/api/user-clean` | GET | Single user without PII (for comparison) |
| `/api/users` | GET | Multiple users with PII |

**Example `/api/user` Response (Before Scrubbing):**
```json
{
  "id": "user-12345",
  "name": "John Doe",
  "email": "john.doe@example.com",
  "ssn": "123-45-6789",
  "payment": {
    "card_number": "4111-1111-1111-1111",
    "expiry": "12/25"
  }
}
```

**After Wasm Scrubbing:**
```json
{
  "id": "user-12345",
  "name": "John Doe",
  "email": "[EMAIL REDACTED]",
  "ssn": "XXX-XX-XXXX",
  "payment": {
    "card_number": "XXXX-XXXX-XXXX-1111",
    "expiry": "12/25"
  }
}
```

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

- [Demo 1 README](../../README.md)
- [Project Overview](../../../../PROJECT_OVERVIEW.md)
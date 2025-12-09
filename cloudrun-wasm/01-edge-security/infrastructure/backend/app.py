"""
Mock Backend Server for Demo 1: Edge Security (PII Scrubbing)

This Flask application provides test endpoints for Demo 1:
- PII data endpoints (to be scrubbed by Wasm filter)
- Health check for Load Balancer probing
"""

import os
import logging
from datetime import datetime, timezone
from flask import Flask, jsonify, request

# Configure logging
log_level = os.environ.get("LOG_LEVEL", "info").upper()
logging.basicConfig(
    level=getattr(logging, log_level, logging.INFO),
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

# Create Flask app
app = Flask(__name__)

# Track server start time for uptime calculation
START_TIME = datetime.now(timezone.utc)


# =============================================================================
# Health Check Endpoint
# =============================================================================


@app.route("/health")
def health() -> tuple:
    """
    Health check endpoint for Load Balancer probing.
    
    Returns:
        JSON with health status, version, and uptime
    """
    uptime = (datetime.now(timezone.utc) - START_TIME).total_seconds()
    return jsonify({
        "status": "healthy",
        "version": "1.0.0",
        "demo": "01-edge-security",
        "uptime_seconds": int(uptime),
    })


# =============================================================================
# Demo 1: PII Data Endpoints (Edge Security Testing)
# =============================================================================


@app.route("/api/user")
def get_user() -> tuple:
    """
    Returns user data WITH PII for Demo 1 testing.
    
    The Wasm filter should scrub:
    - SSN: 123-45-6789 -> XXX-XX-XXXX
    - Credit Card: 4111-1111-1111-1111 -> XXXX-XXXX-XXXX-1111
    - Email: john.doe@example.com -> [EMAIL REDACTED]
    """
    logger.info("GET /api/user - Returning user with PII data")
    
    return jsonify({
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
                "zip": "12345",
            },
        },
        "created_at": "2024-01-15T10:30:00Z",
    })


@app.route("/api/user-clean")
def get_user_clean() -> tuple:
    """
    Returns user data WITHOUT PII for comparison.
    
    This endpoint can be used to verify the Wasm filter
    doesn't modify data that doesn't contain PII.
    """
    logger.info("GET /api/user-clean - Returning user without PII data")
    
    return jsonify({
        "id": "user-12345",
        "name": "John Doe",
        "membership": "gold",
        "preferences": {
            "newsletter": True,
            "notifications": True,
        },
        "created_at": "2024-01-15T10:30:00Z",
    })


@app.route("/api/users")
def get_users() -> tuple:
    """
    Returns multiple users with PII for batch testing.
    """
    logger.info("GET /api/users - Returning multiple users with PII")
    
    return jsonify({
        "users": [
            {
                "id": "user-001",
                "name": "Alice Smith",
                "email": "alice.smith@example.com",
                "ssn": "111-22-3333",
                "card": "5500-0000-0000-0004",
            },
            {
                "id": "user-002",
                "name": "Bob Johnson",
                "email": "bob.j@company.org",
                "ssn": "444-55-6666",
                "card": "3400-000000-00009",
            },
            {
                "id": "user-003",
                "name": "Carol Williams",
                "email": "carol@personal.net",
                "ssn": "777-88-9999",
                "card": "6011-0000-0000-0004",
            },
        ],
        "total": 3,
    })


# =============================================================================
# Debug Endpoints
# =============================================================================


@app.route("/debug/headers")
def debug_headers() -> tuple:
    """
    Returns all request headers for debugging.
    """
    headers = dict(request.headers)
    logger.debug(f"Request headers: {headers}")
    
    return jsonify({
        "headers": headers,
        "method": request.method,
        "path": request.path,
        "remote_addr": request.remote_addr,
    })


# =============================================================================
# Error Handlers
# =============================================================================


@app.errorhandler(404)
def not_found(error) -> tuple:
    """Handle 404 errors."""
    return jsonify({
        "error": "Not Found",
        "message": f"The requested URL {request.path} was not found",
        "status": 404,
    }), 404


@app.errorhandler(500)
def internal_error(error) -> tuple:
    """Handle 500 errors."""
    logger.error(f"Internal error: {error}")
    return jsonify({
        "error": "Internal Server Error",
        "message": "An unexpected error occurred",
        "status": 500,
    }), 500


# =============================================================================
# Main Entry Point
# =============================================================================


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    debug = os.environ.get("FLASK_ENV") == "development"
    
    logger.info(f"Starting Demo 1 Backend on port {port}")
    logger.info(f"Debug mode: {debug}")
    
    app.run(
        host="0.0.0.0",
        port=port,
        debug=debug,
    )
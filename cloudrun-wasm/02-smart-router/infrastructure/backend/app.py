"""
Mock Backend Server for Demo 2: Smart Router (A/B Testing)

This Flask application provides test endpoints for Demo 2:
- Versioned endpoints (v1/v2 for A/B testing)
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
        "demo": "02-smart-router",
        "uptime_seconds": int(uptime),
    })


# =============================================================================
# Demo 2: Versioned Endpoints (A/B Testing)
# =============================================================================


@app.route("/api/version")
@app.route("/v1/api/version")
def get_version_v1() -> tuple:
    """
    Returns v1 (stable) version response.
    
    This is the default endpoint for standard users.
    """
    logger.info("GET /v1/api/version - Returning v1 stable response")
    
    # Check if request was routed by Wasm filter
    routed_by = request.headers.get("X-Routed-By", "direct")
    route_reason = request.headers.get("X-Route-Reason", "none")
    
    return jsonify({
        "version": "v1",
        "environment": "production",
        "build": "2024.01.15.001",
        "features": {
            "new_dashboard": False,
            "beta_analytics": False,
        },
        "routing_info": {
            "routed_by": routed_by,
            "route_reason": route_reason,
        },
    })


@app.route("/v2/api/version")
def get_version_v2() -> tuple:
    """
    Returns v2 (beta) version response.
    
    This endpoint should be reached when the Wasm router
    detects beta user criteria (iPhone + DE + beta-tester cookie).
    """
    logger.info("GET /v2/api/version - Returning v2 beta response")
    
    # Check if request was routed by Wasm filter
    routed_by = request.headers.get("X-Routed-By", "direct")
    route_reason = request.headers.get("X-Route-Reason", "none")
    
    return jsonify({
        "version": "v2-beta",
        "environment": "beta",
        "build": "2024.01.20.042",
        "features": {
            "new_dashboard": True,
            "beta_analytics": True,
            "experimental_ai": True,
        },
        "routing_info": {
            "routed_by": routed_by,
            "route_reason": route_reason,
        },
    })


@app.route("/v1/api/data")
def get_data_v1() -> tuple:
    """
    Returns v1 data endpoint response.
    """
    logger.info("GET /v1/api/data - Returning v1 data")
    
    return jsonify({
        "version": "v1",
        "data": {
            "items": ["item1", "item2", "item3"],
            "count": 3,
        },
    })


@app.route("/v2/api/data")
def get_data_v2() -> tuple:
    """
    Returns v2 data endpoint response with enhanced features.
    """
    logger.info("GET /v2/api/data - Returning v2 data")
    
    return jsonify({
        "version": "v2-beta",
        "data": {
            "items": ["item1", "item2", "item3", "item4-new", "item5-beta"],
            "count": 5,
            "enhanced": True,
            "ai_recommendations": ["rec1", "rec2"],
        },
    })


# =============================================================================
# Debug Endpoints
# =============================================================================


@app.route("/debug/headers")
def debug_headers() -> tuple:
    """
    Returns all request headers for debugging routing.
    """
    headers = dict(request.headers)
    logger.debug(f"Request headers: {headers}")
    
    return jsonify({
        "headers": headers,
        "method": request.method,
        "path": request.path,
        "remote_addr": request.remote_addr,
    })


@app.route("/debug/echo", methods=["GET", "POST"])
def debug_echo() -> tuple:
    """
    Echoes back the request for debugging.
    """
    response = {
        "method": request.method,
        "path": request.path,
        "headers": dict(request.headers),
        "args": dict(request.args),
    }
    
    if request.method == "POST":
        response["body"] = request.get_data(as_text=True)
    
    return jsonify(response)


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
    
    logger.info(f"Starting Demo 2 Backend on port {port}")
    logger.info(f"Debug mode: {debug}")
    
    app.run(
        host="0.0.0.0",
        port=port,
        debug=debug,
    )
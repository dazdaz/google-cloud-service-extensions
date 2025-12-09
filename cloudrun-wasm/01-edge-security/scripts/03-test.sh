#!/bin/bash
# Test Script for Demo 1: Edge Security (PII Scrubbing)
# Tests the deployed Cloud Run service with WASM PII scrubbing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print header
print_header() {
    echo ""
    echo -e "${BLUE}=========================================="
    echo "  $1"
    echo -e "==========================================${NC}"
    echo ""
}

# Print status message
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[i]${NC} $1"
}

# Default values
REGION="${REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-demo1-edge-security-backend}"

# Test Cloud Run direct (no WASM)
test_cloud_run_direct() {
    print_header "1. CLOUD RUN DIRECT (no WASM filter)"
    
    SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" \
        --region="$REGION" --format='value(status.url)' 2>/dev/null || echo "")
    
    if [ -z "$SERVICE_URL" ]; then
        print_error "Cloud Run service not found: $SERVICE_NAME"
        print_info "Deploy first with: make deploy"
        return 1
    fi
    
    echo "Service URL: $SERVICE_URL"
    echo ""
    
    # Get identity token
    ID_TOKEN=$(gcloud auth print-identity-token 2>/dev/null || echo "")
    if [ -z "$ID_TOKEN" ]; then
        print_error "Failed to get identity token. Run: gcloud auth login"
        return 1
    fi
    
    echo "Health check:"
    if curl -s -H "Authorization: Bearer $ID_TOKEN" "$SERVICE_URL/health" | jq . 2>/dev/null; then
        print_status "Health check passed"
    else
        print_error "Health check failed"
    fi
    
    echo ""
    echo "User endpoint (PII NOT scrubbed - direct to backend):"
    DIRECT_TIME=$(curl -s -o /tmp/direct_response.json -w "%{time_total}" \
        -H "Authorization: Bearer $ID_TOKEN" "$SERVICE_URL/api/user")
    cat /tmp/direct_response.json | jq . 2>/dev/null || cat /tmp/direct_response.json
    echo ""
    echo -e "⏱️  Direct latency: ${DIRECT_TIME}s"
    
    # Check if PII is present (it should be, since no WASM filter)
    if grep -q "123-45-6789" /tmp/direct_response.json 2>/dev/null; then
        print_status "PII present in direct response (expected)"
    fi
}

# Test Load Balancer with WASM filter
test_load_balancer() {
    print_header "2. LOAD BALANCER (with WASM filter)"
    
    LB_IP=$(gcloud compute addresses describe demo1-edge-security-lb-ip \
        --global --format='value(address)' 2>/dev/null || echo "")
    
    if [ -z "$LB_IP" ]; then
        print_info "Load Balancer not found."
        echo ""
        echo "To deploy the Load Balancer with WASM plugin:"
        echo "  1. Run: make deploy"
        echo "  2. Wait for LB to be ready (~5 minutes)"
        return 0
    fi
    
    echo "Load Balancer IP: $LB_IP"
    echo ""
    
    # Get identity token
    ID_TOKEN=$(gcloud auth print-identity-token 2>/dev/null || echo "")
    
    echo "Health check (via LB):"
    if curl -s -k -H "Authorization: Bearer $ID_TOKEN" "https://$LB_IP/health" 2>/dev/null | jq . 2>/dev/null; then
        print_status "LB health check passed"
    else
        print_info "LB health check failed - is WASM plugin deployed?"
    fi
    
    echo ""
    echo "User endpoint (PII SHOULD be scrubbed by WASM):"
    LB_TIME=$(curl -s -k -H "Authorization: Bearer $ID_TOKEN" \
        -o /tmp/lb_response.txt -w "%{time_total}" \
        -D /tmp/lb_headers.txt "https://$LB_IP/api/user" 2>/dev/null)
    cat /tmp/lb_response.txt | jq . 2>/dev/null || cat /tmp/lb_response.txt
    echo ""
    echo -e "⏱️  LB + WASM latency: ${LB_TIME}s"
    
    echo ""
    echo "Response headers (WASM indicator):"
    if grep -i "x-wasm" /tmp/lb_headers.txt 2>/dev/null; then
        print_status "WASM headers found"
    else
        print_info "No WASM headers found"
    fi
    
    # Check if PII is scrubbed
    if grep -q "XXX-XX-XXXX" /tmp/lb_response.txt 2>/dev/null; then
        print_status "SSN redacted (XXX-XX-XXXX)"
    elif grep -q "123-45-6789" /tmp/lb_response.txt 2>/dev/null; then
        print_error "SSN NOT redacted - WASM filter may not be working"
    fi
    
    if grep -q "XXXX-XXXX-XXXX" /tmp/lb_response.txt 2>/dev/null; then
        print_status "Credit card redacted"
    fi
    
    if grep -q "EMAIL REDACTED" /tmp/lb_response.txt 2>/dev/null; then
        print_status "Email redacted"
    fi
}

# Main function
main() {
    print_header "Demo 1: Edge Security - Live Tests"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --region)
                REGION="$2"
                shift 2
                ;;
            --service)
                SERVICE_NAME="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  --region <region>   GCP region (default: us-central1)"
                echo "  --service <name>    Cloud Run service name"
                echo "  --help              Show this help"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    print_info "Region: $REGION"
    print_info "Service: $SERVICE_NAME"
    
    # Run tests
    test_cloud_run_direct
    test_load_balancer
    
    print_header "Test Summary"
    print_status "Live tests completed!"
    echo ""
    echo "Compare the responses above:"
    echo "  - Direct Cloud Run: Should show raw PII (SSN, credit card, email)"
    echo "  - Load Balancer:    Should show redacted PII (XXX-XX-XXXX, etc.)"
}

main "$@"
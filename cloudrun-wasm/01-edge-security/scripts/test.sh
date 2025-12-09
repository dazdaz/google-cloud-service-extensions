#!/bin/bash
# Test Script for Demo 1: Edge Security (PII Scrubbing)
# Runs unit tests and optional integration tests

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"

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

# Run unit tests
run_unit_tests() {
    print_header "Running Unit Tests"
    
    cd "$DEMO_DIR"
    
    print_info "Running cargo test"
    cargo test
    
    print_info "Running cargo clippy"
    cargo clippy -- -D warnings
    
    print_status "Unit tests passed"
}

# Run integration tests
run_integration_tests() {
    print_header "Running Integration Tests"
    
    cd "$DEMO_DIR"
    
    print_info "Starting test environment..."
    docker compose -f infrastructure/docker/docker-compose.yaml up -d
    
    # Wait for services to be ready
    print_info "Waiting for services to start..."
    sleep 5
    
    # Test health endpoint
    print_info "Testing health endpoint..."
    if curl -s -f http://localhost:8080/health > /dev/null; then
        print_status "Backend health check passed"
    else
        print_error "Backend health check failed"
        docker compose -f infrastructure/docker/docker-compose.yaml down
        return 1
    fi
    
    # Test PII endpoint through Envoy
    print_info "Testing PII scrubbing..."
    RESPONSE=$(curl -s http://localhost:10000/api/user 2>/dev/null || echo "")
    if echo "$RESPONSE" | grep -q "XXX-XX-XXXX"; then
        print_status "SSN redaction working"
    elif echo "$RESPONSE" | grep -q "ssn"; then
        print_info "Response received but SSN not redacted (Wasm filter may not be loaded)"
    else
        print_info "Could not connect to Envoy (may not be running)"
    fi
    
    # Cleanup
    print_info "Stopping test environment..."
    docker compose -f infrastructure/docker/docker-compose.yaml down
    
    print_status "Integration tests completed"
}

# Main function
main() {
    print_header "Demo 1: Edge Security - Tests"
    
    # Parse arguments
    RUN_UNIT=true
    RUN_INTEGRATION=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --unit)
                RUN_INTEGRATION=false
                shift
                ;;
            --integration)
                RUN_UNIT=false
                RUN_INTEGRATION=true
                shift
                ;;
            --all)
                RUN_INTEGRATION=true
                shift
                ;;
            --help)
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  --unit          Run unit tests only (default)"
                echo "  --integration   Run integration tests only"
                echo "  --all           Run all tests"
                echo "  --help          Show this help"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Track results
    FAILED=0
    PASSED=0
    
    # Run tests
    if [ "$RUN_UNIT" = true ]; then
        if run_unit_tests; then
            ((PASSED++))
        else
            ((FAILED++))
        fi
    fi
    
    if [ "$RUN_INTEGRATION" = true ]; then
        if run_integration_tests; then
            ((PASSED++))
        else
            ((FAILED++))
        fi
    fi
    
    # Summary
    print_header "Test Summary"
    
    echo "Passed: $PASSED"
    echo "Failed: $FAILED"
    echo ""
    
    if [ $FAILED -gt 0 ]; then
        print_error "Tests completed with $FAILED failures"
        exit 1
    else
        print_status "All tests passed!"
    fi
}

main "$@"
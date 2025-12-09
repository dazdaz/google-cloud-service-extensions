#!/bin/bash
# Build Script for Demo 1: Edge Security (PII Scrubbing)
# Compiles Rust Wasm plugin using cargo

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

# Use rustup's cargo if available (needed for wasm32 target)
if [ -x "$HOME/.cargo/bin/cargo" ]; then
    CARGO="$HOME/.cargo/bin/cargo"
else
    CARGO="cargo"
fi

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

# Build Wasm plugin
build_wasm() {
    print_header "Building Demo 1: Edge Security (Rust)"
    
    cd "$DEMO_DIR"
    
    print_info "Using cargo: $CARGO"
    print_info "Running cargo build --target wasm32-unknown-unknown --release"
    $CARGO build --target wasm32-unknown-unknown --release
    
    WASM_FILE="$DEMO_DIR/target/wasm32-unknown-unknown/release/edge_security.wasm"
    
    if [ -f "$WASM_FILE" ]; then
        SIZE=$(du -h "$WASM_FILE" | cut -f1)
        print_status "Built: $WASM_FILE ($SIZE)"
    else
        print_error "Build failed: $WASM_FILE not found"
        return 1
    fi
}

# Build backend Docker image
build_backend() {
    print_header "Building Backend Docker Image"
    
    BACKEND_DIR="$DEMO_DIR/infrastructure/backend"
    
    if [ ! -d "$BACKEND_DIR" ]; then
        print_error "Backend directory not found: $BACKEND_DIR"
        return 1
    fi
    
    print_info "Running docker build -t demo1-backend"
    docker build -t demo1-backend "$BACKEND_DIR"
    
    print_status "Built: demo1-backend Docker image"
}

# Main function
main() {
    print_header "Demo 1: Edge Security - Build"
    
    # Parse arguments
    BUILD_WASM=true
    BUILD_BACKEND=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --wasm-only)
                BUILD_BACKEND=false
                shift
                ;;
            --backend-only)
                BUILD_WASM=false
                BUILD_BACKEND=true
                shift
                ;;
            --all)
                BUILD_BACKEND=true
                shift
                ;;
            --help)
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  --wasm-only      Build only Wasm plugin (default)"
                echo "  --backend-only   Build only Backend Docker image"
                echo "  --all            Build both Wasm and Backend"
                echo "  --help           Show this help"
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
    
    # Build components
    if [ "$BUILD_WASM" = true ]; then
        build_wasm || ((FAILED++))
    fi
    
    if [ "$BUILD_BACKEND" = true ]; then
        build_backend || ((FAILED++))
    fi
    
    # Summary
    print_header "Build Summary"
    
    if [ $FAILED -gt 0 ]; then
        print_error "Build completed with $FAILED failures"
        exit 1
    else
        print_status "Build completed successfully!"
        echo ""
        echo "Artifacts:"
        [ "$BUILD_WASM" = true ] && echo "  - target/wasm32-unknown-unknown/release/edge_security.wasm"
        [ "$BUILD_BACKEND" = true ] && echo "  - Docker image: demo1-backend"
        echo ""
        echo "Next steps:"
        echo "  make test         - Run tests"
        echo "  make deploy       - Deploy to Cloud Run"
    fi
}

main "$@"
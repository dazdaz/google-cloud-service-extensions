#!/bin/bash
# Deploy Script for Demo 2: Smart Router (A/B Testing)
# Deploys to Cloud Run and configures Wasm plugin

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

# Default values
DEFAULT_REGION="us-central1"
DEFAULT_SERVICE_NAME="demo2-smart-router-backend"
DEFAULT_ARTIFACT_REPO="demo2-smart-router"

# Print header
print_header() {
    echo "" >&2
    echo -e "${BLUE}==========================================" >&2
    echo "  $1" >&2
    echo -e "==========================================${NC}" >&2
    echo "" >&2
}

# Print status message
print_status() {
    echo -e "${GREEN}[✓]${NC} $1" >&2
}

print_error() {
    echo -e "${RED}[✗]${NC} $1" >&2
}

print_info() {
    echo -e "${YELLOW}[i]${NC} $1" >&2
}

# Print and run command
run_cmd() {
    echo -e "${BLUE}  \$ $*${NC}" >&2
    "$@"
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check gcloud
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI not found. Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    print_status "gcloud CLI found"
    
    # Check docker only if not using Cloud Build
    if [ "$USE_CLOUD_BUILD" != "true" ]; then
        if ! command -v docker &> /dev/null; then
            print_info "Docker not found locally, using Cloud Build instead"
            USE_CLOUD_BUILD=true
        else
            print_status "Docker found"
        fi
    else
        print_status "Using Cloud Build (no local Docker required)"
    fi
    
    # Check authentication
    if ! gcloud auth print-access-token &> /dev/null; then
        print_error "Not authenticated with GCP. Run: gcloud auth login"
        exit 1
    fi
    print_status "GCP authentication valid"
}

# Get project ID
get_project_id() {
    if [ -n "$PROJECT_ID" ]; then
        echo "$PROJECT_ID"
        return
    fi
    
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [ -z "$PROJECT_ID" ]; then
        print_error "No project set. Run: gcloud config set project <PROJECT_ID>"
        exit 1
    fi
    echo "$PROJECT_ID"
}

# Build with Cloud Build (like demo 01)
build_with_cloud_build() {
    local project_id=$1
    local region=$2
    local repo_name=$3
    
    print_header "Building with Cloud Build"
    
    # Get the repo root (one level up from demo dir: 02-smart-router -> cloudrun-wasm)
    local repo_root
    repo_root="$(cd "$DEMO_DIR/../.." && pwd)"
    
    local config_file="$DEMO_DIR/cloudbuild.yaml"
    
    print_info "Submitting build to Cloud Build..."
    print_info "This builds the Go Wasm plugin + backend container"
    print_info "Repo root: $repo_root"
    print_info "Config: $config_file"
    
    # Run Cloud Build - use absolute path for config
    if ! run_cmd gcloud builds submit "$repo_root" \
        --config="$config_file" \
        --project="$project_id" \
        --substitutions="_REGION=${region},_ARTIFACT_REPO=${repo_name}"; then
        print_error "Cloud Build failed"
        exit 1
    fi
    
    print_status "Cloud Build completed"
    
    # Set global variable for image name (don't use echo, it gets captured)
    BUILD_IMAGE_NAME="${region}-docker.pkg.dev/${project_id}/${repo_name}/demo2-backend:latest"
    BUILD_WASM_IMAGE="${region}-docker.pkg.dev/${project_id}/${repo_name}/demo2-wasm:latest"
}

# Deploy to Cloud Run
deploy_service() {
    local project_id=$1
    local region=$2
    local service_name=$3
    local image_name=$4
    
    print_header "Deploying to Cloud Run"
    
    print_info "Deploying ${service_name} to ${region}..."
    
    # Note: --allow-unauthenticated may fail due to org policy
    # We use --no-invoker-iam-check + ingress settings instead
    gcloud run deploy "${service_name}" \
        --image "${image_name}" \
        --platform managed \
        --region "${region}" \
        --allow-unauthenticated \
        --ingress=internal-and-cloud-load-balancing \
        --no-invoker-iam-check \
        --port 8080 \
        --cpu 1 \
        --memory 512Mi \
        --min-instances 0 \
        --max-instances 10 \
        --timeout 30 \
        --set-env-vars "FLASK_ENV=production,LOG_LEVEL=info" \
        --labels "app=demo2-smart-router,component=backend" >&2 || {
        # If --allow-unauthenticated fails, try without it
        print_info "Retrying without --allow-unauthenticated (org policy may block it)..."
        gcloud run deploy "${service_name}" \
            --image "${image_name}" \
            --platform managed \
            --region "${region}" \
            --ingress=internal-and-cloud-load-balancing \
            --no-invoker-iam-check \
            --port 8080 \
            --cpu 1 \
            --memory 512Mi \
            --min-instances 0 \
            --max-instances 10 \
            --timeout 30 \
            --set-env-vars "FLASK_ENV=production,LOG_LEVEL=info" \
            --labels "app=demo2-smart-router,component=backend" >&2
    }
    
    print_status "Deployed ${service_name}"
    
    # Get the service URL
    gcloud run services describe "${service_name}" \
        --region "${region}" \
        --format 'value(status.url)'
}

# Ensure Artifact Registry repository exists
ensure_artifact_registry() {
    local project_id=$1
    local region=$2
    local repo_name=$3
    
    print_info "Checking Artifact Registry repository..."
    
    if ! gcloud artifacts repositories describe "$repo_name" \
        --location="$region" \
        --project="$project_id" &> /dev/null; then
        print_info "Creating Artifact Registry repository: $repo_name"
        run_cmd gcloud artifacts repositories create "$repo_name" \
            --repository-format=docker \
            --location="$region" \
            --project="$project_id" \
            --description="Container images for Cloud Run Wasm demos"
        print_status "Created Artifact Registry: $repo_name"
    else
        print_status "Artifact Registry exists: $repo_name"
    fi
}

# Upload Wasm file to GCS
upload_wasm() {
    local project_id=$1
    local bucket="${project_id}-wasm-plugins"
    
    print_header "Uploading Wasm File to GCS"
    
    # Create bucket if it doesn't exist
    if ! gsutil ls "gs://${bucket}" &> /dev/null; then
        print_info "Creating bucket: ${bucket}"
        run_cmd gsutil mb -l us-central1 "gs://${bucket}"
    fi
    
    # Upload Demo 2 Wasm
    WASM_FILE="$DEMO_DIR/target/wasm32-unknown-unknown/release/smart_router.wasm"
    if [ -f "$WASM_FILE" ]; then
        print_info "Uploading Wasm file..."
        run_cmd gsutil cp "$WASM_FILE" "gs://${bucket}/wasm/smart_router.wasm"
        print_status "Uploaded smart_router.wasm to gs://${bucket}/wasm/"
    else
        print_error "Wasm file not found at $WASM_FILE"
        print_info "Building Wasm locally..."
        if command -v cargo &> /dev/null; then
            (cd "$DEMO_DIR" && RUSTFLAGS="-C link-arg=-zstack-size=32768 -C panic=abort -C debuginfo=0" cargo build --target wasm32-unknown-unknown --release)
            run_cmd gsutil cp "$WASM_FILE" "gs://${bucket}/wasm/smart_router.wasm"
            print_status "Built and uploaded smart_router.wasm"
        else
            print_error "Cargo not found. Install Rust or build via make build-wasm first."
            return 1
        fi
    fi
}

# Deploy Load Balancer infrastructure
deploy_load_balancer() {
    local project_id=$1
    local region=$2
    local service_name=$3
    
    print_header "Deploying Load Balancer Infrastructure"
    
    # Reserve static IP if not exists
    print_info "Checking for static IP..."
    if ! gcloud compute addresses describe demo2-smart-router-lb-ip --global --project="$project_id" &> /dev/null; then
        print_info "Reserving static IP address..."
        run_cmd gcloud compute addresses create demo2-smart-router-lb-ip \
            --global \
            --project="$project_id"
        print_status "Reserved static IP"
    else
        print_status "Static IP already exists"
    fi
    
    LB_IP=$(gcloud compute addresses describe demo2-smart-router-lb-ip \
        --global --project="$project_id" --format='value(address)')
    print_info "Load Balancer IP: $LB_IP"
    
    # Create Serverless NEG for Cloud Run
    print_info "Checking for Serverless NEG..."
    if ! gcloud compute network-endpoint-groups describe demo2-cloud-run-neg \
        --region="$region" --project="$project_id" &> /dev/null; then
        print_info "Creating Serverless NEG..."
        run_cmd gcloud compute network-endpoint-groups create demo2-cloud-run-neg \
            --region="$region" \
            --network-endpoint-type=serverless \
            --cloud-run-service="$service_name" \
            --project="$project_id"
        print_status "Created Serverless NEG"
    else
        print_status "Serverless NEG already exists"
    fi
    
    # Create Backend Service
    print_info "Checking for Backend Service..."
    if ! gcloud compute backend-services describe demo2-backend-service \
        --global --project="$project_id" &> /dev/null; then
        print_info "Creating Backend Service..."
        run_cmd gcloud compute backend-services create demo2-backend-service \
            --global \
            --load-balancing-scheme=EXTERNAL_MANAGED \
            --project="$project_id"
        
        # Add NEG to backend service
        run_cmd gcloud compute backend-services add-backend demo2-backend-service \
            --global \
            --network-endpoint-group=demo2-cloud-run-neg \
            --network-endpoint-group-region="$region" \
            --project="$project_id"
        print_status "Created Backend Service"
    else
        print_status "Backend Service already exists"
    fi
    
    # Create URL Map
    print_info "Checking for URL Map..."
    if ! gcloud compute url-maps describe demo2-url-map \
        --global --project="$project_id" &> /dev/null; then
        print_info "Creating URL Map..."
        run_cmd gcloud compute url-maps create demo2-url-map \
            --default-service=demo2-backend-service \
            --global \
            --project="$project_id"
        print_status "Created URL Map"
    else
        print_status "URL Map already exists"
    fi
    
    # Create SSL Certificate (self-signed for demo)
    print_info "Checking for SSL Certificate..."
    if ! gcloud compute ssl-certificates describe demo2-ssl-cert \
        --global --project="$project_id" &> /dev/null; then
        print_info "Creating self-signed SSL Certificate..."
        # Create temp key and cert
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /tmp/demo2-key.pem \
            -out /tmp/demo2-cert.pem \
            -subj "/CN=demo2.example.com" 2>/dev/null
        
        run_cmd gcloud compute ssl-certificates create demo2-ssl-cert \
            --certificate=/tmp/demo2-cert.pem \
            --private-key=/tmp/demo2-key.pem \
            --global \
            --project="$project_id"
        rm -f /tmp/demo2-key.pem /tmp/demo2-cert.pem
        print_status "Created SSL Certificate"
    else
        print_status "SSL Certificate already exists"
    fi
    
    # Create HTTPS Target Proxy
    print_info "Checking for HTTPS Proxy..."
    if ! gcloud compute target-https-proxies describe demo2-https-proxy \
        --global --project="$project_id" &> /dev/null; then
        print_info "Creating HTTPS Proxy..."
        run_cmd gcloud compute target-https-proxies create demo2-https-proxy \
            --url-map=demo2-url-map \
            --ssl-certificates=demo2-ssl-cert \
            --global \
            --project="$project_id"
        print_status "Created HTTPS Proxy"
    else
        print_status "HTTPS Proxy already exists"
    fi
    
    # Create Forwarding Rule
    print_info "Checking for Forwarding Rule..."
    if ! gcloud compute forwarding-rules describe demo2-https-rule \
        --global --project="$project_id" &> /dev/null; then
        print_info "Creating Forwarding Rule..."
        run_cmd gcloud compute forwarding-rules create demo2-https-rule \
            --global \
            --target-https-proxy=demo2-https-proxy \
            --address=demo2-smart-router-lb-ip \
            --ports=443 \
            --load-balancing-scheme=EXTERNAL_MANAGED \
            --project="$project_id"
        print_status "Created Forwarding Rule"
    else
        print_status "Forwarding Rule already exists"
    fi
    
    print_status "Load Balancer deployed at https://$LB_IP"
}

# Deploy WASM plugin and Traffic Extension
deploy_wasm_plugin() {
    local project_id=$1
    local region=$2
    local artifact_repo=$3
    local wasm_image="${region}-docker.pkg.dev/${project_id}/${artifact_repo}/demo2-wasm:latest"
    
    print_header "Deploying WASM Plugin"
    
    # Check if Service Extensions API is enabled
    print_info "Checking Service Extensions API..."
    if ! gcloud services list --enabled --project="$project_id" 2>/dev/null | grep -q "networkservices.googleapis.com"; then
        print_info "Enabling Network Services API..."
        run_cmd gcloud services enable networkservices.googleapis.com --project="$project_id"
    fi
    
    # Write plugin config to a temp file (avoids shell escaping issues)
    cat > /tmp/wasm-plugin-config.json << 'EOF'
{
    "log_level": "info",
    "default_target": "v1",
    "rules": [
        {
            "name": "beta-testers",
            "priority": 1,
            "conditions": [
                {"type": "header", "key": "User-Agent", "operator": "contains", "value": "iPhone"},
                {"type": "header", "key": "X-Geo-Country", "operator": "equals", "value": "DE"},
                {"type": "cookie", "key": "beta-tester", "operator": "equals", "value": "true"}
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
                {"type": "header", "key": "X-Request-Hash", "operator": "regex", "value": "^[0-9]$"}
            ],
            "target": "v2",
            "add_headers": {
                "X-Routed-By": "smart-router",
                "X-Route-Reason": "canary"
            }
        }
    ]
}
EOF
    
    # Create or update WASM Plugin
    print_info "Checking for WASM Plugin..."
    if ! gcloud beta service-extensions wasm-plugins describe smart-router \
        --location=global --project="$project_id" &> /dev/null 2>&1; then
        print_info "Creating WASM Plugin..."
        print_info "Using WASM OCI image: ${wasm_image}"
        echo -e "${BLUE}  \$ gcloud beta service-extensions wasm-plugins create smart-router ...${NC}" >&2
        
        gcloud beta service-extensions wasm-plugins create smart-router \
            --location=global \
            --project="$project_id" \
            --main-version=v1 \
            --image="${wasm_image}" \
            --plugin-config-file=/tmp/wasm-plugin-config.json \
            --log-config=enable=true,sample-rate=1.0
        
        print_status "Created WASM Plugin"
    else
        print_status "WASM Plugin exists, updating with new version..."
        print_info "Using WASM OCI image: ${wasm_image}"
        
        # Create new version with timestamp to force update
        VERSION_NAME="v$(date +%Y%m%d%H%M%S)"
        print_info "Creating new version: ${VERSION_NAME}"
        echo -e "${BLUE}  \$ gcloud beta service-extensions wasm-plugin-versions create ${VERSION_NAME} ...${NC}" >&2
        
        gcloud beta service-extensions wasm-plugin-versions create "${VERSION_NAME}" \
            --wasm-plugin=smart-router \
            --location=global \
            --project="$project_id" \
            --image="${wasm_image}" \
            --plugin-config-file=/tmp/wasm-plugin-config.json
        
        # Set new version as main version
        print_info "Setting ${VERSION_NAME} as main version..."
        gcloud beta service-extensions wasm-plugins update smart-router \
            --location=global \
            --project="$project_id" \
            --main-version="${VERSION_NAME}"
        
        print_status "Updated WASM Plugin to version ${VERSION_NAME}"
    fi
    
    rm -f /tmp/wasm-plugin-config.json
    
    # Create LB Traffic Extension to attach WASM to LB
    print_info "Checking for LB Traffic Extension..."
    if ! gcloud service-extensions lb-traffic-extensions describe smart-router-extension \
        --location=global --project="$project_id" &> /dev/null 2>&1; then
        print_info "Creating LB Traffic Extension..."
        
        # Get forwarding rule self link
        FWD_RULE=$(gcloud compute forwarding-rules describe demo2-https-rule \
            --global --project="$project_id" --format='value(selfLink)' 2>/dev/null)
        
        if [ -z "$FWD_RULE" ]; then
            print_error "Forwarding rule not found. Deploy Load Balancer first."
            return 1
        fi
        
        # Write extension config to YAML file for import
        # Note: Smart Router runs on REQUEST path for routing decisions
        cat > /tmp/lb-traffic-extension.yaml << EOF
name: smart-router-extension
loadBalancingScheme: EXTERNAL_MANAGED
forwardingRules:
  - ${FWD_RULE}
extensionChains:
  - name: router-chain
    matchCondition:
      celExpression: "true"
    extensions:
      - name: smart-router
        service: projects/${project_id}/locations/global/wasmPlugins/smart-router
        failOpen: true
        supportedEvents:
          - REQUEST_HEADERS
          - RESPONSE_HEADERS
EOF
        
        print_info "Importing LB traffic extension..."
        echo -e "${BLUE}  \$ gcloud service-extensions lb-traffic-extensions import smart-router-extension ...${NC}" >&2
        
        gcloud service-extensions lb-traffic-extensions import smart-router-extension \
            --location=global \
            --project="$project_id" \
            --source=/tmp/lb-traffic-extension.yaml
        
        rm -f /tmp/lb-traffic-extension.yaml
        print_status "Created LB Traffic Extension"
    else
        print_status "LB Traffic Extension already exists"
    fi
    
    print_status "WASM Plugin deployed and attached to Load Balancer"
}

# Test the deployment
test_deployment() {
    local service_url=$1
    
    print_header "Testing Deployment"
    
    # Get identity token for authentication
    local auth_header=""
    if ID_TOKEN=$(gcloud auth print-identity-token 2>/dev/null); then
        auth_header="Authorization: Bearer ${ID_TOKEN}"
        print_info "Using authenticated requests"
    fi
    
    print_info "Testing health endpoint..."
    if [ -n "$auth_header" ]; then
        RESPONSE=$(curl -s -H "$auth_header" "${service_url}/health")
    else
        RESPONSE=$(curl -s "${service_url}/health")
    fi
    
    if echo "$RESPONSE" | grep -q "healthy"; then
        print_status "Health check passed"
    else
        print_error "Health check failed"
        echo "Response: $RESPONSE" >&2
        return 1
    fi
    
    print_info "Testing version endpoint..."
    if [ -n "$auth_header" ]; then
        RESPONSE=$(curl -s -H "$auth_header" "${service_url}/api/version")
    else
        RESPONSE=$(curl -s "${service_url}/api/version")
    fi
    
    if echo "$RESPONSE" | grep -q "version"; then
        print_status "Version endpoint working"
    else
        print_error "Version endpoint check failed"
    fi
}

# Destroy deployment
destroy_deployment() {
    local project_id=$1
    local region=$2
    local service_name=$3
    local bucket="${project_id}-wasm-plugins"
    
    print_header "Destroying Demo 2 Deployment"
    
    # Delete LB Traffic Extension first (depends on forwarding rule)
    print_info "Deleting LB Traffic Extension..."
    if gcloud service-extensions lb-traffic-extensions describe smart-router-extension \
        --location=global --project="$project_id" &> /dev/null 2>&1; then
        run_cmd gcloud service-extensions lb-traffic-extensions delete smart-router-extension \
            --location=global \
            --project="$project_id" \
            --quiet || true
        print_status "Deleted LB Traffic Extension"
    else
        print_info "LB Traffic Extension not found, skipping"
    fi
    
    # Delete WASM Plugin
    print_info "Deleting WASM Plugin..."
    if gcloud beta service-extensions wasm-plugins describe smart-router \
        --location=global --project="$project_id" &> /dev/null 2>&1; then
        run_cmd gcloud beta service-extensions wasm-plugins delete smart-router \
            --location=global \
            --project="$project_id" \
            --quiet || true
        print_status "Deleted WASM Plugin"
    else
        print_info "WASM Plugin not found, skipping"
    fi
    
    # Delete Forwarding Rules
    print_info "Deleting Forwarding Rules..."
    if gcloud compute forwarding-rules describe demo2-https-rule \
        --global --project="$project_id" &> /dev/null 2>&1; then
        run_cmd gcloud compute forwarding-rules delete demo2-https-rule \
            --global --project="$project_id" --quiet || true
        print_status "Deleted HTTPS Forwarding Rule"
    fi
    
    # Delete HTTPS Proxy
    print_info "Deleting HTTPS Proxy..."
    if gcloud compute target-https-proxies describe demo2-https-proxy \
        --global --project="$project_id" &> /dev/null 2>&1; then
        run_cmd gcloud compute target-https-proxies delete demo2-https-proxy \
            --global --project="$project_id" --quiet || true
        print_status "Deleted HTTPS Proxy"
    fi
    
    # Delete URL Map
    print_info "Deleting URL Map..."
    if gcloud compute url-maps describe demo2-url-map \
        --global --project="$project_id" &> /dev/null 2>&1; then
        run_cmd gcloud compute url-maps delete demo2-url-map \
            --global --project="$project_id" --quiet || true
        print_status "Deleted URL Map"
    fi
    
    # Delete SSL Certificate
    print_info "Deleting SSL Certificate..."
    if gcloud compute ssl-certificates describe demo2-ssl-cert \
        --global --project="$project_id" &> /dev/null 2>&1; then
        run_cmd gcloud compute ssl-certificates delete demo2-ssl-cert \
            --global --project="$project_id" --quiet || true
        print_status "Deleted SSL Certificate"
    fi
    
    # Delete Backend Service
    print_info "Deleting Backend Service..."
    if gcloud compute backend-services describe demo2-backend-service \
        --global --project="$project_id" &> /dev/null 2>&1; then
        run_cmd gcloud compute backend-services delete demo2-backend-service \
            --global --project="$project_id" --quiet || true
        print_status "Deleted Backend Service"
    fi
    
    # Delete Serverless NEG
    print_info "Deleting Serverless NEG..."
    if gcloud compute network-endpoint-groups describe demo2-cloud-run-neg \
        --region="$region" --project="$project_id" &> /dev/null 2>&1; then
        run_cmd gcloud compute network-endpoint-groups delete demo2-cloud-run-neg \
            --region="$region" --project="$project_id" --quiet || true
        print_status "Deleted Serverless NEG"
    fi
    
    # Delete Static IP
    print_info "Deleting Static IP..."
    if gcloud compute addresses describe demo2-smart-router-lb-ip \
        --global --project="$project_id" &> /dev/null 2>&1; then
        run_cmd gcloud compute addresses delete demo2-smart-router-lb-ip \
            --global --project="$project_id" --quiet || true
        print_status "Deleted Static IP"
    fi
    
    # Delete Cloud Run service
    print_info "Deleting Cloud Run service: ${service_name}..."
    if gcloud run services describe "${service_name}" --region="${region}" --project="$project_id" &> /dev/null; then
        run_cmd gcloud run services delete "${service_name}" \
            --region "${region}" \
            --project="$project_id" \
            --quiet
        print_status "Deleted Cloud Run service"
    else
        print_info "Service not found, skipping"
    fi
    
    # Delete Docker image from GCR
    print_info "Deleting Docker image from GCR..."
    IMAGE_NAME="gcr.io/${project_id}/${service_name}"
    if gcloud container images describe "${IMAGE_NAME}" &> /dev/null 2>&1; then
        run_cmd gcloud container images delete "${IMAGE_NAME}" --quiet --force-delete-tags || true
        print_status "Deleted Docker image"
    else
        print_info "Docker image not found, skipping"
    fi
    
    # Delete Wasm file from GCS
    print_info "Deleting Wasm file from GCS..."
    run_cmd gsutil rm "gs://${bucket}/wasm/smart_router.wasm" 2>/dev/null || true
    print_status "Deleted Wasm file from GCS"
    
    print_status "Demo 2 deployment destroyed successfully"
}

# Deploy local (Docker Compose)
deploy_local() {
    print_header "Deploying Demo 2 Locally"
    
    cd "$DEMO_DIR"
    
    # Build Wasm first
    print_info "Building Wasm plugin..."
    ./scripts/build.sh
    
    # Start Docker Compose
    print_info "Starting Docker Compose..."
    docker compose -f infrastructure/docker/docker-compose.yaml up -d
    
    print_status "Local deployment started"
    echo ""
    echo "Services:"
    echo "  - Envoy (with Wasm): http://localhost:10000"
    echo "  - Backend: http://localhost:8080"
    echo "  - Envoy Admin: http://localhost:9901"
    echo ""
    echo "Test with:"
    echo "  curl http://localhost:10000/api/version"
    echo "  curl -H 'Cookie: beta-tester=true' -H 'User-Agent: iPhone' -H 'X-Geo-Country: DE' http://localhost:10000/api/version"
}

# Stop local deployment
stop_local() {
    print_header "Stopping Local Deployment"
    
    cd "$DEMO_DIR"
    
    docker compose -f infrastructure/docker/docker-compose.yaml down -v
    
    print_status "Local deployment stopped"
}

# Main function
main() {
    # Parse arguments
    REGION="${REGION:-$DEFAULT_REGION}"
    SERVICE_NAME="${SERVICE_NAME:-$DEFAULT_SERVICE_NAME}"
    ARTIFACT_REPO="${ARTIFACT_REPO:-$DEFAULT_ARTIFACT_REPO}"
    SKIP_BUILD="${SKIP_BUILD:-false}"
    ACTION="deploy"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project)
                PROJECT_ID="$2"
                shift 2
                ;;
            --region)
                REGION="$2"
                shift 2
                ;;
            --service-name)
                SERVICE_NAME="$2"
                shift 2
                ;;
            --artifact-repo)
                ARTIFACT_REPO="$2"
                shift 2
                ;;
            --skip-build)
                SKIP_BUILD=true
                shift
                ;;
            --local)
                ACTION="local"
                shift
                ;;
            --stop)
                ACTION="stop"
                shift
                ;;
            --destroy)
                ACTION="destroy"
                shift
                ;;
            --help)
                echo "Usage: $0 [options]"
                echo ""
                echo "Actions:"
                echo "  (default)        Deploy to Cloud Run using Cloud Build"
                echo "  --local          Deploy locally with Docker Compose"
                echo "  --stop           Stop local deployment"
                echo "  --destroy        Destroy Cloud Run deployment"
                echo ""
                echo "Options:"
                echo "  --project <id>        GCP project ID"
                echo "  --region <region>     GCP region (default: us-central1)"
                echo "  --service-name <n>    Cloud Run service name"
                echo "  --artifact-repo <n>   Artifact Registry repo (default: cloudrun-wasm)"
                echo "  --skip-build          Skip building (use existing image)"
                echo "  --help                Show this help"
                echo ""
                echo "Environment variables:"
                echo "  PROJECT_ID    GCP project (or use --project)"
                echo "  REGION        GCP region (or use --region)"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Execute action
    case $ACTION in
        local)
            deploy_local
            ;;
        stop)
            stop_local
            ;;
        destroy)
            check_prerequisites
            PROJECT_ID=$(get_project_id)
            destroy_deployment "$PROJECT_ID" "$REGION" "$SERVICE_NAME" "$GCS_BUCKET"
            ;;
        deploy)
            print_header "Demo 2: Smart Router - Full Stack Deployment"
            
            check_prerequisites
            PROJECT_ID=$(get_project_id)
            print_info "Project: ${PROJECT_ID}"
            print_info "Region: ${REGION}"
            print_info "Service: ${SERVICE_NAME}"
            print_info "Artifact Registry: ${ARTIFACT_REPO}"
            
            # Ensure Artifact Registry exists
            ensure_artifact_registry "$PROJECT_ID" "$REGION" "$ARTIFACT_REPO"
            
            # Build with Cloud Build
            if [ "$SKIP_BUILD" = "false" ]; then
                build_with_cloud_build "$PROJECT_ID" "$REGION" "$ARTIFACT_REPO"
                IMAGE_NAME="$BUILD_IMAGE_NAME"
            else
                IMAGE_NAME="${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REPO}/demo2-backend:latest"
                print_info "Skipping build, using: ${IMAGE_NAME}"
            fi
            
            print_info "Deploying image: ${IMAGE_NAME}"
            
            # Step 1: Deploy to Cloud Run (backend)
            SERVICE_URL=$(deploy_service "$PROJECT_ID" "$REGION" "$SERVICE_NAME" "$IMAGE_NAME")
            
            # Step 2: Upload WASM file to GCS (backup)
            upload_wasm "$PROJECT_ID"
            
            # Step 3: Deploy Load Balancer
            deploy_load_balancer "$PROJECT_ID" "$REGION" "$SERVICE_NAME"
            
            # Step 4: Deploy WASM Plugin and Traffic Extension
            deploy_wasm_plugin "$PROJECT_ID" "$REGION" "$ARTIFACT_REPO"
            
            # Get LB IP for summary
            LB_IP=$(gcloud compute addresses describe demo2-smart-router-lb-ip \
                --global --project="$PROJECT_ID" --format='value(address)' 2>/dev/null || echo "")
            
            # Summary
            print_header "Deployment Complete"
            echo ""
            echo "Cloud Run Backend (direct, no WASM):"
            echo "  ${SERVICE_URL}"
            echo ""
            echo "Load Balancer (with WASM Smart Router):"
            if [ -n "$LB_IP" ]; then
                echo "  https://${LB_IP}"
            else
                echo "  (IP not available yet)"
            fi
            echo ""
            echo "Container Image:"
            echo "  ${IMAGE_NAME}"
            echo ""
            echo "WASM Plugin:"
            echo "  ${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REPO}/demo2-wasm:latest"
            echo ""
            echo -e "${GREEN}Test the deployment:${NC}"
            echo "  make test-live"
            echo ""
            echo "This will show:"
            echo "  1. Cloud Run (no routing, direct access)"
            echo "  2. Load Balancer (A/B routing by WASM plugin)"
            ;;
    esac
}

main "$@"
#!/bin/bash
# Deploy Script for Demo 1: Edge Security (PII Scrubbing)
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
DEFAULT_SERVICE_NAME="demo1-edge-security-backend"

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

# Print and run command
run_cmd() {
    echo -e "${BLUE}  \$ $*${NC}"
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

# Build with Cloud Build
build_with_cloud_build() {
    local project_id=$1
    local region=$2
    local repo_name=$3
    
    print_header "Building with Cloud Build"
    
    # Get the repo root (one level up from demo dir: 01-edge-security -> cloudrun-wasm)
    local repo_root
    repo_root="$(cd "$DEMO_DIR/../.." && pwd)"
    
    local config_file="$DEMO_DIR/cloudbuild.yaml"
    
    print_info "Submitting build to Cloud Build..."
    print_info "This builds the Rust Wasm plugin + backend container"
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
    BUILD_IMAGE_NAME="${region}-docker.pkg.dev/${project_id}/${repo_name}/demo1-backend:latest"
}

# Deploy to Cloud Run
deploy_service() {
    local project_id=$1
    local region=$2
    local service_name=$3
    local image_name=$4
    
    # All output to stderr since stdout is captured for the URL
    print_header "Deploying to Cloud Run" >&2
    
    print_info "Deploying ${service_name} to ${region}..." >&2
    
    # Print full command
    echo -e "${BLUE}  \$ gcloud run deploy ${service_name} --image ${image_name} --platform managed --region ${region} ...${NC}" >&2
    
    # Note: --allow-unauthenticated may fail due to org policy
    # We'll add IAM bindings manually after deployment
    gcloud run deploy "${service_name}" \
        --image "${image_name}" \
        --platform managed \
        --region "${region}" \
        --ingress all \
        --port 8080 \
        --cpu 1 \
        --memory 512Mi \
        --min-instances 0 \
        --max-instances 10 \
        --timeout 30 \
        --set-env-vars "FLASK_ENV=production,LOG_LEVEL=info" \
        --labels "app=demo1-edge-security,component=backend" >&2 || {
        print_error "Deployment failed" >&2
        exit 1
    }
    
    print_status "Deployed ${service_name}" >&2
    
    # Grant IAM access for Load Balancer and public access
    print_info "Configuring IAM permissions..." >&2
    PROJECT_NUMBER=$(gcloud projects describe "$project_id" --format='value(projectNumber)')
    
    # Try to add allUsers first (for direct public access)
    if gcloud run services add-iam-policy-binding "${service_name}" \
        --region "${region}" \
        --member="allUsers" \
        --role="roles/run.invoker" &> /dev/null; then
        print_status "Granted public access (allUsers)" >&2
    else
        print_info "Public access blocked by org policy, skipping allUsers" >&2
    fi
    
    # Add Load Balancer service account (required for LB access)
    if gcloud run services add-iam-policy-binding "${service_name}" \
        --region "${region}" \
        --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
        --role="roles/run.invoker" &> /dev/null; then
        print_status "Granted Load Balancer access" >&2
    else
        print_info "Failed to grant LB access, may need manual IAM configuration" >&2
    fi
    
    # Get the service URL (this is the only output to stdout)
    echo -e "${BLUE}  \$ gcloud run services describe ${service_name} --region ${region} --format 'value(status.url)'${NC}" >&2
    gcloud run services describe "${service_name}" \
        --region "${region}" \
        --format 'value(status.url)'
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
    
    # Upload Demo 1 Wasm
    WASM_FILE="$DEMO_DIR/target/wasm32-unknown-unknown/release/edge_security.wasm"
    if [ -f "$WASM_FILE" ]; then
        print_info "Uploading Wasm file..."
        run_cmd gsutil cp "$WASM_FILE" "gs://${bucket}/wasm/edge_security.wasm"
        print_status "Uploaded edge_security.wasm to gs://${bucket}/wasm/"
    else
        print_error "Wasm file not found at $WASM_FILE"
        print_info "Building Wasm locally..."
        if command -v cargo &> /dev/null; then
            (cd "$DEMO_DIR" && cargo build --target wasm32-unknown-unknown --release)
            run_cmd gsutil cp "$WASM_FILE" "gs://${bucket}/wasm/edge_security.wasm"
            print_status "Built and uploaded edge_security.wasm"
        else
            print_error "Cargo not found. Install Rust or build via Cloud Build first."
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
    if ! gcloud compute addresses describe demo1-edge-security-lb-ip --global --project="$project_id" &> /dev/null; then
        print_info "Reserving static IP address..."
        run_cmd gcloud compute addresses create demo1-edge-security-lb-ip \
            --global \
            --project="$project_id"
        print_status "Reserved static IP"
    else
        print_status "Static IP already exists"
    fi
    
    LB_IP=$(gcloud compute addresses describe demo1-edge-security-lb-ip \
        --global --project="$project_id" --format='value(address)')
    print_info "Load Balancer IP: $LB_IP"
    
    # Create Serverless NEG for Cloud Run
    print_info "Checking for Serverless NEG..."
    if ! gcloud compute network-endpoint-groups describe demo1-cloud-run-neg \
        --region="$region" --project="$project_id" &> /dev/null; then
        print_info "Creating Serverless NEG..."
        run_cmd gcloud compute network-endpoint-groups create demo1-cloud-run-neg \
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
    if ! gcloud compute backend-services describe demo1-backend-service \
        --global --project="$project_id" &> /dev/null; then
        print_info "Creating Backend Service..."
        run_cmd gcloud compute backend-services create demo1-backend-service \
            --global \
            --load-balancing-scheme=EXTERNAL_MANAGED \
            --project="$project_id"
        
        # Add NEG to backend service
        run_cmd gcloud compute backend-services add-backend demo1-backend-service \
            --global \
            --network-endpoint-group=demo1-cloud-run-neg \
            --network-endpoint-group-region="$region" \
            --project="$project_id"
        print_status "Created Backend Service"
    else
        print_status "Backend Service already exists"
    fi
    
    # Create URL Map
    print_info "Checking for URL Map..."
    if ! gcloud compute url-maps describe demo1-url-map \
        --global --project="$project_id" &> /dev/null; then
        print_info "Creating URL Map..."
        run_cmd gcloud compute url-maps create demo1-url-map \
            --default-service=demo1-backend-service \
            --global \
            --project="$project_id"
        print_status "Created URL Map"
    else
        print_status "URL Map already exists"
    fi
    
    # Create SSL Certificate (self-signed for demo)
    print_info "Checking for SSL Certificate..."
    if ! gcloud compute ssl-certificates describe demo1-ssl-cert \
        --global --project="$project_id" &> /dev/null; then
        print_info "Creating self-signed SSL Certificate..."
        # Create temp key and cert
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /tmp/demo1-key.pem \
            -out /tmp/demo1-cert.pem \
            -subj "/CN=demo1.example.com" 2>/dev/null
        
        run_cmd gcloud compute ssl-certificates create demo1-ssl-cert \
            --certificate=/tmp/demo1-cert.pem \
            --private-key=/tmp/demo1-key.pem \
            --global \
            --project="$project_id"
        rm -f /tmp/demo1-key.pem /tmp/demo1-cert.pem
        print_status "Created SSL Certificate"
    else
        print_status "SSL Certificate already exists"
    fi
    
    # Create HTTPS Target Proxy
    print_info "Checking for HTTPS Proxy..."
    if ! gcloud compute target-https-proxies describe demo1-https-proxy \
        --global --project="$project_id" &> /dev/null; then
        print_info "Creating HTTPS Proxy..."
        run_cmd gcloud compute target-https-proxies create demo1-https-proxy \
            --url-map=demo1-url-map \
            --ssl-certificates=demo1-ssl-cert \
            --global \
            --project="$project_id"
        print_status "Created HTTPS Proxy"
    else
        print_status "HTTPS Proxy already exists"
    fi
    
    # Create Forwarding Rule
    print_info "Checking for Forwarding Rule..."
    if ! gcloud compute forwarding-rules describe demo1-https-rule \
        --global --project="$project_id" &> /dev/null; then
        print_info "Creating Forwarding Rule..."
        run_cmd gcloud compute forwarding-rules create demo1-https-rule \
            --global \
            --target-https-proxy=demo1-https-proxy \
            --address=demo1-edge-security-lb-ip \
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
    local wasm_image="${region}-docker.pkg.dev/${project_id}/${artifact_repo}/demo1-wasm:latest"
    
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
    "patterns": {
        "credit_card": true,
        "ssn": true,
        "email": true,
        "phone_us": false
    },
    "bypass_paths": ["/health", "/metrics"],
    "max_body_size_bytes": 1048576
}
EOF
    
    # Create or update WASM Plugin
    print_info "Checking for WASM Plugin..."
    if ! gcloud beta service-extensions wasm-plugins describe pii-scrubbing \
        --location=global --project="$project_id" &> /dev/null 2>&1; then
        print_info "Creating WASM Plugin..."
        print_info "Using WASM OCI image: ${wasm_image}"
        echo -e "${BLUE}  \$ gcloud beta service-extensions wasm-plugins create pii-scrubbing ...${NC}"
        
        gcloud beta service-extensions wasm-plugins create pii-scrubbing \
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
        
        # Create new version with timestamp to force image pull
        VERSION_NAME="v$(date +%Y%m%d%H%M%S)"
        print_info "Creating new version: ${VERSION_NAME}"
        echo -e "${BLUE}  \$ gcloud beta service-extensions wasm-plugin-versions create ${VERSION_NAME} ...${NC}"
        
        gcloud beta service-extensions wasm-plugin-versions create "${VERSION_NAME}" \
            --wasm-plugin=pii-scrubbing \
            --location=global \
            --project="$project_id" \
            --image="${wasm_image}" \
            --plugin-config-file=/tmp/wasm-plugin-config.json
        
        # Set new version as main version
        print_info "Setting ${VERSION_NAME} as main version..."
        gcloud beta service-extensions wasm-plugins update pii-scrubbing \
            --location=global \
            --project="$project_id" \
            --main-version="${VERSION_NAME}"
        
        print_status "Updated WASM Plugin to version ${VERSION_NAME}"
    fi
    
    rm -f /tmp/wasm-plugin-config.json
    
    # Create LB Traffic Extension to attach WASM to LB
    print_info "Checking for LB Traffic Extension..."
    if ! gcloud service-extensions lb-traffic-extensions describe pii-scrubbing-extension \
        --location=global --project="$project_id" &> /dev/null 2>&1; then
        print_info "Creating LB Traffic Extension..."
        
        # Get forwarding rule self link
        FWD_RULE=$(gcloud compute forwarding-rules describe demo1-https-rule \
            --global --project="$project_id" --format='value(selfLink)' 2>/dev/null)
        
        if [ -z "$FWD_RULE" ]; then
            print_error "Forwarding rule not found. Deploy Load Balancer first."
            return 1
        fi
        
        # Write extension config to YAML file for import
        # Note: authority and timeout fields are NOT allowed for WASM plugins
        # Note: REQUEST_HEADERS needed for path detection, RESPONSE_* for body scrubbing
        cat > /tmp/lb-traffic-extension.yaml << EOF
name: pii-scrubbing-extension
loadBalancingScheme: EXTERNAL_MANAGED
forwardingRules:
  - ${FWD_RULE}
extensionChains:
  - name: pii-chain
    matchCondition:
      celExpression: "true"
    extensions:
      - name: pii-scrubbing
        service: projects/${project_id}/locations/global/wasmPlugins/pii-scrubbing
        failOpen: true
        supportedEvents:
          - REQUEST_HEADERS
          - RESPONSE_HEADERS
          - RESPONSE_BODY
EOF
        
        print_info "Importing LB traffic extension..."
        echo -e "${BLUE}  \$ gcloud service-extensions lb-traffic-extensions import pii-scrubbing-extension ...${NC}"
        
        gcloud service-extensions lb-traffic-extensions import pii-scrubbing-extension \
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
    
    print_info "Testing health endpoint..."
    echo -e "${BLUE}  \$ curl -s ${service_url}/health${NC}"
    HTTP_CODE=$(curl -s -o /tmp/health_response.txt -w "%{http_code}" "${service_url}/health")
    RESPONSE=$(cat /tmp/health_response.txt 2>/dev/null || echo "")
    
    if [ "$HTTP_CODE" = "403" ]; then
        print_info "Got 403 Forbidden - public access not enabled"
        print_info "This is expected if IAM policy couldn't be set"
        # Set global flag for summary
        PUBLIC_ACCESS_NEEDED=true
        return 0  # Don't fail the deployment
    elif echo "$RESPONSE" | grep -q "healthy"; then
        print_status "Health check passed"
    else
        print_error "Health check failed (HTTP ${HTTP_CODE})"
        echo "Response: $RESPONSE"
        return 1
    fi
    
    print_info "Testing user endpoint..."
    echo -e "${BLUE}  \$ curl -s ${service_url}/api/user${NC}"
    RESPONSE=$(curl -s "${service_url}/api/user")
    if echo "$RESPONSE" | grep -q "ssn"; then
        print_status "User endpoint working (contains PII for Wasm filter)"
    else
        print_info "User endpoint returned: $RESPONSE"
    fi
}

# Destroy deployment
destroy_deployment() {
    local project_id=$1
    local region=$2
    local service_name=$3
    local bucket=$4
    
    print_header "Destroying Demo 1 Deployment"
    
    # Delete Cloud Run service
    print_info "Deleting Cloud Run service: ${service_name}..."
    if gcloud run services describe "${service_name}" --region="${region}" &> /dev/null; then
        run_cmd gcloud run services delete "${service_name}" \
            --region "${region}" \
            --quiet
        print_status "Deleted Cloud Run service"
    else
        print_info "Service not found, skipping"
    fi
    
    # Delete Wasm plugin if exists
    print_info "Deleting Wasm plugin..."
    if gcloud beta service-extensions wasm-plugins describe pii-scrubbing --location=global &> /dev/null 2>&1; then
        run_cmd gcloud beta service-extensions wasm-plugins delete pii-scrubbing \
            --location=global \
            --quiet || true
        print_status "Deleted Wasm plugin"
    else
        print_info "Wasm plugin not found, skipping"
    fi
    
    # Delete traffic extension if exists
    print_info "Deleting traffic extension..."
    if gcloud beta service-extensions traffic-extensions describe pii-scrubbing-extension --location=global &> /dev/null 2>&1; then
        run_cmd gcloud beta service-extensions traffic-extensions delete pii-scrubbing-extension \
            --location=global \
            --quiet || true
        print_status "Deleted traffic extension"
    else
        print_info "Traffic extension not found, skipping"
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
    if [ -n "$bucket" ]; then
        print_info "Deleting Wasm file from GCS..."
        run_cmd gsutil rm "gs://${bucket}/wasm/edge_security.wasm" 2>/dev/null || true
        print_status "Deleted Wasm file from GCS"
    fi
    
    print_status "Demo 1 deployment destroyed successfully"
}

# Main function
main() {
    # Parse arguments
    REGION="${REGION:-$DEFAULT_REGION}"
    SERVICE_NAME="${SERVICE_NAME:-$DEFAULT_SERVICE_NAME}"
    ARTIFACT_REPO="${ARTIFACT_REPO:-demo1-edge-security}"
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
            --destroy)
                ACTION="destroy"
                shift
                ;;
            --help)
                echo "Usage: $0 [options]"
                echo ""
                echo "Actions:"
                echo "  (default)        Deploy to Cloud Run using Cloud Build"
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
        destroy)
            check_prerequisites
            PROJECT_ID=$(get_project_id)
            destroy_deployment "$PROJECT_ID" "$REGION" "$SERVICE_NAME" ""
            ;;
        deploy)
            print_header "Demo 1: Edge Security - Full Stack Deployment"
            
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
                IMAGE_NAME="${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REPO}/demo1-backend:latest"
                print_info "Skipping build, using: ${IMAGE_NAME}"
            fi
            
            print_info "Deploying image: ${IMAGE_NAME}"
            
            # Step 1: Deploy to Cloud Run (backend)
            SERVICE_URL=$(deploy_service "$PROJECT_ID" "$REGION" "$SERVICE_NAME" "$IMAGE_NAME")
            
            # Step 2: Upload WASM file to GCS
            upload_wasm "$PROJECT_ID"
            
            # Step 3: Deploy Load Balancer
            deploy_load_balancer "$PROJECT_ID" "$REGION" "$SERVICE_NAME"
            
            # Step 4: Deploy WASM Plugin and Traffic Extension
            deploy_wasm_plugin "$PROJECT_ID" "$REGION" "$ARTIFACT_REPO"
            
            # Get LB IP for summary
            LB_IP=$(gcloud compute addresses describe demo1-edge-security-lb-ip \
                --global --project="$PROJECT_ID" --format='value(address)' 2>/dev/null || echo "")
            
            # Summary
            print_header "Deployment Complete"
            echo ""
            echo "Cloud Run Backend (direct, no WASM):"
            echo "  ${SERVICE_URL}"
            echo ""
            echo "Load Balancer (with WASM PII scrubbing):"
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
            echo "  gs://${PROJECT_ID}-wasm-plugins/wasm/edge_security.wasm"
            echo ""
            echo -e "${GREEN}Test the deployment:${NC}"
            echo "  make test-live"
            echo ""
            echo "This will show:"
            echo "  1. Cloud Run (raw PII data)"
            echo "  2. Load Balancer (PII scrubbed by WASM)"
            ;;
    esac
}

main "$@"
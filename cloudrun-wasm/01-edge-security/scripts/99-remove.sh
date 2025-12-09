#!/bin/bash
# Cleanup Script for Demo 1: Edge Security (PII Scrubbing)
# Destroys all deployed GCP infrastructure
#
# Usage: ./scripts/99-remove.sh [--project PROJECT_ID] [--region REGION] [--force]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_REGION="us-central1"
DEFAULT_SERVICE_NAME="demo1-edge-security-backend"
DEFAULT_ARTIFACT_REPO="demo1-edge-security"

# Print functions
print_header() {
    echo ""
    echo -e "${BLUE}=========================================="
    echo "  $1"
    echo -e "==========================================${NC}"
    echo ""
}

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[i]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Print and run command
run_cmd() {
    echo -e "${BLUE}  \$ $*${NC}"
    "$@"
}

# Get project ID
get_project_id() {
    if [ -n "$PROJECT_ID" ]; then
        echo "$PROJECT_ID"
        return
    fi
    
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [ -z "$PROJECT_ID" ]; then
        print_error "No project set. Use --project or run: gcloud config set project <PROJECT_ID>"
        exit 1
    fi
    echo "$PROJECT_ID"
}

# Delete Cloud Run service
delete_cloud_run_service() {
    local project_id=$1
    local region=$2
    local service_name=$3
    
    print_info "Deleting Cloud Run service: ${service_name}..."
    
    if gcloud run services describe "${service_name}" \
        --region="${region}" \
        --project="${project_id}" &> /dev/null; then
        run_cmd gcloud run services delete "${service_name}" \
            --region="${region}" \
            --project="${project_id}" \
            --quiet
        print_status "Deleted Cloud Run service: ${service_name}"
    else
        print_info "Cloud Run service not found: ${service_name}"
    fi
}

# Delete container images from Artifact Registry
delete_artifact_images() {
    local project_id=$1
    local region=$2
    local repo_name=$3
    
    print_info "Deleting container images from Artifact Registry..."
    
    IMAGE_PATH="${region}-docker.pkg.dev/${project_id}/${repo_name}/demo1-backend"
    
    # List and delete all tags
    if gcloud artifacts docker images list "${IMAGE_PATH}" \
        --project="${project_id}" &> /dev/null 2>&1; then
        
        # Delete all versions
        run_cmd gcloud artifacts docker images delete "${IMAGE_PATH}" \
            --project="${project_id}" \
            --delete-tags \
            --quiet 2>/dev/null || true
        
        print_status "Deleted container images from: ${IMAGE_PATH}"
    else
        print_info "No container images found in Artifact Registry"
    fi
}

# Delete Wasm files from GCS
delete_wasm_from_gcs() {
    local project_id=$1
    
    local bucket="${project_id}-wasm-plugins"
    
    print_info "Deleting Wasm files from GCS bucket: ${bucket}..."
    
    if gsutil ls "gs://${bucket}" &> /dev/null 2>&1; then
        # Delete demo1 folder
        run_cmd gsutil -m rm -r "gs://${bucket}/demo1/" 2>/dev/null || true
        print_status "Deleted Wasm files from: gs://${bucket}/demo1/"
        
        # Check if bucket is empty, offer to delete it
        REMAINING=$(gsutil ls "gs://${bucket}" 2>/dev/null | wc -l || echo "0")
        if [ "$REMAINING" -eq 0 ]; then
            if [ "$FORCE" = "true" ]; then
                run_cmd gsutil rb "gs://${bucket}"
                print_status "Deleted empty bucket: ${bucket}"
            else
                print_info "Bucket is empty. To delete it: gsutil rb gs://${bucket}"
            fi
        fi
    else
        print_info "GCS bucket not found: ${bucket}"
    fi
}

# Delete Service Extensions (Wasm plugin and traffic extension)
delete_service_extensions() {
    local project_id=$1
    
    print_info "Deleting Service Extensions..."
    
    # Delete LB traffic extension (new API)
    if gcloud service-extensions lb-traffic-extensions describe pii-scrubbing-extension \
        --location=global \
        --project="${project_id}" &> /dev/null 2>&1; then
        run_cmd gcloud service-extensions lb-traffic-extensions delete pii-scrubbing-extension \
            --location=global \
            --project="${project_id}" \
            --quiet
        print_status "Deleted LB traffic extension: pii-scrubbing-extension"
    else
        print_info "LB traffic extension not found"
    fi
    
    # Delete wasm plugin
    if gcloud service-extensions wasm-plugins describe pii-scrubbing \
        --location=global \
        --project="${project_id}" &> /dev/null 2>&1; then
        run_cmd gcloud service-extensions wasm-plugins delete pii-scrubbing \
            --location=global \
            --project="${project_id}" \
            --quiet
        print_status "Deleted Wasm plugin: pii-scrubbing"
    else
        print_info "Wasm plugin not found"
    fi
}

# Delete Load Balancer infrastructure
delete_load_balancer() {
    local project_id=$1
    local region=$2
    
    print_info "Deleting Load Balancer infrastructure..."
    
    # Delete in reverse order of creation (dependencies first)
    
    # 1. Delete Forwarding Rule
    if gcloud compute forwarding-rules describe demo1-https-rule \
        --global --project="${project_id}" &> /dev/null 2>&1; then
        run_cmd gcloud compute forwarding-rules delete demo1-https-rule \
            --global \
            --project="${project_id}" \
            --quiet
        print_status "Deleted forwarding rule: demo1-https-rule"
    else
        print_info "Forwarding rule not found"
    fi
    
    # 2. Delete HTTPS Target Proxy
    if gcloud compute target-https-proxies describe demo1-https-proxy \
        --global --project="${project_id}" &> /dev/null 2>&1; then
        run_cmd gcloud compute target-https-proxies delete demo1-https-proxy \
            --global \
            --project="${project_id}" \
            --quiet
        print_status "Deleted HTTPS proxy: demo1-https-proxy"
    else
        print_info "HTTPS proxy not found"
    fi
    
    # 3. Delete SSL Certificate
    if gcloud compute ssl-certificates describe demo1-ssl-cert \
        --global --project="${project_id}" &> /dev/null 2>&1; then
        run_cmd gcloud compute ssl-certificates delete demo1-ssl-cert \
            --global \
            --project="${project_id}" \
            --quiet
        print_status "Deleted SSL certificate: demo1-ssl-cert"
    else
        print_info "SSL certificate not found"
    fi
    
    # 4. Delete URL Map
    if gcloud compute url-maps describe demo1-url-map \
        --global --project="${project_id}" &> /dev/null 2>&1; then
        run_cmd gcloud compute url-maps delete demo1-url-map \
            --global \
            --project="${project_id}" \
            --quiet
        print_status "Deleted URL map: demo1-url-map"
    else
        print_info "URL map not found"
    fi
    
    # 5. Delete Backend Service
    if gcloud compute backend-services describe demo1-backend-service \
        --global --project="${project_id}" &> /dev/null 2>&1; then
        run_cmd gcloud compute backend-services delete demo1-backend-service \
            --global \
            --project="${project_id}" \
            --quiet
        print_status "Deleted backend service: demo1-backend-service"
    else
        print_info "Backend service not found"
    fi
    
    # 6. Delete Serverless NEG
    if gcloud compute network-endpoint-groups describe demo1-cloud-run-neg \
        --region="${region}" --project="${project_id}" &> /dev/null 2>&1; then
        run_cmd gcloud compute network-endpoint-groups delete demo1-cloud-run-neg \
            --region="${region}" \
            --project="${project_id}" \
            --quiet
        print_status "Deleted serverless NEG: demo1-cloud-run-neg"
    else
        print_info "Serverless NEG not found"
    fi
    
    # 7. Delete Static IP
    if gcloud compute addresses describe demo1-edge-security-lb-ip \
        --global --project="${project_id}" &> /dev/null 2>&1; then
        run_cmd gcloud compute addresses delete demo1-edge-security-lb-ip \
            --global \
            --project="${project_id}" \
            --quiet
        print_status "Deleted static IP: demo1-edge-security-lb-ip"
    else
        print_info "Static IP not found"
    fi
}

# Main cleanup function
cleanup_all() {
    local project_id=$1
    local region=$2
    local service_name=$3
    local artifact_repo=$4
    
    print_header "Destroying Demo 1: Edge Security Infrastructure"
    
    echo "Project:          ${project_id}"
    echo "Region:           ${region}"
    echo "Service:          ${service_name}"
    echo "Artifact Repo:    ${artifact_repo}"
    echo ""
    
    if [ "$FORCE" != "true" ]; then
        read -p "Are you sure you want to delete all Demo 1 infrastructure? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Aborted"
            exit 0
        fi
    fi
    
    echo ""
    
    # Delete in order (dependencies first)
    delete_service_extensions "$project_id"
    delete_load_balancer "$project_id" "$region"
    delete_cloud_run_service "$project_id" "$region" "$service_name"
    delete_artifact_images "$project_id" "$region" "$artifact_repo"
    delete_wasm_from_gcs "$project_id"
    
    print_header "Cleanup Complete"
    
    echo "The following resources have been deleted:"
    echo "  - Cloud Run service: ${service_name}"
    echo "  - Load Balancer infrastructure (forwarding rule, proxy, backend, NEG, IP)"
    echo "  - Container images: ${artifact_repo}/demo1-backend"
    echo "  - Wasm files: gs://${project_id}-wasm-plugins/wasm/"
    echo "  - Service Extensions (WASM plugin, traffic extension)"
    echo ""
    echo "Note: Artifact Registry repository '${artifact_repo}' was not deleted"
    echo "      (may contain images for other demos)"
    echo ""
    echo "To delete the Artifact Registry repo:"
    echo "  gcloud artifacts repositories delete ${artifact_repo} --location=${region}"
}

# Parse arguments
main() {
    REGION="${REGION:-$DEFAULT_REGION}"
    SERVICE_NAME="${SERVICE_NAME:-$DEFAULT_SERVICE_NAME}"
    ARTIFACT_REPO="${ARTIFACT_REPO:-$DEFAULT_ARTIFACT_REPO}"
    FORCE="${FORCE:-false}"
    
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
            --force|-f)
                FORCE=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [options]"
                echo ""
                echo "Destroys all Demo 1: Edge Security GCP infrastructure"
                echo ""
                echo "Options:"
                echo "  --project <id>        GCP project ID"
                echo "  --region <region>     GCP region (default: us-central1)"
                echo "  --service-name <n>    Cloud Run service name"
                echo "  --artifact-repo <n>   Artifact Registry repo (default: cloudrun-wasm)"
                echo "  --force, -f           Skip confirmation prompts"
                echo "  --help, -h            Show this help"
                echo ""
                echo "This script deletes:"
                echo "  - Cloud Run service"
                echo "  - Container images from Artifact Registry"
                echo "  - Wasm files from GCS"
                echo "  - Service Extensions (Wasm plugin, traffic extension)"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Check gcloud
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI not found. Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check authentication
    if ! gcloud auth print-access-token &> /dev/null; then
        print_error "Not authenticated with GCP. Run: gcloud auth login"
        exit 1
    fi
    
    PROJECT_ID=$(get_project_id)
    cleanup_all "$PROJECT_ID" "$REGION" "$SERVICE_NAME" "$ARTIFACT_REPO"
}

main "$@"
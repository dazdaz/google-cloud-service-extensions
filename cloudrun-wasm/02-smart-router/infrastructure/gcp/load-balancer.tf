# GCP Application Load Balancer Configuration for Demo 2: Smart Router
# Terraform configuration for setting up the Load Balancer with Smart Router Wasm plugin

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# Variables
variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "backend_url" {
  description = "Cloud Run backend URL"
  type        = string
}

# Provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
}

# Reserve a static external IP address
resource "google_compute_global_address" "demo2_ip" {
  name = "demo2-smart-router-lb-ip"
}

# Backend service pointing to Cloud Run
resource "google_compute_backend_service" "demo2_backend" {
  name                  = "demo2-smart-router-backend"
  protocol              = "HTTP"
  port_name             = "http"
  timeout_sec           = 30
  enable_cdn            = false
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group = google_compute_region_network_endpoint_group.cloud_run_neg.id
  }

  health_checks = [google_compute_health_check.default.id]

  # Logging configuration
  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

# Serverless Network Endpoint Group for Cloud Run
resource "google_compute_region_network_endpoint_group" "cloud_run_neg" {
  name                  = "demo2-cloud-run-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = "demo2-smart-router-backend"
  }
}

# Health check
resource "google_compute_health_check" "default" {
  name = "demo2-health-check"

  http_health_check {
    port         = 80
    request_path = "/health"
  }

  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3
}

# URL Map (routing configuration)
resource "google_compute_url_map" "demo2" {
  name            = "demo2-url-map"
  default_service = google_compute_backend_service.demo2_backend.id

  host_rule {
    hosts        = ["*"]
    path_matcher = "allpaths"
  }

  path_matcher {
    name            = "allpaths"
    default_service = google_compute_backend_service.demo2_backend.id
  }
}

# HTTPS Target Proxy
resource "google_compute_target_https_proxy" "demo2" {
  name             = "demo2-https-proxy"
  url_map          = google_compute_url_map.demo2.id
  ssl_certificates = [google_compute_managed_ssl_certificate.demo2.id]
}

# HTTP Target Proxy (for redirect to HTTPS)
resource "google_compute_target_http_proxy" "demo2_redirect" {
  name    = "demo2-http-redirect"
  url_map = google_compute_url_map.demo2_redirect.id
}

# URL Map for HTTP -> HTTPS redirect
resource "google_compute_url_map" "demo2_redirect" {
  name = "demo2-http-redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

# Managed SSL Certificate
resource "google_compute_managed_ssl_certificate" "demo2" {
  name = "demo2-ssl-cert"

  managed {
    domains = ["demo2.example.com"] # Replace with your domain
  }
}

# HTTPS Forwarding Rule
resource "google_compute_global_forwarding_rule" "demo2_https" {
  name                  = "demo2-https-rule"
  ip_address            = google_compute_global_address.demo2_ip.id
  ip_protocol           = "TCP"
  port_range            = "443"
  target                = google_compute_target_https_proxy.demo2.id
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# HTTP Forwarding Rule (redirects to HTTPS)
resource "google_compute_global_forwarding_rule" "demo2_http" {
  name                  = "demo2-http-rule"
  ip_address            = google_compute_global_address.demo2_ip.id
  ip_protocol           = "TCP"
  port_range            = "80"
  target                = google_compute_target_http_proxy.demo2_redirect.id
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# Outputs
output "load_balancer_ip" {
  description = "The external IP address of the load balancer"
  value       = google_compute_global_address.demo2_ip.address
}

output "load_balancer_url" {
  description = "The URL of the load balancer"
  value       = "https://${google_compute_global_address.demo2_ip.address}"
}
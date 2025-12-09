//! Edge Security Wasm Filter - PII Scrubbing
//!
//! This proxy-wasm plugin scans HTTP response bodies for PII patterns
//! and redacts them before the response reaches the client.
//!
//! Supported patterns:
//! - Credit card numbers (e.g., 4111-1111-1111-1111)
//! - Social Security Numbers (e.g., 123-45-6789)
//! - Email addresses (e.g., user@example.com)
//!
//! # Extension Point
//! - Location: Response Path
//! - Callback: `on_http_response_body`

mod patterns;

use log::{debug, info, warn};
use proxy_wasm::traits::{Context, HttpContext, RootContext};
use proxy_wasm::types::{Action, ContextType, LogLevel};
use serde::Deserialize;

use patterns::{PiiPatternMatcher, RedactionResult};

// =============================================================================
// Configuration
// =============================================================================

/// Plugin configuration loaded from Envoy config
#[derive(Debug, Clone, Deserialize)]
struct PluginConfig {
    /// Log level for the plugin
    #[serde(default = "default_log_level")]
    log_level: String,

    /// Which patterns to enable
    #[serde(default)]
    patterns: PatternConfig,

    /// Paths to bypass (no scrubbing)
    #[serde(default)]
    bypass_paths: Vec<String>,

    /// Maximum body size to scan (bytes)
    #[serde(default = "default_max_body_size")]
    max_body_size_bytes: usize,
}

#[derive(Debug, Clone, Deserialize)]
struct PatternConfig {
    #[serde(default = "default_true")]
    credit_card: bool,
    #[serde(default = "default_true")]
    ssn: bool,
    #[serde(default = "default_true")]
    email: bool,
    #[serde(default)]
    phone_us: bool,
}

impl Default for PatternConfig {
    fn default() -> Self {
        Self {
            credit_card: true,
            ssn: true,
            email: true,
            phone_us: false,
        }
    }
}

fn default_log_level() -> String {
    "info".to_string()
}

fn default_max_body_size() -> usize {
    1_048_576 // 1MB
}

fn default_true() -> bool {
    true
}

impl Default for PluginConfig {
    fn default() -> Self {
        Self {
            log_level: default_log_level(),
            patterns: PatternConfig::default(),
            bypass_paths: vec!["/health".to_string(), "/metrics".to_string()],
            max_body_size_bytes: default_max_body_size(),
        }
    }
}

// =============================================================================
// Root Context
// =============================================================================

/// Root context for plugin initialization
struct PiiScrubberRoot {
    config: PluginConfig,
}

impl PiiScrubberRoot {
    fn new() -> Self {
        Self {
            config: PluginConfig::default(),
        }
    }
}

impl Context for PiiScrubberRoot {}

impl RootContext for PiiScrubberRoot {
    fn on_configure(&mut self, _plugin_configuration_size: usize) -> bool {
        // Try to get configuration from Envoy
        if let Some(config_bytes) = self.get_plugin_configuration() {
            match serde_json::from_slice::<PluginConfig>(&config_bytes) {
                Ok(config) => {
                    info!("PII Scrubber configured: {:?}", config);
                    self.config = config;
                }
                Err(e) => {
                    warn!("Failed to parse config, using defaults: {}", e);
                }
            }
        } else {
            info!("No configuration provided, using defaults");
        }

        // Set log level based on config
        let log_level = match self.config.log_level.to_lowercase().as_str() {
            "trace" => LogLevel::Trace,
            "debug" => LogLevel::Debug,
            "info" => LogLevel::Info,
            "warn" => LogLevel::Warn,
            "error" => LogLevel::Error,
            _ => LogLevel::Info,
        };
        proxy_wasm::set_log_level(log_level);

        info!("PII Scrubber initialized with {} bypass paths",
              self.config.bypass_paths.len());
        true
    }

    fn create_http_context(&self, context_id: u32) -> Option<Box<dyn HttpContext>> {
        info!("DIAG: create_http_context called with id={}", context_id);
        Some(Box::new(PiiScrubberHttp::new(context_id, self.config.clone())))
    }

    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }
}

// =============================================================================
// HTTP Context
// =============================================================================

/// HTTP context for processing individual requests
struct PiiScrubberHttp {
    context_id: u32,
    config: PluginConfig,
    request_path: String,
    should_scrub: bool,
    accumulated_body_size: usize,
}

impl PiiScrubberHttp {
    fn new(context_id: u32, config: PluginConfig) -> Self {
        Self {
            context_id,
            config,
            request_path: String::new(),
            should_scrub: true,
            accumulated_body_size: 0,
        }
    }

    /// Check if the current path should bypass scrubbing
    fn should_bypass_path(&self, path: &str) -> bool {
        for bypass_path in &self.config.bypass_paths {
            if bypass_path.ends_with('*') {
                let prefix = &bypass_path[..bypass_path.len() - 1];
                if path.starts_with(prefix) {
                    return true;
                }
            } else if path == bypass_path {
                return true;
            }
        }
        false
    }

    /// Perform PII redaction on the body
    fn redact_pii(&self, body: &[u8]) -> RedactionResult {
        let matcher = PiiPatternMatcher::new(
            self.config.patterns.credit_card,
            self.config.patterns.ssn,
            self.config.patterns.email,
            self.config.patterns.phone_us,
        );

        matcher.redact(body)
    }
}

impl Context for PiiScrubberHttp {}

impl HttpContext for PiiScrubberHttp {
    fn on_http_request_headers(&mut self, _num_headers: usize, _end_of_stream: bool) -> Action {
        info!("DIAG: on_http_request_headers called for context_id={}", self.context_id);
        
        // Get the request path to check for bypass
        if let Some(path) = self.get_http_request_header(":path") {
            info!("DIAG: request path={}", path);
            self.request_path = path.clone();
            self.should_scrub = !self.should_bypass_path(&path);
            
            if !self.should_scrub {
                debug!("[{}] Bypassing scrubbing for path: {}", self.context_id, path);
            }
        }

        Action::Continue
    }

    fn on_http_response_headers(&mut self, _num_headers: usize, _end_of_stream: bool) -> Action {
        info!("DIAG: on_http_response_headers called for context_id={}", self.context_id);
        
        // Add debug header to prove WASM is running
        self.add_http_response_header("X-WASM-Active", "true");
        
        if !self.should_scrub {
            self.add_http_response_header("X-WASM-Scrub", "bypassed");
            return Action::Continue;
        }

        // Check content type - only process text/json responses
        if let Some(content_type) = self.get_http_response_header("content-type") {
            let ct_lower = content_type.to_lowercase();
            if !ct_lower.contains("json") && !ct_lower.contains("text") {
                debug!("[{}] Skipping non-text content type: {}", self.context_id, content_type);
                self.should_scrub = false;
                self.add_http_response_header("X-WASM-Scrub", "non-text");
                return Action::Continue;
            }
        }

        // Get content length if available to check size limit
        if let Some(length) = self.get_http_response_header("content-length") {
            if let Ok(size) = length.parse::<usize>() {
                // Skip if body is too large
                if size > self.config.max_body_size_bytes {
                    warn!("[{}] Body too large ({} bytes), skipping scrubbing",
                          self.context_id, size);
                    self.should_scrub = false;
                    self.add_http_response_header("X-WASM-Scrub", "too-large");
                    return Action::Continue;
                }
            }
        }

        // Remove content-length header as we may modify the body
        self.set_http_response_header("content-length", None);
        self.add_http_response_header("X-WASM-Scrub", "will-scrub");

        Action::Continue
    }

    fn on_http_response_body(&mut self, body_size: usize, end_of_stream: bool) -> Action {
        info!("DIAG: on_http_response_body called for context_id={}, body_size={}, end_of_stream={}",
              self.context_id, body_size, end_of_stream);
        
        if !self.should_scrub {
            info!("DIAG: skipping scrub (should_scrub=false)");
            return Action::Continue;
        }

        // Track accumulated body size for later retrieval
        self.accumulated_body_size += body_size;

        // Only process when we have the complete body
        if !end_of_stream {
            return Action::Continue;
        }

        // Check size limit
        if self.accumulated_body_size > self.config.max_body_size_bytes {
            warn!("[{}] Body too large ({} bytes), passing through",
                  self.context_id, self.accumulated_body_size);
            return Action::Continue;
        }

        // Get the full accumulated body
        let full_body = match self.get_http_response_body(0, self.accumulated_body_size) {
            Some(body) => body,
            None => {
                warn!("[{}] Failed to get response body", self.context_id);
                return Action::Continue;
            }
        };

        // Perform PII redaction
        let result = self.redact_pii(&full_body);

        if result.redacted {
            info!("[{}] Redacted {} PII patterns: {:?}",
                  self.context_id, result.match_count, result.matched_patterns);

            // NOTE: Cannot add headers in on_http_response_body - headers already sent
            // Headers must be added in on_http_response_headers callback
            
            // Replace the response body with redacted content
            self.set_http_response_body(0, full_body.len(), &result.content);
        } else {
            debug!("[{}] No PII patterns found in response", self.context_id);
        }

        Action::Continue
    }
}

// =============================================================================
// Plugin Entry Point
// =============================================================================

proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Info);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> {
        Box::new(PiiScrubberRoot::new())
    });
}}

// =============================================================================
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = PluginConfig::default();
        assert!(config.patterns.credit_card);
        assert!(config.patterns.ssn);
        assert!(config.patterns.email);
        assert!(!config.patterns.phone_us);
    }

    #[test]
    fn test_bypass_path_exact() {
        let config = PluginConfig {
            bypass_paths: vec!["/health".to_string()],
            ..Default::default()
        };
        let ctx = PiiScrubberHttp::new(1, config);
        
        assert!(ctx.should_bypass_path("/health"));
        assert!(!ctx.should_bypass_path("/api/user"));
    }

    #[test]
    fn test_bypass_path_wildcard() {
        let config = PluginConfig {
            bypass_paths: vec!["/api/internal/*".to_string()],
            ..Default::default()
        };
        let ctx = PiiScrubberHttp::new(1, config);
        
        assert!(ctx.should_bypass_path("/api/internal/debug"));
        assert!(ctx.should_bypass_path("/api/internal/metrics"));
        assert!(!ctx.should_bypass_path("/api/user"));
    }
}
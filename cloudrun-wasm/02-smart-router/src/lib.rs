//! Smart Router - A/B Testing and Canary Deployment Wasm Plugin
//!
//! This proxy-wasm plugin inspects HTTP request headers and cookies
//! to make routing decisions for A/B testing and canary deployments.
//!
//! Extension Point:
//! - Location: Request Path
//! - Callback: `on_http_request_headers`

use log::{info, warn};
use proxy_wasm::traits::{Context, HttpContext, RootContext};
use proxy_wasm::types::{Action, ContextType};
use serde::Deserialize;
use std::collections::HashMap;

// =============================================================================
// Configuration
// =============================================================================

// Plugin configuration loaded from Envoy config
#[derive(Debug, Clone, Deserialize)]
struct RoutingRule {
    name: String,
    priority: i32,
    conditions: Vec<Condition>,
    target: String,
    #[serde(default)]
    add_headers: HashMap<String, String>,
}

#[derive(Debug, Clone, Deserialize)]
struct Condition {
    #[serde(rename = "type")]
    condition_type: String,
    key: String,
    operator: String,
    value: String,
}

// Plugin configuration loaded from Envoy config
#[derive(Debug, Clone, Deserialize)]
struct PluginConfig {
    #[serde(default = "default_log_level")]
    log_level: String,

    #[serde(default = "default_target")]
    default_target: String,

    #[serde(default)]
    debug: bool,

    #[serde(default)]
    rules: Vec<RoutingRule>,
}

fn default_log_level() -> String {
    "info".to_string()
}

fn default_target() -> String {
    "v1".to_string()
}

impl Default for PluginConfig {
    fn default() -> Self {
        Self {
            log_level: default_log_level(),
            default_target: default_target(),
            debug: false,
            rules: vec![],
        }
    }
}

// =============================================================================
// Root Context
// =============================================================================

struct SmartRouterRoot {
    config: PluginConfig,
}

impl SmartRouterRoot {
    fn new() -> Self {
        Self {
            config: PluginConfig::default(),
        }
    }
}

impl Context for SmartRouterRoot {}

impl RootContext for SmartRouterRoot {
    fn on_configure(&mut self, _plugin_configuration_size: usize) -> bool {
        // Try to get configuration from Envoy
        if let Some(config_bytes) = self.get_plugin_configuration() {
            match serde_json::from_slice::<PluginConfig>(&config_bytes) {
                Ok(config) => {
                    info!("Smart Router configured with {} rules", config.rules.len());
                    self.config = config;
                }
                Err(e) => {
                    warn!("Failed to parse config, using defaults: {}", e);
                }
            }
        } else {
            info!("No configuration provided, using defaults");
        }
        true
    }

    fn create_http_context(&self, context_id: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(SmartRouterHttp::new(context_id, self.config.clone())))
    }

    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }
}

// =============================================================================
// HTTP Context
// =============================================================================

// HTTP context for processing individual requests
struct SmartRouterHttp {
    context_id: u32,
    config: PluginConfig,
}

impl SmartRouterHttp {
    fn new(context_id: u32, config: PluginConfig) -> Self {
        Self {
            context_id,
            config,
        }
    }
}

impl Context for SmartRouterHttp {}

impl HttpContext for SmartRouterHttp {
    fn on_http_request_headers(&mut self, _num_headers: usize, _end_of_stream: bool) -> Action {
        info!("[{}] Processing request", self.context_id);

        // Get current path
        let current_path = self.get_http_request_header(":path").unwrap_or_else(|| "/".to_string());

        // Collect all headers for evaluation
        let mut headers = HashMap::new();
        let all_headers = self.get_http_request_headers();
        for (name, value) in all_headers {
            headers.insert(name.to_lowercase(), value);
        }

        // Parse cookies
        let cookies = parse_cookies(&headers.get("cookie").cloned().unwrap_or_default());

        // Sort rules by priority (lower number = higher priority)
        let mut sorted_rules = self.config.rules.clone();
        sorted_rules.sort_by_key(|rule| rule.priority);

        // Find matching rule
        let mut matched_rule = None;
        for rule in &sorted_rules {
            if evaluate_conditions(&rule.conditions, &headers, &cookies) {
                info!("[{}] Rule '{}' matched", self.context_id, rule.name);
                matched_rule = Some(rule);
                break;
            }
        }

        // Use matched rule or default
        let (target, reason, headers_to_add) = if let Some(rule) = matched_rule {
            (rule.target.clone(), rule.name.clone(), rule.add_headers.clone())
        } else {
            (self.config.default_target.clone(), "default".to_string(), HashMap::new())
        };

        info!("[{}] Routing decision: target={} reason={}", self.context_id, target, reason);

        // Add routing headers from rule or defaults
        self.add_http_request_header("X-Routed-By", "smart-router");
        self.add_http_request_header("X-Route-Reason", &reason);
        
        // Add any additional headers from the rule
        for (key, value) in &headers_to_add {
            self.add_http_request_header(key, value);
        }

        // If target v2 and not already /v2, rewrite path
        if target == "v2" && !current_path.starts_with("/v2") {
            let new_path = format!("/v2{}", current_path);
            self.set_http_request_header(":path", Some(&new_path));
            info!("[{}] Rewrote path from {} to {}", self.context_id, current_path, new_path);
        }

        Action::Continue
    }

    fn on_http_response_headers(&mut self, _num_headers: usize, _end_of_stream: bool) -> Action {
        self.add_http_response_header("X-Smart-Router", "active");
        Action::Continue
    }
}

// =============================================================================
// Plugin Entry Point
// =============================================================================

proxy_wasm::main! {{
    proxy_wasm::set_log_level(proxy_wasm::types::LogLevel::Info);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> {
        Box::new(SmartRouterRoot::new())
    });
}}

// =============================================================================
// Helper Functions
// =============================================================================

fn parse_cookies(cookie_header: &str) -> HashMap<String, String> {
    let mut cookies = HashMap::new();
    for cookie in cookie_header.split(';') {
        let cookie = cookie.trim();
        if let Some((key, value)) = cookie.split_once('=') {
            cookies.insert(key.trim().to_lowercase(), value.trim().to_string());
        }
    }
    cookies
}

fn evaluate_conditions(
    conditions: &[Condition],
    headers: &HashMap<String, String>,
    cookies: &HashMap<String, String>,
) -> bool {
    for condition in conditions {
        let value = match condition.condition_type.as_str() {
            "header" => headers.get(&condition.key.to_lowercase()).cloned(),
            "cookie" => cookies.get(&condition.key.to_lowercase()).cloned(),
            _ => {
                warn!("Unknown condition type: {}", condition.condition_type);
                None
            }
        };

        let matches = match condition.operator.as_str() {
            "equals" => value.as_ref().map_or(false, |v| v == &condition.value),
            "contains" => value.as_ref().map_or(false, |v| v.contains(&condition.value)),
            "regex" => {
                if let Some(v) = value {
                    if let Ok(regex) = regex::Regex::new(&condition.value) {
                        regex.is_match(&v)
                    } else {
                        warn!("Invalid regex pattern: {}", condition.value);
                        false
                    }
                } else {
                    false
                }
            }
            _ => {
                warn!("Unknown operator: {}", condition.operator);
                false
            }
        };

        if !matches {
            return false; // All conditions must match
        }
    }
    true // All conditions matched
}

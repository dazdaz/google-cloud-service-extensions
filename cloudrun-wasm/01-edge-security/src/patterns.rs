//! PII Pattern Matching and Redaction
//!
//! This module uses regex-lite for efficient PII pattern matching.
//! Patterns are compiled once using OnceLock for optimal performance
//! in the Wasm sandbox's strict CPU budget (~1-2ms).
//!
//! # Technical Deep Dive: Using Regex in Wasm Extensions
//!
//! When building custom validators using Service Extensions (Proxy-Wasm),
//! the strict resource constraints of the sandbox require efficient memory
//! management. The key constraint is that regex compilation (Regex::new)
//! is expensive and must NOT happen in the request path.
//!
//! ## The Golden Pattern: Global Initialization with OnceLock
//!
//! ```rust,ignore
//! static PATTERN: OnceLock<Regex> = OnceLock::new();
//!
//! fn on_http_request_headers(...) {
//!     let re = PATTERN.get_or_init(|| Regex::new(r"...").unwrap());
//!     // ... use re
//! }
//! ```
//!
//! We use regex-lite instead of regex to reduce Wasm binary size by ~500KB.

use regex_lite::Regex;
use std::collections::HashSet;
use std::sync::OnceLock;

// =============================================================================
// Global Pattern Cache (compiled once, reused everywhere)
// =============================================================================

/// Credit card with dashes: 4111-1111-1111-1111
static CREDIT_CARD_DASHES: OnceLock<Regex> = OnceLock::new();

/// Credit card without dashes: 4111111111111111 (16 consecutive digits)
static CREDIT_CARD_NO_DASHES: OnceLock<Regex> = OnceLock::new();

/// SSN: 123-45-6789
static SSN_PATTERN: OnceLock<Regex> = OnceLock::new();

/// Email: user@example.com
static EMAIL_PATTERN: OnceLock<Regex> = OnceLock::new();

/// US Phone: 555-123-4567 or 555.123.4567
static PHONE_US_PATTERN: OnceLock<Regex> = OnceLock::new();

/// Get the credit card (with dashes) regex, compiling it once if needed
fn credit_card_dashes_regex() -> &'static Regex {
    CREDIT_CARD_DASHES.get_or_init(|| {
        // Matches: 4111-1111-1111-1111
        Regex::new(r"\b(\d{4})-(\d{4})-(\d{4})-(\d{4})\b").unwrap()
    })
}

/// Get the credit card (no dashes) regex, compiling it once if needed
fn credit_card_no_dashes_regex() -> &'static Regex {
    CREDIT_CARD_NO_DASHES.get_or_init(|| {
        // Matches: 4111111111111111 (exactly 16 digits, not part of longer number)
        Regex::new(r"\b(\d{12})(\d{4})\b").unwrap()
    })
}

/// Get the SSN regex, compiling it once if needed
fn ssn_regex() -> &'static Regex {
    SSN_PATTERN.get_or_init(|| {
        // Matches: 123-45-6789
        Regex::new(r"\b\d{3}-\d{2}-\d{4}\b").unwrap()
    })
}

/// Get the email regex, compiling it once if needed
fn email_regex() -> &'static Regex {
    EMAIL_PATTERN.get_or_init(|| {
        // Matches: user@example.com, john.doe+tag@sub.domain.org
        Regex::new(r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}").unwrap()
    })
}

/// Get the US phone regex, compiling it once if needed
fn phone_us_regex() -> &'static Regex {
    PHONE_US_PATTERN.get_or_init(|| {
        // Matches: 555-123-4567 or 555.123.4567
        Regex::new(r"\b(\d{3})[-.](\d{3})[-.](\d{4})\b").unwrap()
    })
}

// =============================================================================
// Pattern Matcher
// =============================================================================

/// Result of a redaction operation
#[derive(Debug, Clone)]
pub struct RedactionResult {
    /// Whether any redactions were made
    pub redacted: bool,
    /// Number of patterns matched
    pub match_count: u32,
    /// Names of patterns that matched
    pub matched_patterns: HashSet<String>,
    /// The sanitized content
    pub content: Vec<u8>,
}

/// Matcher for PII patterns with configurable pattern enablement
pub struct PiiPatternMatcher {
    enable_credit_card: bool,
    enable_ssn: bool,
    enable_email: bool,
    enable_phone_us: bool,
}

impl PiiPatternMatcher {
    /// Create a new pattern matcher with specified patterns enabled
    pub fn new(
        enable_credit_card: bool,
        enable_ssn: bool,
        enable_email: bool,
        enable_phone_us: bool,
    ) -> Self {
        Self {
            enable_credit_card,
            enable_ssn,
            enable_email,
            enable_phone_us,
        }
    }

    /// Create a matcher with all patterns enabled
    #[allow(dead_code)]
    pub fn all() -> Self {
        Self::new(true, true, true, true)
    }

    /// Create a matcher with default patterns (no phone)
    #[allow(dead_code)]
    pub fn default_patterns() -> Self {
        Self::new(true, true, true, false)
    }

    /// Perform redaction on the input bytes
    pub fn redact(&self, input: &[u8]) -> RedactionResult {
        // Convert to string for processing
        let input_str = match std::str::from_utf8(input) {
            Ok(s) => s,
            Err(_) => {
                // If not valid UTF-8, return unchanged
                return RedactionResult {
                    redacted: false,
                    match_count: 0,
                    matched_patterns: HashSet::new(),
                    content: input.to_vec(),
                };
            }
        };

        let mut result = input_str.to_string();
        let mut match_count: u32 = 0;
        let mut matched_patterns = HashSet::new();

        // Apply each enabled pattern
        if self.enable_credit_card {
            let (new_result, count) = redact_credit_cards(&result);
            if count > 0 {
                matched_patterns.insert("credit_card".to_string());
                match_count += count;
                result = new_result;
            }
        }

        if self.enable_ssn {
            let (new_result, count) = redact_ssn(&result);
            if count > 0 {
                matched_patterns.insert("ssn".to_string());
                match_count += count;
                result = new_result;
            }
        }

        if self.enable_email {
            let (new_result, count) = redact_email(&result);
            if count > 0 {
                matched_patterns.insert("email".to_string());
                match_count += count;
                result = new_result;
            }
        }

        if self.enable_phone_us {
            let (new_result, count) = redact_phone_us(&result);
            if count > 0 {
                matched_patterns.insert("phone_us".to_string());
                match_count += count;
                result = new_result;
            }
        }

        RedactionResult {
            redacted: match_count > 0,
            match_count,
            matched_patterns,
            content: result.into_bytes(),
        }
    }
}

// =============================================================================
// Pattern Matching Functions using regex-lite
// =============================================================================

/// Redact credit card numbers
/// - Format: 1234-5678-9012-3456 → XXXX-XXXX-XXXX-3456
/// - Format: 1234567890123456 → XXXXXXXXXXXX3456
fn redact_credit_cards(input: &str) -> (String, u32) {
    let mut count = 0u32;

    // First handle dashed format: 4111-1111-1111-1111 → XXXX-XXXX-XXXX-1111
    let re_dashes = credit_card_dashes_regex();
    let result = re_dashes.replace_all(input, |caps: &regex_lite::Captures| {
        count += 1;
        format!("XXXX-XXXX-XXXX-{}", &caps[4])
    });

    // Then handle no-dash format: 4111111111111111 → XXXXXXXXXXXX1111
    let re_no_dashes = credit_card_no_dashes_regex();
    let result = re_no_dashes.replace_all(&result, |caps: &regex_lite::Captures| {
        count += 1;
        format!("XXXXXXXXXXXX{}", &caps[2])
    });

    (result.into_owned(), count)
}

/// Redact SSN numbers: 123-45-6789 → XXX-XX-XXXX
fn redact_ssn(input: &str) -> (String, u32) {
    let re = ssn_regex();
    let mut count = 0u32;

    let result = re.replace_all(input, |_caps: &regex_lite::Captures| {
        count += 1;
        "XXX-XX-XXXX"
    });

    (result.into_owned(), count)
}

/// Redact email addresses: user@example.com → [EMAIL REDACTED]
fn redact_email(input: &str) -> (String, u32) {
    let re = email_regex();
    let mut count = 0u32;

    let result = re.replace_all(input, |_caps: &regex_lite::Captures| {
        count += 1;
        "[EMAIL REDACTED]"
    });

    (result.into_owned(), count)
}

/// Redact US phone numbers: 555-123-4567 → (XXX) XXX-4567
fn redact_phone_us(input: &str) -> (String, u32) {
    let re = phone_us_regex();
    let mut count = 0u32;

    let result = re.replace_all(input, |caps: &regex_lite::Captures| {
        count += 1;
        format!("(XXX) XXX-{}", &caps[3])
    });

    (result.into_owned(), count)
}

// =============================================================================
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_credit_card_redaction() {
        let matcher = PiiPatternMatcher::default_patterns();
        let input = b"Card: 4111-1111-1111-1111";
        let result = matcher.redact(input);

        assert!(result.redacted);
        assert_eq!(result.match_count, 1);
        assert!(result.matched_patterns.contains("credit_card"));
        assert_eq!(
            String::from_utf8_lossy(&result.content),
            "Card: XXXX-XXXX-XXXX-1111"
        );
    }

    #[test]
    fn test_credit_card_no_dash_redaction() {
        let matcher = PiiPatternMatcher::default_patterns();
        let input = b"Card: 4111111111111111";
        let result = matcher.redact(input);

        assert!(result.redacted);
        assert_eq!(result.match_count, 1);
        assert!(result.matched_patterns.contains("credit_card"));
        assert_eq!(
            String::from_utf8_lossy(&result.content),
            "Card: XXXXXXXXXXXX1111"
        );
    }

    #[test]
    fn test_ssn_redaction() {
        let matcher = PiiPatternMatcher::default_patterns();
        let input = b"SSN: 123-45-6789";
        let result = matcher.redact(input);

        assert!(result.redacted);
        assert_eq!(result.match_count, 1);
        assert!(result.matched_patterns.contains("ssn"));
        assert_eq!(
            String::from_utf8_lossy(&result.content),
            "SSN: XXX-XX-XXXX"
        );
    }

    #[test]
    fn test_email_redaction() {
        let matcher = PiiPatternMatcher::default_patterns();
        let input = b"Email: john.doe@example.com";
        let result = matcher.redact(input);

        assert!(result.redacted);
        assert_eq!(result.match_count, 1);
        assert!(result.matched_patterns.contains("email"));
        assert_eq!(
            String::from_utf8_lossy(&result.content),
            "Email: [EMAIL REDACTED]"
        );
    }

    #[test]
    fn test_phone_redaction_when_enabled() {
        let matcher = PiiPatternMatcher::all();
        let input = b"Phone: 555-123-4567";
        let result = matcher.redact(input);

        assert!(result.redacted);
        assert!(result.matched_patterns.contains("phone_us"));
        assert_eq!(
            String::from_utf8_lossy(&result.content),
            "Phone: (XXX) XXX-4567"
        );
    }

    #[test]
    fn test_phone_not_redacted_by_default() {
        let matcher = PiiPatternMatcher::default_patterns();
        let input = b"Phone: 555-123-4567";
        let result = matcher.redact(input);

        // Phone is disabled by default
        assert!(!result.matched_patterns.contains("phone_us"));
        assert_eq!(
            String::from_utf8_lossy(&result.content),
            "Phone: 555-123-4567"
        );
    }

    #[test]
    fn test_multiple_patterns() {
        let matcher = PiiPatternMatcher::default_patterns();
        let input = b"SSN: 123-45-6789, Card: 4111-1111-1111-1111, Email: test@example.com";
        let result = matcher.redact(input);

        assert!(result.redacted);
        assert_eq!(result.match_count, 3);
        assert!(result.matched_patterns.contains("ssn"));
        assert!(result.matched_patterns.contains("credit_card"));
        assert!(result.matched_patterns.contains("email"));
        assert_eq!(
            String::from_utf8_lossy(&result.content),
            "SSN: XXX-XX-XXXX, Card: XXXX-XXXX-XXXX-1111, Email: [EMAIL REDACTED]"
        );
    }

    #[test]
    fn test_no_pii() {
        let matcher = PiiPatternMatcher::default_patterns();
        let input = b"Hello, World! This is a test message.";
        let result = matcher.redact(input);

        assert!(!result.redacted);
        assert_eq!(result.match_count, 0);
        assert!(result.matched_patterns.is_empty());
        assert_eq!(result.content, input.to_vec());
    }

    #[test]
    fn test_json_redaction() {
        let matcher = PiiPatternMatcher::default_patterns();
        let input = br#"{"ssn": "123-45-6789", "card": "4111-1111-1111-1111"}"#;
        let result = matcher.redact(input);

        assert!(result.redacted);
        assert_eq!(
            String::from_utf8_lossy(&result.content),
            r#"{"ssn": "XXX-XX-XXXX", "card": "XXXX-XXXX-XXXX-1111"}"#
        );
    }

    #[test]
    fn test_multiple_same_pattern() {
        let matcher = PiiPatternMatcher::default_patterns();
        let input = b"Card1: 4111-1111-1111-1111, Card2: 5500-0000-0000-0004";
        let result = matcher.redact(input);

        assert!(result.redacted);
        assert_eq!(result.match_count, 2);
        assert_eq!(
            String::from_utf8_lossy(&result.content),
            "Card1: XXXX-XXXX-XXXX-1111, Card2: XXXX-XXXX-XXXX-0004"
        );
    }

    #[test]
    fn test_preserves_surrounding_text() {
        let matcher = PiiPatternMatcher::default_patterns();
        let input = b"Before 123-45-6789 After";
        let result = matcher.redact(input);

        assert_eq!(
            String::from_utf8_lossy(&result.content),
            "Before XXX-XX-XXXX After"
        );
    }

    #[test]
    fn test_phone_with_dots() {
        let matcher = PiiPatternMatcher::all();
        let input = b"Phone: 555.123.4567";
        let result = matcher.redact(input);

        assert!(result.redacted);
        assert!(result.matched_patterns.contains("phone_us"));
        assert_eq!(
            String::from_utf8_lossy(&result.content),
            "Phone: (XXX) XXX-4567"
        );
    }

    #[test]
    fn test_complex_email() {
        let matcher = PiiPatternMatcher::default_patterns();
        let input = b"Email: john.doe+tag@sub.domain.org";
        let result = matcher.redact(input);

        assert!(result.redacted);
        assert!(result.matched_patterns.contains("email"));
        assert_eq!(
            String::from_utf8_lossy(&result.content),
            "Email: [EMAIL REDACTED]"
        );
    }
}
//! PII Pattern Matching and Redaction
//!
//! This module contains simple string-based patterns for detecting PII
//! and the logic for redacting matched content.
//!
//! NOTE: We use simple character-by-character matching instead of regex
//! because the regex crate is not compatible with GCP Service Extensions
//! WASM runtime (causes TerminationException panic).

use std::collections::HashSet;

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
// Pattern Matching Functions (No Regex)
// =============================================================================

/// Check if a character is a digit
fn is_digit(c: char) -> bool {
    c.is_ascii_digit()
}

/// Redact credit card numbers in format: 1234-5678-9012-3456
/// Replaces with: XXXX-XXXX-XXXX-3456 (preserves last 4 digits)
fn redact_credit_cards(input: &str) -> (String, u32) {
    let mut result = String::with_capacity(input.len());
    let chars: Vec<char> = input.chars().collect();
    let mut i = 0;
    let mut count = 0;

    while i < chars.len() {
        // Try to match credit card pattern: DDDD-DDDD-DDDD-DDDD
        if i + 18 < chars.len() {
            let potential_cc: String = chars[i..i + 19].iter().collect();
            if is_credit_card_format(&potential_cc) {
                // Extract last 4 digits and redact
                let last_four = &potential_cc[15..19];
                result.push_str("XXXX-XXXX-XXXX-");
                result.push_str(last_four);
                i += 19;
                count += 1;
                continue;
            }
        }

        // Try to match credit card without dashes: 16 consecutive digits
        if i + 15 < chars.len() {
            let all_digits = chars[i..i + 16].iter().all(|c| is_digit(*c));
            if all_digits {
                // Check it's not part of a longer number
                let before_ok = i == 0 || !is_digit(chars[i - 1]);
                let after_ok = i + 16 >= chars.len() || !is_digit(chars[i + 16]);
                if before_ok && after_ok {
                    let last_four: String = chars[i + 12..i + 16].iter().collect();
                    result.push_str("XXXXXXXXXXXX");
                    result.push_str(&last_four);
                    i += 16;
                    count += 1;
                    continue;
                }
            }
        }

        result.push(chars[i]);
        i += 1;
    }

    (result, count)
}

/// Check if string matches DDDD-DDDD-DDDD-DDDD format
fn is_credit_card_format(s: &str) -> bool {
    let chars: Vec<char> = s.chars().collect();
    if chars.len() != 19 {
        return false;
    }

    // Check pattern: 4 digits, dash, 4 digits, dash, 4 digits, dash, 4 digits
    for (idx, c) in chars.iter().enumerate() {
        match idx {
            4 | 9 | 14 => {
                if *c != '-' {
                    return false;
                }
            }
            _ => {
                if !is_digit(*c) {
                    return false;
                }
            }
        }
    }
    true
}

/// Redact SSN numbers in format: 123-45-6789
/// Replaces with: XXX-XX-XXXX
fn redact_ssn(input: &str) -> (String, u32) {
    let mut result = String::with_capacity(input.len());
    let chars: Vec<char> = input.chars().collect();
    let mut i = 0;
    let mut count = 0;

    while i < chars.len() {
        // Try to match SSN pattern: DDD-DD-DDDD (11 chars)
        if i + 10 < chars.len() {
            let potential_ssn: String = chars[i..i + 11].iter().collect();
            if is_ssn_format(&potential_ssn) {
                // Check word boundaries
                let before_ok = i == 0 || !chars[i - 1].is_alphanumeric();
                let after_ok = i + 11 >= chars.len() || !chars[i + 11].is_alphanumeric();
                if before_ok && after_ok {
                    result.push_str("XXX-XX-XXXX");
                    i += 11;
                    count += 1;
                    continue;
                }
            }
        }

        result.push(chars[i]);
        i += 1;
    }

    (result, count)
}

/// Check if string matches DDD-DD-DDDD format
fn is_ssn_format(s: &str) -> bool {
    let chars: Vec<char> = s.chars().collect();
    if chars.len() != 11 {
        return false;
    }

    // Check pattern: 3 digits, dash, 2 digits, dash, 4 digits
    for (idx, c) in chars.iter().enumerate() {
        match idx {
            3 | 6 => {
                if *c != '-' {
                    return false;
                }
            }
            _ => {
                if !is_digit(*c) {
                    return false;
                }
            }
        }
    }
    true
}

/// Redact email addresses
/// Replaces with: [EMAIL REDACTED]
fn redact_email(input: &str) -> (String, u32) {
    let mut result = String::with_capacity(input.len());
    let chars: Vec<char> = input.chars().collect();
    let mut i = 0;
    let mut count = 0;

    while i < chars.len() {
        // Look for @ symbol
        if chars[i] == '@' {
            // Find the start of the email (local part)
            let start = find_email_start(&chars, i);
            // Find the end of the email (domain part)
            let end = find_email_end(&chars, i);

            if start < i && end > i + 1 {
                // Valid email found - check for valid domain with dot
                let domain: String = chars[i + 1..end].iter().collect();
                if domain.contains('.') && !domain.starts_with('.') && !domain.ends_with('.') {
                    // Remove the local part we already added
                    let to_remove = i - start;
                    for _ in 0..to_remove {
                        result.pop();
                    }
                    result.push_str("[EMAIL REDACTED]");
                    i = end;
                    count += 1;
                    continue;
                }
            }
        }

        result.push(chars[i]);
        i += 1;
    }

    (result, count)
}

/// Find the start index of an email address (before @)
fn find_email_start(chars: &[char], at_pos: usize) -> usize {
    if at_pos == 0 {
        return at_pos;
    }

    let mut start = at_pos;
    for j in (0..at_pos).rev() {
        let c = chars[j];
        if c.is_alphanumeric() || c == '.' || c == '_' || c == '%' || c == '+' || c == '-' {
            start = j;
        } else {
            break;
        }
    }
    start
}

/// Find the end index of an email address (after @)
fn find_email_end(chars: &[char], at_pos: usize) -> usize {
    let mut end = at_pos + 1;
    for j in (at_pos + 1)..chars.len() {
        let c = chars[j];
        if c.is_alphanumeric() || c == '.' || c == '-' {
            end = j + 1;
        } else {
            break;
        }
    }
    end
}

/// Redact US phone numbers in format: 555-123-4567 or 555.123.4567
/// Replaces with: (XXX) XXX-4567 (preserves last 4 digits)
fn redact_phone_us(input: &str) -> (String, u32) {
    let mut result = String::with_capacity(input.len());
    let chars: Vec<char> = input.chars().collect();
    let mut i = 0;
    let mut count = 0;

    while i < chars.len() {
        // Try to match phone pattern: DDD-DDD-DDDD or DDD.DDD.DDDD (12 chars)
        if i + 11 < chars.len() {
            let potential_phone: String = chars[i..i + 12].iter().collect();
            if is_phone_format(&potential_phone) {
                // Check word boundaries
                let before_ok = i == 0 || !chars[i - 1].is_alphanumeric();
                let after_ok = i + 12 >= chars.len() || !chars[i + 12].is_alphanumeric();
                if before_ok && after_ok {
                    let last_four = &potential_phone[8..12];
                    result.push_str("(XXX) XXX-");
                    result.push_str(last_four);
                    i += 12;
                    count += 1;
                    continue;
                }
            }
        }

        result.push(chars[i]);
        i += 1;
    }

    (result, count)
}

/// Check if string matches DDD-DDD-DDDD or DDD.DDD.DDDD format
fn is_phone_format(s: &str) -> bool {
    let chars: Vec<char> = s.chars().collect();
    if chars.len() != 12 {
        return false;
    }

    // Determine separator (must be consistent)
    let sep = chars[3];
    if sep != '-' && sep != '.' {
        return false;
    }

    // Check pattern: 3 digits, sep, 3 digits, sep, 4 digits
    for (idx, c) in chars.iter().enumerate() {
        match idx {
            3 | 7 => {
                if *c != sep {
                    return false;
                }
            }
            _ => {
                if !is_digit(*c) {
                    return false;
                }
            }
        }
    }
    true
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
}
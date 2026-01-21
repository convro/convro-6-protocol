use rand::Rng;

/// Generate random Convro Number in format: +99 XXX XXX
///
/// Namespace: 100,000 - 999,999 (900,000 numbers)
/// Format: +99 {first 3 digits} {last 3 digits}
///
/// Example: +99 123 456
pub fn generate_random() -> String {
    let mut rng = rand::thread_rng();
    let number = rng.gen_range(100_000..1_000_000);
    format_convro_number(number)
}

/// Generate sequential Convro Number (for testing)
pub fn generate_sequential(sequence: u32) -> String {
    let number = 100_000 + (sequence % 900_000);
    format_convro_number(number)
}

/// Format number as Convro Number
fn format_convro_number(number: u32) -> String {
    let first_three = number / 1000;
    let last_three = number % 1000;
    format!("+99 {} {}", first_three, last_three)
}

/// Validate Convro Number format
pub fn is_valid_format(convro_number: &str) -> bool {
    // Format: +99 XXX XXX
    let parts: Vec<&str> = convro_number.split_whitespace().collect();

    if parts.len() != 3 {
        return false;
    }

    if parts[0] != "+99" {
        return false;
    }

    // Check that parts[1] and parts[2] are 3-digit numbers
    parts[1].len() == 3
        && parts[2].len() == 3
        && parts[1].chars().all(|c| c.is_ascii_digit())
        && parts[2].chars().all(|c| c.is_ascii_digit())
}

/// Parse Convro Number to numeric value
pub fn parse_convro_number(convro_number: &str) -> Option<u32> {
    if !is_valid_format(convro_number) {
        return None;
    }

    let parts: Vec<&str> = convro_number.split_whitespace().collect();
    let first_three: u32 = parts[1].parse().ok()?;
    let last_three: u32 = parts[2].parse().ok()?;

    Some(first_three * 1000 + last_three)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_random() {
        let number = generate_random();
        assert!(is_valid_format(&number));
        assert!(number.starts_with("+99"));
    }

    #[test]
    fn test_generate_sequential() {
        let number = generate_sequential(0);
        assert_eq!(number, "+99 100 000");

        let number2 = generate_sequential(123456);
        assert_eq!(number2, "+99 223 456");
    }

    #[test]
    fn test_validate_format() {
        assert!(is_valid_format("+99 123 456"));
        assert!(is_valid_format("+99 100 000"));
        assert!(is_valid_format("+99 999 999"));

        assert!(!is_valid_format("+99123456"));  // No spaces
        assert!(!is_valid_format("+98 123 456")); // Wrong prefix
        assert!(!is_valid_format("+99 12 345"));   // Wrong digit count
        assert!(!is_valid_format("+99 abc 456"));  // Non-numeric
    }

    #[test]
    fn test_parse_convro_number() {
        assert_eq!(parse_convro_number("+99 123 456"), Some(123456));
        assert_eq!(parse_convro_number("+99 100 000"), Some(100000));
        assert_eq!(parse_convro_number("+99 999 999"), Some(999999));
        assert_eq!(parse_convro_number("invalid"), None);
    }

    #[test]
    fn test_generate_unique() {
        // Generate 1000 numbers and check uniqueness
        use std::collections::HashSet;
        let mut numbers = HashSet::new();

        for _ in 0..1000 {
            let number = generate_random();
            assert!(is_valid_format(&number));
            numbers.insert(number);
        }

        // Should have close to 1000 unique numbers (with high probability)
        assert!(numbers.len() > 990);
    }
}

use argon2::{
    password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};

use crate::errors::{AppError, AppResult};

/// Hash password using Argon2id
pub fn hash_password(password: &str) -> AppResult<String> {
    let salt = SaltString::generate(&mut OsRng);
    let argon2 = Argon2::default();

    let password_hash = argon2
        .hash_password(password.as_bytes(), &salt)
        .map_err(|e| AppError::InternalError(format!("Password hashing failed: {}", e)))?
        .to_string();

    Ok(password_hash)
}

/// Verify password against hash
pub fn verify_password(password: &str, hash: &str) -> AppResult<()> {
    let parsed_hash = PasswordHash::new(hash)
        .map_err(|e| AppError::InternalError(format!("Invalid password hash: {}", e)))?;

    Argon2::default()
        .verify_password(password.as_bytes(), &parsed_hash)
        .map_err(|_| AppError::Unauthorized("Invalid credentials".to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hash_and_verify_password() {
        let password = "SecurePassword123!";
        let hash = hash_password(password).expect("Failed to hash password");

        // Should verify correctly
        assert!(verify_password(password, &hash).is_ok());

        // Should fail with wrong password
        assert!(verify_password("WrongPassword", &hash).is_err());
    }

    #[test]
    fn test_hash_generates_different_salts() {
        let password = "SamePassword123!";
        let hash1 = hash_password(password).expect("Failed to hash");
        let hash2 = hash_password(password).expect("Failed to hash");

        // Same password should generate different hashes (different salts)
        assert_ne!(hash1, hash2);

        // But both should verify
        assert!(verify_password(password, &hash1).is_ok());
        assert!(verify_password(password, &hash2).is_ok());
    }

    #[test]
    fn test_verify_invalid_hash() {
        let result = verify_password("password", "invalid_hash");
        assert!(result.is_err());
    }
}

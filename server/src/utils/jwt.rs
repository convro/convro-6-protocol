use chrono::{Duration, Utc};
use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::errors::{AppError, AppResult};

/// JWT Claims structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Claims {
    pub sub: Uuid,                // User ID
    pub convro_number: String,    // Convro Number
    pub username: String,          // Username
    pub token_type: String,        // "access" or "refresh"
    pub iat: i64,                  // Issued at
    pub exp: i64,                  // Expiration
    pub jti: String,               // JWT ID (for revocation)
}

/// Encode access token (1 hour expiry)
pub fn encode_access_token(
    user_id: Uuid,
    convro_number: String,
    username: String,
) -> AppResult<String> {
    let secret = get_jwt_secret()?;
    let expiry = std::env::var("JWT_ACCESS_EXPIRY")
        .unwrap_or_else(|_| "3600".to_string())
        .parse::<i64>()
        .unwrap_or(3600);

    encode_token(user_id, convro_number, username, "access", expiry, &secret)
}

/// Encode refresh token (30 days expiry)
pub fn encode_refresh_token(
    user_id: Uuid,
    convro_number: String,
    username: String,
) -> AppResult<String> {
    let secret = get_jwt_secret()?;
    let expiry = std::env::var("JWT_REFRESH_EXPIRY")
        .unwrap_or_else(|_| "2592000".to_string())
        .parse::<i64>()
        .unwrap_or(2592000);

    encode_token(user_id, convro_number, username, "refresh", expiry, &secret)
}

/// Internal: Encode JWT with given parameters
fn encode_token(
    user_id: Uuid,
    convro_number: String,
    username: String,
    token_type: &str,
    expiry_seconds: i64,
    secret: &str,
) -> AppResult<String> {
    let now = Utc::now();
    let exp = now + Duration::seconds(expiry_seconds);

    let claims = Claims {
        sub: user_id,
        convro_number,
        username,
        token_type: token_type.to_string(),
        iat: now.timestamp(),
        exp: exp.timestamp(),
        jti: Uuid::new_v4().to_string(),
    };

    let token = encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(secret.as_bytes()),
    )
    .map_err(|e| AppError::InternalError(format!("Failed to encode JWT: {}", e)))?;

    Ok(token)
}

/// Decode and validate JWT
pub fn decode_token(token: &str) -> AppResult<Claims> {
    let secret = get_jwt_secret()?;

    let token_data = decode::<Claims>(
        token,
        &DecodingKey::from_secret(secret.as_bytes()),
        &Validation::default(),
    )?;

    // Check expiration (jsonwebtoken already validates, but double-check)
    let now = Utc::now().timestamp();
    if token_data.claims.exp < now {
        return Err(AppError::Unauthorized("Token expired".to_string()));
    }

    Ok(token_data.claims)
}

/// Get JWT secret from environment
fn get_jwt_secret() -> AppResult<String> {
    std::env::var("JWT_SECRET")
        .map_err(|_| AppError::InternalError("JWT_SECRET not configured".to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn setup() {
        std::env::set_var("JWT_SECRET", "test_secret_key_at_least_32_characters_long");
        std::env::set_var("JWT_ACCESS_EXPIRY", "3600");
        std::env::set_var("JWT_REFRESH_EXPIRY", "2592000");
    }

    #[test]
    fn test_encode_and_decode_access_token() {
        setup();

        let user_id = Uuid::new_v4();
        let convro_number = "+99 123 456".to_string();
        let username = "alice".to_string();

        let token = encode_access_token(user_id, convro_number.clone(), username.clone())
            .expect("Failed to encode token");

        let claims = decode_token(&token).expect("Failed to decode token");

        assert_eq!(claims.sub, user_id);
        assert_eq!(claims.convro_number, convro_number);
        assert_eq!(claims.username, username);
        assert_eq!(claims.token_type, "access");
    }

    #[test]
    fn test_encode_and_decode_refresh_token() {
        setup();

        let user_id = Uuid::new_v4();
        let convro_number = "+99 654 321".to_string();
        let username = "bob".to_string();

        let token = encode_refresh_token(user_id, convro_number.clone(), username.clone())
            .expect("Failed to encode token");

        let claims = decode_token(&token).expect("Failed to decode token");

        assert_eq!(claims.sub, user_id);
        assert_eq!(claims.convro_number, convro_number);
        assert_eq!(claims.username, username);
        assert_eq!(claims.token_type, "refresh");
    }

    #[test]
    fn test_decode_invalid_token() {
        setup();

        let result = decode_token("invalid.token.here");
        assert!(result.is_err());
    }

    #[test]
    fn test_token_expiration() {
        setup();
        std::env::set_var("JWT_ACCESS_EXPIRY", "-10"); // Already expired

        let user_id = Uuid::new_v4();
        let convro_number = "+99 123 456".to_string();
        let username = "alice".to_string();

        let token = encode_access_token(user_id, convro_number, username)
            .expect("Failed to encode token");

        let result = decode_token(&token);
        assert!(result.is_err());
    }
}

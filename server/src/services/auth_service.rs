use sqlx::PgPool;
use uuid::Uuid;

use crate::{
    errors::{AppError, AppResult},
    models::{
        auth::AuthTokens,
        user::User,
    },
    repositories::{UserRepository, DeviceRepository},
    utils::{generate_convro_number, hash_password, jwt, verify_password},
};

/// Authentication service
#[derive(Clone)]
pub struct AuthService {
    pool: PgPool,
}

impl AuthService {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Register new user with device identity
    pub async fn register_user(
        &self,
        username: String,
        password: String,
        display_name: Option<String>,
        device_id: String,
        identity_key: String,
        device_name: Option<String>,
        device_platform: Option<String>,
        device_os_version: Option<String>,
        app_version: Option<String>,
    ) -> AppResult<(User, AuthTokens)> {
        let user_repo = UserRepository::new(self.pool.clone());
        let device_repo = DeviceRepository::new(self.pool.clone());

        // Check if username exists
        if user_repo.find_by_username(&username).await?.is_some() {
            return Err(AppError::Conflict("Username already exists".to_string()));
        }

        // Hash password
        let password_hash = hash_password(&password)?;

        // Generate Convro Number (random strategy with collision detection)
        let convro_number = self.generate_unique_convro_number(&user_repo).await?;

        // Create user in database
        let user = user_repo
            .create(username, password_hash, convro_number, display_name)
            .await?;

        // Decode device keys from hex
        let device_id_bytes = hex::decode(&device_id)
            .map_err(|_| AppError::ValidationError("Invalid device_id format".to_string()))?;
        let identity_key_bytes = hex::decode(&identity_key)
            .map_err(|_| AppError::ValidationError("Invalid identity_key format".to_string()))?;

        // Validate key sizes
        if device_id_bytes.len() != 32 {
            return Err(AppError::ValidationError("device_id must be 32 bytes".to_string()));
        }
        if identity_key_bytes.len() != 32 {
            return Err(AppError::ValidationError("identity_key must be 32 bytes".to_string()));
        }

        // Create device identity
        device_repo
            .create(
                user.user_id,
                device_id_bytes,
                identity_key_bytes,
                device_name,
                device_platform,
                device_os_version,
                app_version,
            )
            .await?;

        // Generate JWT tokens
        let tokens = self.generate_tokens(&user)?;

        tracing::info!("User registered: {} ({})", user.username, user.convro_number);

        Ok((user, tokens))
    }

    /// Login user
    pub async fn login(&self, username: String, password: String) -> AppResult<(User, AuthTokens)> {
        let user_repo = UserRepository::new(self.pool.clone());

        // Find user by username
        let user = user_repo
            .find_by_username(&username)
            .await?
            .ok_or_else(|| AppError::Unauthorized("Invalid credentials".to_string()))?;

        // Check account status
        if user.account_status != "active" {
            return Err(AppError::Unauthorized(format!(
                "Account is {}",
                user.account_status
            )));
        }

        // Verify password
        verify_password(&password, &user.password_hash)?;

        // Update last_login
        user_repo.update_last_login(user.user_id).await?;

        // Generate tokens
        let tokens = self.generate_tokens(&user)?;

        tracing::info!("User logged in: {} ({})", user.username, user.convro_number);

        Ok((user, tokens))
    }

    /// Refresh access token using refresh token
    pub async fn refresh_access_token(&self, refresh_token: String) -> AppResult<String> {
        // Decode and validate refresh token
        let claims = jwt::decode_token(&refresh_token)?;

        // Verify token type
        if claims.token_type != "refresh" {
            return Err(AppError::Unauthorized(
                "Invalid token type. Expected refresh token.".to_string(),
            ));
        }

        // Verify user still exists and is active
        let user_repo = UserRepository::new(self.pool.clone());
        let user = user_repo
            .find_by_id(claims.sub)
            .await?
            .ok_or_else(|| AppError::Unauthorized("User not found".to_string()))?;

        if user.account_status != "active" {
            return Err(AppError::Unauthorized("Account is not active".to_string()));
        }

        // Generate new access token
        let username = user.username.clone();
        let access_token = jwt::encode_access_token(
            user.user_id,
            user.convro_number,
            user.username,
        )?;

        tracing::debug!("Access token refreshed for user: {}", username);

        Ok(access_token)
    }

    /// Logout (for stateless JWT, this is a no-op)
    /// In production: add token to Redis blacklist
    pub async fn logout(&self, _user_id: Uuid) -> AppResult<()> {
        // TODO: Implement token blacklist with Redis
        Ok(())
    }

    /// Generate JWT tokens (access + refresh)
    fn generate_tokens(&self, user: &User) -> AppResult<AuthTokens> {
        let access_token = jwt::encode_access_token(
            user.user_id,
            user.convro_number.clone(),
            user.username.clone(),
        )?;

        let refresh_token = jwt::encode_refresh_token(
            user.user_id,
            user.convro_number.clone(),
            user.username.clone(),
        )?;

        Ok(AuthTokens::new(access_token, refresh_token))
    }

    /// Generate unique Convro Number (with collision detection)
    async fn generate_unique_convro_number(&self, user_repo: &UserRepository) -> AppResult<String> {
        const MAX_ATTEMPTS: u32 = 100;

        for attempt in 1..=MAX_ATTEMPTS {
            let candidate = generate_convro_number();

            if user_repo.is_convro_number_available(&candidate).await? {
                tracing::debug!(
                    "Generated unique Convro Number: {} (attempt {})",
                    candidate,
                    attempt
                );
                return Ok(candidate);
            }

            if attempt == MAX_ATTEMPTS {
                tracing::error!("Failed to generate unique Convro Number after {} attempts", MAX_ATTEMPTS);
                return Err(AppError::ServiceUnavailable(
                    "Convro Number pool exhausted. Please try again later.".to_string(),
                ));
            }
        }

        unreachable!()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Integration tests would go here
}

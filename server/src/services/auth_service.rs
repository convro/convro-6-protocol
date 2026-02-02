use sqlx::PgPool;
use uuid::Uuid;

use crate::{
    errors::{AppError, AppResult},
    models::{
        auth::AuthTokens,
        prekey::{OneTimePrekeyDto, SignedPrekeyDto},
        user::{CreateUserRequest, User},
    },
    repositories::{DeviceRepository, UserRepository},
    services::PrekeyService,
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

    /// Register new user with device identity and prekeys
    pub async fn register_user(&self, req: CreateUserRequest) -> AppResult<(User, AuthTokens)> {
        let user_repo = UserRepository::new(self.pool.clone());

        // Check if username exists
        if user_repo.find_by_username(&req.username).await?.is_some() {
            return Err(AppError::Conflict("Username already exists".to_string()));
        }

        // Hash password
        let password_hash = hash_password(&req.password)?;

        // Generate Convro Number (random strategy with collision detection)
        let convro_number = self.generate_unique_convro_number(&user_repo).await?;

        // Create user in database
        let user = user_repo
            .create(
                req.username.clone(),
                password_hash,
                convro_number,
                req.display_name.clone(),
            )
            .await?;

        // Register device identity if provided
        if let (Some(identity_ed25519), Some(identity_x25519)) =
            (&req.identity_pub_ed25519, &req.identity_pub_x25519)
        {
            let device_repo = DeviceRepository::new(self.pool.clone());

            // Decode hex keys
            let ed25519_key = hex::decode(identity_ed25519).map_err(|_| {
                AppError::ValidationError("Invalid identity_pub_ed25519 format".to_string())
            })?;
            let x25519_key = hex::decode(identity_x25519).map_err(|_| {
                AppError::ValidationError("Invalid identity_pub_x25519 format".to_string())
            })?;

            // Validate key sizes
            if ed25519_key.len() != 32 {
                return Err(AppError::ValidationError(
                    "identity_pub_ed25519 must be 32 bytes".to_string(),
                ));
            }
            if x25519_key.len() != 32 {
                return Err(AppError::ValidationError(
                    "identity_pub_x25519 must be 32 bytes".to_string(),
                ));
            }

            // Create device identity
            // Note: device_id column stores Ed25519 key, identity_key stores X25519 key
            let device = device_repo
                .create(
                    user.user_id,
                    ed25519_key,  // device_id column = Ed25519 public key
                    x25519_key,   // identity_key column = X25519 public key
                    Some("Primary Device".to_string()),
                    Some("iOS".to_string()),
                    None,
                    None,
                )
                .await?;

            tracing::info!(
                "Device registered during signup: {} for user {}",
                device.device_identity_id,
                user.user_id
            );

            // Upload prekeys if provided
            if let (Some(spk_id), Some(spk_pub), Some(spk_sig)) =
                (&req.spk_id, &req.spk_pub, &req.spk_sig)
            {
                let prekey_service = PrekeyService::new(self.pool.clone());

                // Build signed prekey DTO
                let signed_prekey_dto = SignedPrekeyDto {
                    spk_id: hex::decode(spk_id)
                        .map_err(|_| AppError::ValidationError("Invalid spk_id format".to_string()))?,
                    public_key: spk_pub.clone(),
                    signature: spk_sig.clone(),
                    expires_at: None,
                };

                // Build one-time prekey DTOs
                let one_time_prekeys_dto: Vec<OneTimePrekeyDto> = req
                    .one_time_prekeys
                    .as_ref()
                    .map(|otps| {
                        otps.iter()
                            .map(|otp| OneTimePrekeyDto {
                                otp_id: otp.otp_id.clone(),
                                public_key: otp.otp_pub.clone(),
                            })
                            .collect()
                    })
                    .unwrap_or_default();

                if !one_time_prekeys_dto.is_empty() {
                    let bundle_id = prekey_service
                        .upload_prekeys(
                            device.device_identity_id,
                            signed_prekey_dto,
                            one_time_prekeys_dto,
                        )
                        .await?;

                    tracing::info!(
                        "Prekeys uploaded during signup: bundle_id={} for device {}",
                        bundle_id,
                        device.device_identity_id
                    );
                } else {
                    tracing::warn!(
                        "No one-time prekeys provided during signup for device {}",
                        device.device_identity_id
                    );
                }
            }
        }

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

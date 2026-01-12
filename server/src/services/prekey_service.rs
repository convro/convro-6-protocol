use sqlx::PgPool;
use uuid::Uuid;

use crate::{
    errors::{AppError, AppResult},
    models::prekey::{OneTimePrekey, OneTimePrekeyDto, PrekeyBundle, SignedPrekey, SignedPrekeyDto},
    repositories::PrekeyRepository,
};

/// Prekey management service
#[derive(Clone)]
pub struct PrekeyService {
    pool: PgPool,
}

impl PrekeyService {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Upload prekeys (signed prekey + one-time prekeys)
    pub async fn upload_prekeys(
        &self,
        device_identity_id: Uuid,
        signed_prekey_dto: SignedPrekeyDto,
        one_time_prekeys_dto: Vec<OneTimePrekeyDto>,
    ) -> AppResult<Uuid> {
        let prekey_repo = PrekeyRepository::new(self.pool.clone());

        // Convert DTOs to domain models (decode hex)
        let signed_prekey = self.parse_signed_prekey(signed_prekey_dto)?;
        let one_time_prekeys = self.parse_one_time_prekeys(one_time_prekeys_dto)?;

        // Validate OTP count
        if one_time_prekeys.is_empty() {
            return Err(AppError::ValidationError(
                "At least 1 one-time prekey required".to_string(),
            ));
        }

        if one_time_prekeys.len() > 100 {
            return Err(AppError::ValidationError(
                "Maximum 100 one-time prekeys allowed per upload".to_string(),
            ));
        }

        // Upload to database
        let bundle_id = prekey_repo
            .upload_prekeys(device_identity_id, signed_prekey, one_time_prekeys)
            .await?;

        tracing::info!(
            "Prekeys uploaded: bundle_id={}, device={}",
            bundle_id,
            device_identity_id
        );

        Ok(bundle_id)
    }

    /// Fetch prekey bundle for handshake
    pub async fn fetch_bundle(&self, convro_number: &str) -> AppResult<PrekeyBundle> {
        let prekey_repo = PrekeyRepository::new(self.pool.clone());

        let bundle = prekey_repo
            .fetch_bundle(convro_number)
            .await?
            .ok_or_else(|| {
                AppError::ServiceUnavailable(format!(
                    "No prekeys available for user {}",
                    convro_number
                ))
            })?;

        // If OTP is present, consume it
        if let Some(otp_id) = bundle.otp_id {
            // Note: We don't consume here - the client should call consume_otp
            // after successfully using it in handshake
            tracing::debug!("OTP reserved for handshake: {}", otp_id);
        }

        Ok(bundle)
    }

    /// Consume OTP after successful handshake
    pub async fn consume_otp(&self, otp_id: Uuid, consumed_by: Uuid) -> AppResult<()> {
        let prekey_repo = PrekeyRepository::new(self.pool.clone());

        let consumed = prekey_repo.consume_otp(otp_id, consumed_by).await?;

        if !consumed {
            return Err(AppError::Conflict(
                "OTP already consumed or not found".to_string(),
            ));
        }

        Ok(())
    }

    /// Get prekey health status
    pub async fn get_prekey_health(
        &self,
        user_id: Uuid,
    ) -> AppResult<Vec<crate::repositories::prekey_repo::PrekeyHealthStatus>> {
        let prekey_repo = PrekeyRepository::new(self.pool.clone());
        prekey_repo.get_prekey_health(user_id).await
    }

    /// Parse signed prekey DTO (hex → bytes)
    fn parse_signed_prekey(&self, dto: SignedPrekeyDto) -> AppResult<SignedPrekey> {
        let public_key = hex::decode(&dto.public_key).map_err(|_| {
            AppError::ValidationError("Invalid signed_prekey format (must be hex)".to_string())
        })?;

        let signature = hex::decode(&dto.signature).map_err(|_| {
            AppError::ValidationError("Invalid signature format (must be hex)".to_string())
        })?;

        if public_key.len() != 32 {
            return Err(AppError::ValidationError(
                "signed_prekey must be 32 bytes (64 hex chars)".to_string(),
            ));
        }

        if signature.len() != 64 {
            return Err(AppError::ValidationError(
                "signature must be 64 bytes (128 hex chars)".to_string(),
            ));
        }

        Ok(SignedPrekey {
            spk_id: dto.spk_id,
            public_key,
            signature,
            expires_at: dto.expires_at,
        })
    }

    /// Parse one-time prekeys (hex → bytes)
    fn parse_one_time_prekeys(&self, dtos: Vec<OneTimePrekeyDto>) -> AppResult<Vec<OneTimePrekey>> {
        dtos.into_iter()
            .map(|dto| {
                let public_key = hex::decode(&dto.public_key).map_err(|_| {
                    AppError::ValidationError(
                        "Invalid one_time_prekey format (must be hex)".to_string(),
                    )
                })?;

                if public_key.len() != 32 {
                    return Err(AppError::ValidationError(
                        "one_time_prekey must be 32 bytes (64 hex chars)".to_string(),
                    ));
                }

                Ok(OneTimePrekey {
                    otp_id: dto.otp_id,
                    public_key,
                })
            })
            .collect()
    }
}

use sqlx::PgPool;
use uuid::Uuid;

use crate::{
    errors::{AppError, AppResult},
    models::prekey::{OneTimePrekey, PrekeyBundle, SignedPrekey},
};

/// Prekey repository for database operations
#[derive(Clone)]
pub struct PrekeyRepository {
    pool: PgPool,
}

impl PrekeyRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Upload prekeys (signed prekey + one-time prekeys)
    pub async fn upload_prekeys(
        &self,
        device_identity_id: Uuid,
        signed_prekey: SignedPrekey,
        one_time_prekeys: Vec<OneTimePrekey>,
    ) -> AppResult<Uuid> {
        let mut tx = self.pool.begin().await?;

        // Insert signed prekey
        let bundle_id: Uuid = sqlx::query_scalar(
            r#"
            INSERT INTO prekey_bundles (
                device_identity_id,
                signed_prekey,
                signed_prekey_signature,
                signed_prekey_id,
                expires_at,
                is_active
            )
            VALUES ($1, $2, $3, $4, $5, TRUE)
            RETURNING bundle_id
            "#,
        )
        .bind(device_identity_id)
        .bind(signed_prekey.public_key)
        .bind(signed_prekey.signature)
        .bind(signed_prekey.spk_id)
        .bind(signed_prekey.expires_at)
        .fetch_one(&mut *tx)
        .await
        .map_err(|e| {
            if let sqlx::Error::Database(db_err) = &e {
                if db_err.is_unique_violation() {
                    return AppError::Conflict(
                        "Signed prekey with this ID already exists".to_string(),
                    );
                }
            }
            AppError::DatabaseError(e)
        })?;

        // Insert one-time prekeys
        for otp in one_time_prekeys {
            sqlx::query(
                r#"
                INSERT INTO one_time_prekeys (
                    device_identity_id,
                    one_time_prekey,
                    otp_key_id,
                    client_otp_id
                )
                VALUES ($1, $2, $3, $4)
                "#,
            )
            .bind(device_identity_id)
            .bind(otp.public_key)
            .bind(0i32)  // otp_key_id is now unused, kept for schema compatibility
            .bind(&otp.otp_id)  // client's hex-encoded OTP ID
            .execute(&mut *tx)
            .await?;
        }

        tx.commit().await?;

        tracing::info!(
            "Prekeys uploaded: bundle_id={}, device={}",
            bundle_id,
            device_identity_id
        );

        Ok(bundle_id)
    }

    /// Fetch prekey bundle for handshake (includes OTP reservation)
    pub async fn fetch_bundle(&self, convro_number: &str) -> AppResult<Option<PrekeyBundle>> {
        // This query matches the one in database schema (with LATERAL join for OTP)
        // Returns client_otp_id so client can match it to Keychain
        let result = sqlx::query_as::<_, PrekeyBundle>(
            r#"
            SELECT
                u.user_id,
                u.convro_number,
                di.device_identity_id,
                di.device_id,
                di.identity_key,
                pb.signed_prekey,
                pb.signed_prekey_signature,
                pb.signed_prekey_id,
                otp.one_time_prekey,
                otp.client_otp_id
            FROM users u
            JOIN device_identities di ON u.user_id = di.user_id
            JOIN prekey_bundles pb ON di.device_identity_id = pb.device_identity_id
            LEFT JOIN LATERAL (
                SELECT client_otp_id, one_time_prekey
                FROM one_time_prekeys
                WHERE device_identity_id = di.device_identity_id
                  AND consumed_at IS NULL
                ORDER BY uploaded_at ASC
                LIMIT 1
            ) otp ON TRUE
            WHERE u.convro_number = $1
              AND di.is_active = TRUE
              AND pb.is_active = TRUE
            LIMIT 1
            "#,
        )
        .bind(convro_number)
        .fetch_optional(&self.pool)
        .await?;

        if result.is_none() {
            tracing::warn!("No prekey bundle found for convro_number: {}", convro_number);
        }

        Ok(result)
    }

    /// Consume OTP (atomic operation with SELECT FOR UPDATE)
    /// This uses the database function from schema.sql
    pub async fn consume_otp(&self, otp_id: Uuid, consumed_by: Uuid) -> AppResult<bool> {
        let result: bool = sqlx::query_scalar(
            r#"
            SELECT consume_otp($1, $2) as "consumed"
            "#,
        )
        .bind(otp_id)
        .bind(consumed_by)
        .fetch_one(&self.pool)
        .await?;

        if result {
            tracing::info!("OTP consumed: {} by user {}", otp_id, consumed_by);
        } else {
            tracing::warn!("Failed to consume OTP: {} (already consumed or not found)", otp_id);
        }

        Ok(result)
    }

    /// Get available OTP count for device
    pub async fn get_available_otp_count(&self, device_identity_id: Uuid) -> AppResult<i64> {
        let count: i64 = sqlx::query_scalar(
            r#"
            SELECT get_available_otp_count($1) as "count"
            "#,
        )
        .bind(device_identity_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(count)
    }

    /// Get prekey health status for all user devices
    pub async fn get_prekey_health(&self, user_id: Uuid) -> AppResult<Vec<PrekeyHealthStatus>> {
        let results = sqlx::query_as::<_, PrekeyHealthStatus>(
            r#"
            SELECT
                d.device_identity_id,
                d.device_name,
                pb.bundle_id IS NOT NULL as "has_signed_prekey",
                pb.expires_at as spk_expires_at,
                COUNT(otp.otp_id) FILTER (WHERE otp.consumed_at IS NULL) as "available_otps",
                COUNT(otp.otp_id) FILTER (WHERE otp.consumed_at IS NOT NULL) as "consumed_otps"
            FROM device_identities d
            LEFT JOIN prekey_bundles pb ON d.device_identity_id = pb.device_identity_id AND pb.is_active = TRUE
            LEFT JOIN one_time_prekeys otp ON d.device_identity_id = otp.device_identity_id
            WHERE d.user_id = $1 AND d.is_active = TRUE
            GROUP BY d.device_identity_id, d.device_name, pb.bundle_id, pb.expires_at
            "#,
        )
        .bind(user_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(results)
    }
}

/// Prekey health status (for monitoring)
#[derive(Debug, sqlx::FromRow)]
pub struct PrekeyHealthStatus {
    pub device_identity_id: Uuid,
    pub device_name: Option<String>,
    pub has_signed_prekey: bool,
    pub spk_expires_at: Option<chrono::DateTime<chrono::Utc>>,
    pub available_otps: i64,
    pub consumed_otps: i64,
}

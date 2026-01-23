use sqlx::PgPool;
use uuid::Uuid;

use crate::{
    errors::{AppError, AppResult},
    models::device::Device,
};

/// Device repository for database operations
#[derive(Clone)]
pub struct DeviceRepository {
    pool: PgPool,
}

impl DeviceRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Register new device
    pub async fn create(
        &self,
        user_id: Uuid,
        device_id: Vec<u8>,
        identity_key: Vec<u8>,
        device_name: Option<String>,
        device_platform: Option<String>,
        device_os_version: Option<String>,
        app_version: Option<String>,
    ) -> AppResult<Device> {
        let device = sqlx::query_as::<_, Device>(
            r#"
            INSERT INTO device_identities (
                user_id,
                device_id,
                identity_key,
                device_name,
                device_platform,
                device_os_version,
                app_version,
                is_active
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, TRUE)
            RETURNING
                device_identity_id,
                user_id,
                device_id,
                identity_key,
                device_name,
                device_platform,
                device_os_version,
                app_version,
                registered_at,
                last_seen,
                is_active
            "#,
        )
        .bind(user_id)
        .bind(device_id)
        .bind(identity_key)
        .bind(device_name)
        .bind(device_platform)
        .bind(device_os_version)
        .bind(app_version)
        .fetch_one(&self.pool)
        .await
        .map_err(|e| {
            if let sqlx::Error::Database(db_err) = &e {
                if db_err.is_unique_violation() {
                    return AppError::Conflict("Device already registered".to_string());
                }
            }
            AppError::DatabaseError(e)
        })?;

        tracing::info!(
            "Device registered: {} for user {}",
            device.device_identity_id,
            device.user_id
        );

        Ok(device)
    }

    /// List devices for user
    pub async fn list_by_user(&self, user_id: Uuid) -> AppResult<Vec<Device>> {
        let devices = sqlx::query_as::<_, Device>(
            r#"
            SELECT
                device_identity_id,
                user_id,
                device_id,
                identity_key,
                device_name,
                device_platform,
                device_os_version,
                app_version,
                registered_at,
                last_seen,
                is_active
            FROM device_identities
            WHERE user_id = $1
            ORDER BY registered_at DESC
            "#,
        )
        .bind(user_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(devices)
    }

    /// Get device by ID
    pub async fn find_by_id(&self, device_identity_id: Uuid) -> AppResult<Option<Device>> {
        let device = sqlx::query_as::<_, Device>(
            r#"
            SELECT
                device_identity_id,
                user_id,
                device_id,
                identity_key,
                device_name,
                device_platform,
                device_os_version,
                app_version,
                registered_at,
                last_seen,
                is_active
            FROM device_identities
            WHERE device_identity_id = $1
            "#,
        )
        .bind(device_identity_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(device)
    }

    /// Update last_seen timestamp
    pub async fn update_last_seen(&self, device_identity_id: Uuid) -> AppResult<()> {
        sqlx::query(
            r#"
            UPDATE device_identities
            SET last_seen = NOW()
            WHERE device_identity_id = $1
            "#,
        )
        .bind(device_identity_id)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// Deactivate device
    pub async fn deactivate(&self, device_identity_id: Uuid, user_id: Uuid) -> AppResult<()> {
        let result = sqlx::query(
            r#"
            UPDATE device_identities
            SET is_active = FALSE, updated_at = NOW()
            WHERE device_identity_id = $1 AND user_id = $2
            "#,
        )
        .bind(device_identity_id)
        .bind(user_id)
        .execute(&self.pool)
        .await?;

        if result.rows_affected() == 0 {
            return Err(AppError::NotFound("Device not found".to_string()));
        }

        tracing::info!("Device deactivated: {}", device_identity_id);

        Ok(())
    }

    /// Check if user has any active devices
    pub async fn has_active_devices(&self, user_id: Uuid) -> AppResult<bool> {
        let count: i64 = sqlx::query_scalar(
            r#"
            SELECT COUNT(*) as "count"
            FROM device_identities
            WHERE user_id = $1 AND is_active = TRUE
            "#,
        )
        .bind(user_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(count > 0)
    }
}

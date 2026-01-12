use sqlx::PgPool;
use uuid::Uuid;

use crate::{
    errors::{AppError, AppResult},
    models::device::Device,
    repositories::DeviceRepository,
};

/// Device management service
#[derive(Clone)]
pub struct DeviceService {
    pool: PgPool,
}

impl DeviceService {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Register new device
    pub async fn register_device(
        &self,
        user_id: Uuid,
        device_id: String,  // Hex-encoded
        identity_key: String,  // Hex-encoded
        device_name: Option<String>,
        device_platform: Option<String>,
        device_os_version: Option<String>,
        app_version: Option<String>,
    ) -> AppResult<Device> {
        let device_repo = DeviceRepository::new(self.pool.clone());

        // Decode hex strings to bytes
        let device_id_bytes = hex::decode(&device_id)
            .map_err(|_| AppError::ValidationError("Invalid device_id format (must be hex)".to_string()))?;

        let identity_key_bytes = hex::decode(&identity_key)
            .map_err(|_| AppError::ValidationError("Invalid identity_key format (must be hex)".to_string()))?;

        // Validate sizes
        if device_id_bytes.len() != 32 {
            return Err(AppError::ValidationError(
                "device_id must be 32 bytes (64 hex chars)".to_string(),
            ));
        }

        if identity_key_bytes.len() != 32 {
            return Err(AppError::ValidationError(
                "identity_key must be 32 bytes (64 hex chars)".to_string(),
            ));
        }

        // Create device
        let device = device_repo
            .create(
                user_id,
                device_id_bytes,
                identity_key_bytes,
                device_name,
                device_platform,
                device_os_version,
                app_version,
            )
            .await?;

        tracing::info!(
            "Device registered: {} for user {}",
            device.device_identity_id,
            user_id
        );

        Ok(device)
    }

    /// List user's devices
    pub async fn list_user_devices(&self, user_id: Uuid) -> AppResult<Vec<Device>> {
        let device_repo = DeviceRepository::new(self.pool.clone());
        device_repo.list_by_user(user_id).await
    }

    /// Deactivate device
    pub async fn deactivate_device(
        &self,
        device_identity_id: Uuid,
        user_id: Uuid,
    ) -> AppResult<()> {
        let device_repo = DeviceRepository::new(self.pool.clone());

        // Check if this is the last active device
        let active_devices = device_repo.list_by_user(user_id).await?;
        let active_count = active_devices.iter().filter(|d| d.is_active).count();

        if active_count <= 1 {
            return Err(AppError::ValidationError(
                "Cannot deactivate last active device".to_string(),
            ));
        }

        device_repo.deactivate(device_identity_id, user_id).await?;

        tracing::info!(
            "Device deactivated: {} for user {}",
            device_identity_id,
            user_id
        );

        Ok(())
    }

    /// Update device last_seen timestamp
    pub async fn update_last_seen(&self, device_identity_id: Uuid) -> AppResult<()> {
        let device_repo = DeviceRepository::new(self.pool.clone());
        device_repo.update_last_seen(device_identity_id).await
    }
}

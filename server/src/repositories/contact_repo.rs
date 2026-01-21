use sqlx::PgPool;
use uuid::Uuid;

use crate::{
    errors::{AppError, AppResult},
    models::contact::Contact,
};

/// Contact repository for database operations
#[derive(Clone)]
pub struct ContactRepository {
    pool: PgPool,
}

impl ContactRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Add new contact
    pub async fn create(
        &self,
        user_id: Uuid,
        contact_convro_number: String,
        contact_user_id: Option<Uuid>,
        display_name: Option<String>,
    ) -> AppResult<Contact> {
        let contact = sqlx::query_as::<_, Contact>(
            r#"
            INSERT INTO contacts (user_id, contact_convro_number, contact_user_id, display_name)
            VALUES ($1, $2, $3, $4)
            RETURNING
                contact_id,
                user_id,
                contact_convro_number,
                contact_user_id,
                display_name,
                is_verified,
                verified_at,
                added_at,
                updated_at
            "#,
        )
        .bind(user_id)
        .bind(&contact_convro_number)
        .bind(contact_user_id)
        .bind(&display_name)
        .fetch_one(&self.pool)
        .await
        .map_err(|e| {
            if let sqlx::Error::Database(db_err) = &e {
                if db_err.is_unique_violation() {
                    return AppError::Conflict("Contact already exists".to_string());
                }
            }
            AppError::DatabaseError(e)
        })?;

        tracing::info!(
            "Contact created: {} for user {}",
            contact_convro_number,
            user_id
        );

        Ok(contact)
    }

    /// Get all contacts for a user
    pub async fn list_by_user(&self, user_id: Uuid) -> AppResult<Vec<Contact>> {
        let contacts = sqlx::query_as::<_, Contact>(
            r#"
            SELECT
                contact_id,
                user_id,
                contact_convro_number,
                contact_user_id,
                display_name,
                is_verified,
                verified_at,
                added_at,
                updated_at
            FROM contacts
            WHERE user_id = $1
            ORDER BY added_at DESC
            "#,
        )
        .bind(user_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(contacts)
    }

    /// Delete contact
    pub async fn delete(&self, contact_id: Uuid, user_id: Uuid) -> AppResult<()> {
        let result = sqlx::query(
            r#"
            DELETE FROM contacts
            WHERE contact_id = $1 AND user_id = $2
            "#,
        )
        .bind(contact_id)
        .bind(user_id)
        .execute(&self.pool)
        .await?;

        if result.rows_affected() == 0 {
            return Err(AppError::NotFound("Contact not found".to_string()));
        }

        tracing::info!("Contact deleted: {} by user {}", contact_id, user_id);

        Ok(())
    }

    /// Verify contact (set is_verified flag)
    pub async fn update_verification(
        &self,
        contact_id: Uuid,
        user_id: Uuid,
        verified: bool,
    ) -> AppResult<Contact> {
        let contact = sqlx::query_as::<_, Contact>(
            r#"
            UPDATE contacts
            SET is_verified = $3,
                verified_at = CASE WHEN $3 = TRUE THEN NOW() ELSE NULL END,
                updated_at = NOW()
            WHERE contact_id = $1 AND user_id = $2
            RETURNING
                contact_id,
                user_id,
                contact_convro_number,
                contact_user_id,
                display_name,
                is_verified,
                verified_at,
                added_at,
                updated_at
            "#,
        )
        .bind(contact_id)
        .bind(user_id)
        .bind(verified)
        .fetch_optional(&self.pool)
        .await?
        .ok_or_else(|| AppError::NotFound("Contact not found".to_string()))?;

        tracing::info!(
            "Contact verification updated: {} verified={}",
            contact_id,
            verified
        );

        Ok(contact)
    }
}

use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::{
    errors::{AppError, AppResult},
    models::user::User,
};

/// User repository for database operations
#[derive(Clone)]
pub struct UserRepository {
    pool: PgPool,
}

impl UserRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Create new user
    pub async fn create(
        &self,
        username: String,
        password_hash: String,
        convro_number: String,
        display_name: Option<String>,
    ) -> AppResult<User> {
        let user = sqlx::query_as::<_, User>(
            r#"
            INSERT INTO users (username, password_hash, convro_number, display_name, account_status)
            VALUES ($1, $2, $3, $4, 'active')
            RETURNING
                user_id,
                username,
                convro_number,
                password_hash,
                display_name,
                account_status,
                created_at,
                last_login,
                updated_at
            "#,
        )
        .bind(&username)
        .bind(&password_hash)
        .bind(&convro_number)
        .bind(&display_name)
        .fetch_one(&self.pool)
        .await
        .map_err(|e| {
            if let sqlx::Error::Database(db_err) = &e {
                if db_err.is_unique_violation() {
                    return AppError::Conflict("Username already exists".to_string());
                }
            }
            AppError::DatabaseError(e)
        })?;

        tracing::info!("User created: {} ({})", user.username, user.convro_number);

        Ok(user)
    }

    /// Find user by username
    pub async fn find_by_username(&self, username: &str) -> AppResult<Option<User>> {
        let user = sqlx::query_as::<_, User>(
            r#"
            SELECT
                user_id,
                username,
                convro_number,
                password_hash,
                display_name,
                account_status,
                created_at,
                last_login,
                updated_at
            FROM users
            WHERE username = $1
            "#,
        )
        .bind(username)
        .fetch_optional(&self.pool)
        .await?;

        Ok(user)
    }

    /// Find user by Convro Number
    pub async fn find_by_convro_number(&self, convro_number: &str) -> AppResult<Option<User>> {
        let user = sqlx::query_as::<_, User>(
            r#"
            SELECT
                user_id,
                username,
                convro_number,
                password_hash,
                display_name,
                account_status,
                created_at,
                last_login,
                updated_at
            FROM users
            WHERE convro_number = $1
            "#,
        )
        .bind(convro_number)
        .fetch_optional(&self.pool)
        .await?;

        Ok(user)
    }

    /// Find user by ID
    pub async fn find_by_id(&self, user_id: Uuid) -> AppResult<Option<User>> {
        let user = sqlx::query_as::<_, User>(
            r#"
            SELECT
                user_id,
                username,
                convro_number,
                password_hash,
                display_name,
                account_status,
                created_at,
                last_login,
                updated_at
            FROM users
            WHERE user_id = $1
            "#,
        )
        .bind(user_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(user)
    }

    /// Check if Convro Number is available
    pub async fn is_convro_number_available(&self, convro_number: &str) -> AppResult<bool> {
        let row = sqlx::query("SELECT COUNT(*) FROM users WHERE convro_number = $1")
            .bind(convro_number)
            .fetch_one(&self.pool)
            .await?;

        let count: i64 = row.try_get(0)?;
        Ok(count == 0)
    }

    /// Update last_login timestamp
    pub async fn update_last_login(&self, user_id: Uuid) -> AppResult<()> {
        sqlx::query("UPDATE users SET last_login = NOW() WHERE user_id = $1")
            .bind(user_id)
            .execute(&self.pool)
            .await?;

        Ok(())
    }

    /// Update display name
    pub async fn update_display_name(
        &self,
        user_id: Uuid,
        display_name: Option<String>,
    ) -> AppResult<User> {
        let user = sqlx::query_as::<_, User>(
            r#"
            UPDATE users
            SET display_name = $2, updated_at = NOW()
            WHERE user_id = $1
            RETURNING
                user_id,
                username,
                convro_number,
                password_hash,
                display_name,
                account_status,
                created_at,
                last_login,
                updated_at
            "#,
        )
        .bind(user_id)
        .bind(&display_name)
        .fetch_one(&self.pool)
        .await?;

        Ok(user)
    }

    /// Search users by Convro Number (for adding contacts)
    pub async fn search_by_convro_number(&self, convro_number: &str) -> AppResult<Option<User>> {
        self.find_by_convro_number(convro_number).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Integration tests would go here
    // Requires test database setup
}

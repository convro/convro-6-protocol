use sqlx::PgPool;
use uuid::Uuid;

use crate::{
    errors::{AppError, AppResult},
    models::user::{User, UserResponse},
    repositories::user_repo::UserRepository,
};

/// User service for user profile operations
#[derive(Clone)]
pub struct UserService {
    user_repo: UserRepository,
}

impl UserService {
    pub fn new(pool: PgPool) -> Self {
        Self {
            user_repo: UserRepository::new(pool),
        }
    }

    /// Get user profile by ID
    pub async fn get_user_profile(&self, user_id: Uuid) -> AppResult<UserResponse> {
        let user = self
            .user_repo
            .find_by_id(user_id)
            .await?
            .ok_or_else(|| AppError::NotFound("User not found".to_string()))?;

        Ok(UserResponse::from(user))
    }

    /// Update user display name
    pub async fn update_display_name(
        &self,
        user_id: Uuid,
        display_name: Option<String>,
    ) -> AppResult<UserResponse> {
        let user = self
            .user_repo
            .update_display_name(user_id, display_name)
            .await?;

        Ok(UserResponse::from(user))
    }
}

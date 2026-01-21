use sqlx::{postgres::PgPoolOptions, PgPool};
use std::time::Duration;

/// Create PostgreSQL connection pool
pub async fn create_pool(database_url: &str) -> anyhow::Result<PgPool> {
    let pool = PgPoolOptions::new()
        .max_connections(50)
        .min_connections(5)
        .acquire_timeout(Duration::from_secs(10))
        .idle_timeout(Duration::from_secs(600))
        .max_lifetime(Duration::from_secs(1800))
        .connect(database_url)
        .await?;

    tracing::info!("✅ Database connection pool created (max: 50 connections)");

    // Test connection
    sqlx::query("SELECT 1")
        .execute(&pool)
        .await
        .map_err(|e| {
            tracing::error!("Failed to connect to database: {}", e);
            e
        })?;

    tracing::info!("✅ Database connection verified");

    Ok(pool)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore] // Run with: cargo test -- --ignored
    async fn test_create_pool() {
        dotenv::dotenv().ok();
        let database_url = std::env::var("DATABASE_URL")
            .expect("DATABASE_URL must be set for tests");

        let pool = create_pool(&database_url).await;
        assert!(pool.is_ok());
    }
}

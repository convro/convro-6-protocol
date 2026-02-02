use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub struct Settings {
    pub host: String,
    pub port: u16,
    pub database_url: String,
    pub jwt_secret: String,
    pub jwt_access_expiry: u64,
    pub jwt_refresh_expiry: u64,
    #[serde(skip)]
    pub cors_allowed_origins: Vec<String>,
    pub rate_limit_per_minute: u32,
    pub ws_heartbeat_interval: u64,
    pub ws_client_timeout: u64,
}

impl Settings {
    pub fn load() -> anyhow::Result<Self> {
        // Load .env file
        dotenv::dotenv().ok();

        // Build config from environment variables
        let settings = config::Config::builder()
            .add_source(config::Environment::default().separator("__"))
            .build()?;

        let mut config: Settings = settings.try_deserialize()?;

        // Parse CORS origins (comma-separated string)
        if let Ok(origins) = std::env::var("CORS_ALLOWED_ORIGINS") {
            config.cors_allowed_origins = origins
                .split(',')
                .map(|s| s.trim().to_string())
                .collect();
        }

        // Validate JWT secret length
        if config.jwt_secret.len() < 32 {
            anyhow::bail!("JWT_SECRET must be at least 32 characters long");
        }

        Ok(config)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_settings_validation() {
        // This test requires .env file or environment variables
        // Run with: cargo test -- --ignored
    }
}

use axum::{routing::get, Router};
use std::net::SocketAddr;
use tower_http::{compression::CompressionLayer, trace::TraceLayer};

use convro_server::{
    api, config::Settings, db, errors::AppResult, services::AuthService,
};

#[tokio::main]
async fn main() -> AppResult<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            std::env::var("RUST_LOG")
                .unwrap_or_else(|_| "info,convro_server=debug,sqlx=warn".to_string()),
        )
        .with_target(false)
        .with_thread_ids(true)
        .with_file(true)
        .with_line_number(true)
        .init();

    tracing::info!("🚀 Starting Convro Server...");

    // Load configuration
    let config = Settings::load().map_err(|e| {
        tracing::error!("Failed to load configuration: {}", e);
        e
    })?;

    tracing::info!("✅ Configuration loaded");
    tracing::debug!("  - Host: {}", config.host);
    tracing::debug!("  - Port: {}", config.port);
    tracing::debug!("  - Database: {}", mask_db_url(&config.database_url));

    // Create database connection pool
    let db_pool = db::create_pool(&config.database_url).await.map_err(|e| {
        tracing::error!("Failed to create database pool: {}", e);
        e
    })?;

    // Run database migrations
    tracing::info!("🔄 Running database migrations...");
    sqlx::migrate!("../../database")
        .run(&db_pool)
        .await
        .map_err(|e| {
            tracing::error!("Database migration failed: {}", e);
            e
        })?;
    tracing::info!("✅ Database migrations complete");

    // Create services
    let auth_service = AuthService::new(db_pool.clone());

    // Build application state
    let app_state = api::auth::AppState { auth_service };

    // Build router
    let app = Router::new()
        .route("/health", get(health_check))
        .nest("/v1", api_routes(app_state))
        .layer(CompressionLayer::new())
        .layer(TraceLayer::new_for_http());

    // Start server
    let addr: SocketAddr = format!("{}:{}", config.host, config.port)
        .parse()
        .map_err(|e| {
            tracing::error!("Invalid address: {}", e);
            anyhow::anyhow!("Invalid address")
        })?;

    tracing::info!("🌐 Server listening on http://{}", addr);
    tracing::info!("✅ Convro Server is ready!");

    let listener = tokio::net::TcpListener::bind(addr).await.map_err(|e| {
        tracing::error!("Failed to bind to {}: {}", addr, e);
        e
    })?;

    axum::serve(listener, app).await.map_err(|e| {
        tracing::error!("Server error: {}", e);
        e
    })?;

    Ok(())
}

/// Build API routes
fn api_routes(state: api::auth::AppState) -> Router {
    Router::new().merge(api::auth::router(state))
    // Additional routes will be added here:
    // .merge(api::users::router(state))
    // .merge(api::devices::router(state))
    // .merge(api::prekeys::router(state))
    // .merge(api::messages::router(state))
    // .merge(api::contacts::router(state))
    // .merge(api::presence::router(state))
}

/// Health check endpoint
async fn health_check() -> &'static str {
    "OK"
}

/// Mask sensitive parts of database URL for logging
fn mask_db_url(url: &str) -> String {
    if let Some(at_pos) = url.rfind('@') {
        let (_, after_at) = url.split_at(at_pos);
        format!("postgres://***:***{}", after_at)
    } else {
        url.to_string()
    }
}

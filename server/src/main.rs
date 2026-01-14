use axum::{middleware, routing::get, Router};
use std::net::SocketAddr;
use tower_http::{compression::CompressionLayer, trace::TraceLayer};

use convro_server::{
    api, config::Settings, db,
    middleware as app_middleware,
    services::{AuthService, ConversationService, DeviceService, MessageService, PrekeyService, SealedMessageService},
};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
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
    sqlx::migrate!("../database/migrations")
        .run(&db_pool)
        .await
        .map_err(|e| {
            tracing::error!("Database migration failed: {}", e);
            e
        })?;
    tracing::info!("✅ Database migrations complete");

    // Create services
    let auth_service = AuthService::new(db_pool.clone());
    let device_service = DeviceService::new(db_pool.clone());
    let prekey_service = PrekeyService::new(db_pool.clone());
    let message_service = MessageService::new(db_pool.clone());
    let conversation_service = ConversationService::new(db_pool.clone());
    let sealed_message_service = SealedMessageService::new(db_pool.clone());

    // Build router
    let app = Router::new()
        .route("/health", get(health_check))
        .nest(
            "/v1",
            api_routes(
                auth_service,
                device_service,
                prekey_service,
                message_service,
                conversation_service,
                sealed_message_service,
            ),
        )
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
    tracing::info!("📡 Available endpoints:");
    tracing::info!("  Authentication:");
    tracing::info!("    POST   /v1/auth/register");
    tracing::info!("    POST   /v1/auth/login");
    tracing::info!("    POST   /v1/auth/refresh");
    tracing::info!("    POST   /v1/auth/logout");
    tracing::info!("");
    tracing::info!("  Devices:");
    tracing::info!("    POST   /v1/devices");
    tracing::info!("    GET    /v1/devices");
    tracing::info!("    DELETE /v1/devices/:id");
    tracing::info!("");
    tracing::info!("  Prekeys:");
    tracing::info!("    POST   /v1/prekeys");
    tracing::info!("    GET    /v1/prekeys/:convro_number");
    tracing::info!("    GET    /v1/prekeys/health");
    tracing::info!("");
    tracing::info!("  🔒 Messages (SEALED SENDER - STANDARD):");
    tracing::info!("    POST   /v1/messages             ← Privacy-first (sender hidden, 64KB)");
    tracing::info!("    GET    /v1/messages/inbox");
    tracing::info!("    POST   /v1/messages/:id/delivered");
    tracing::info!("");
    tracing::info!("  ⚠️  Messages (LEGACY - backward compatibility only):");
    tracing::info!("    POST   /v1/messages/legacy      ← Server sees sender (not recommended)");
    tracing::info!("    GET    /v1/messages/legacy/inbox");
    tracing::info!("    POST   /v1/messages/legacy/:id/delivered");
    tracing::info!("    GET    /v1/messages/legacy/history");
    tracing::info!("");
    tracing::info!("  Conversations:");
    tracing::info!("    GET    /v1/conversations");
    tracing::info!("");
    tracing::info!("✅ Convro Server is ready! Privacy-first by default 🔒");

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
fn api_routes(
    auth_service: AuthService,
    device_service: DeviceService,
    prekey_service: PrekeyService,
    message_service: MessageService,
    conversation_service: ConversationService,
    sealed_message_service: SealedMessageService,
) -> Router {
    // Public routes (no auth)
    let public_routes = api::auth_router(api::auth::AppState { auth_service });

    // Protected routes (require JWT)
    let protected_routes = Router::new()
        .merge(api::devices_router(api::devices::AppState {
            device_service,
        }))
        .merge(api::prekeys_router(api::prekeys::AppState {
            prekey_service,
        }))
        .merge(api::messages_router(api::messages::AppState {
            message_service,
        }))
        .merge(api::conversations_router(api::conversations::AppState {
            conversation_service,
        }))
        .merge(api::sealed_messages_router(api::sealed_messages::AppState {
            sealed_message_service,
        }))
        .layer(middleware::from_fn(app_middleware::require_auth));

    // Combine public + protected
    Router::new().merge(public_routes).merge(protected_routes)
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

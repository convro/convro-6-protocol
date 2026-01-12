# Convro Server Architecture - Rust + Axum

**Version:** 1.0.0
**Stack:** Rust 1.75+ | Axum 0.7 | PostgreSQL 15+ | Tokio | WebSocket
**Architecture:** Layered (Router → Handler → Service → Repository → Database)

---

## Table of Contents

1. [Project Structure](#1-project-structure)
2. [Technology Stack](#2-technology-stack)
3. [Layered Architecture](#3-layered-architecture)
4. [Core Components](#4-core-components)
5. [Middleware Pipeline](#5-middleware-pipeline)
6. [WebSocket Hub](#6-websocket-hub)
7. [Database Layer](#7-database-layer)
8. [Configuration](#8-configuration)
9. [Error Handling](#9-error-handling)
10. [Testing Strategy](#10-testing-strategy)

---

## 1. Project Structure

```
server/
├── Cargo.toml
├── .env.example
├── .env
├── migrations/                  # Database migrations (sqlx)
│   └── 001_initial_schema.sql
│
├── src/
│   ├── main.rs                  # Application entry point
│   ├── lib.rs                   # Library exports
│   │
│   ├── api/                     # HTTP API layer (Axum handlers)
│   │   ├── mod.rs
│   │   ├── auth.rs              # POST /auth/register, /login, /refresh
│   │   ├── users.rs             # GET /users/me, /search
│   │   ├── devices.rs           # POST /devices, GET /devices, DELETE /devices/{id}
│   │   ├── prekeys.rs           # POST /prekeys, GET /prekeys/{convro_number}
│   │   ├── messages.rs          # POST /messages, GET /inbox, POST /{id}/delivered
│   │   ├── contacts.rs          # CRUD /contacts
│   │   ├── presence.rs          # POST /presence, GET /presence
│   │   └── health.rs            # GET /health, /metrics
│   │
│   ├── services/                # Business logic layer
│   │   ├── mod.rs
│   │   ├── auth_service.rs      # JWT generation, password hashing (Argon2id)
│   │   ├── user_service.rs      # User registration, Convro Number generation
│   │   ├── device_service.rs    # Device lifecycle, prekey rotation
│   │   ├── handshake_service.rs # Handshake orchestration
│   │   ├── message_service.rs   # Message routing, delivery
│   │   ├── contact_service.rs   # Contact management
│   │   └── presence_service.rs  # Presence tracking
│   │
│   ├── repositories/            # Data access layer (PostgreSQL)
│   │   ├── mod.rs
│   │   ├── user_repo.rs         # User CRUD, search by convro_number
│   │   ├── device_repo.rs       # Device identity CRUD
│   │   ├── prekey_repo.rs       # Prekey upload, fetch, consume OTP
│   │   ├── message_repo.rs      # Message storage, inbox queries
│   │   ├── contact_repo.rs      # Contact CRUD
│   │   └── presence_repo.rs     # Presence updates
│   │
│   ├── websocket/               # WebSocket server
│   │   ├── mod.rs
│   │   ├── hub.rs               # WebSocket connection hub (actor)
│   │   ├── connection.rs        # Individual WS connection handler
│   │   ├── protocol.rs          # WS message protocol (ping/pong, message, typing)
│   │   └── handlers.rs          # WS message handlers
│   │
│   ├── middleware/              # Axum middleware
│   │   ├── mod.rs
│   │   ├── auth.rs              # JWT verification middleware
│   │   ├── rate_limit.rs        # Rate limiting (Tower + Governor)
│   │   ├── request_id.rs        # X-Request-ID generation
│   │   ├── logging.rs           # Request/response logging (tracing)
│   │   └── cors.rs              # CORS configuration
│   │
│   ├── models/                  # Data models (DTOs, domain entities)
│   │   ├── mod.rs
│   │   ├── user.rs              # User, CreateUserRequest, LoginRequest
│   │   ├── device.rs            # DeviceIdentity, RegisterDeviceRequest
│   │   ├── prekey.rs            # PrekeyBundle, UploadPrekeysRequest
│   │   ├── message.rs           # Message, SendMessageRequest
│   │   ├── contact.rs           # Contact, AddContactRequest
│   │   ├── presence.rs          # Presence, UpdatePresenceRequest
│   │   └── auth.rs              # AuthTokens, Claims
│   │
│   ├── db/                      # Database setup
│   │   ├── mod.rs
│   │   ├── pool.rs              # Connection pool (sqlx)
│   │   └── migrations.rs        # Migration runner
│   │
│   ├── config/                  # Configuration
│   │   ├── mod.rs
│   │   └── settings.rs          # AppConfig (from .env)
│   │
│   ├── errors/                  # Error handling
│   │   ├── mod.rs
│   │   ├── app_error.rs         # AppError enum
│   │   └── result.rs            # AppResult<T> type alias
│   │
│   └── utils/                   # Utilities
│       ├── mod.rs
│       ├── convro_number.rs     # Convro Number generation
│       ├── jwt.rs               # JWT encode/decode
│       ├── password.rs          # Argon2id hashing
│       └── crypto.rs            # Hex encoding, fingerprints
│
├── tests/
│   ├── integration/
│   │   ├── auth_tests.rs
│   │   ├── handshake_tests.rs
│   │   └── message_tests.rs
│   └── common/
│       └── test_helpers.rs
│
└── docker/
    ├── Dockerfile
    ├── docker-compose.yml
    └── postgres/
        └── init.sql
```

---

## 2. Technology Stack

### 2.1 Core Dependencies

```toml
[dependencies]
# Web framework
axum = "0.7"
axum-extra = { version = "0.9", features = ["typed-header"] }
tower = "0.4"
tower-http = { version = "0.5", features = ["trace", "cors", "compression"] }

# Async runtime
tokio = { version = "1", features = ["full"] }
tokio-tungstenite = "0.21"  # WebSocket

# Database
sqlx = { version = "0.7", features = ["runtime-tokio", "postgres", "uuid", "chrono", "json"] }

# Serialization
serde = { version = "1", features = ["derive"] }
serde_json = "1"

# Authentication
jsonwebtoken = "9"
argon2 = "0.5"  # Password hashing

# UUID
uuid = { version = "1", features = ["v4", "serde"] }

# Date/Time
chrono = { version = "0.4", features = ["serde"] }

# Logging
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }

# Rate limiting
governor = "0.6"

# Configuration
config = "0.13"
dotenv = "0.15"

# Error handling
thiserror = "1"
anyhow = "1"

# Validation
validator = { version = "0.16", features = ["derive"] }

# Random
rand = "0.8"

# HTTP client (for testing)
reqwest = { version = "0.11", features = ["json"] }
```

---

### 2.2 Development Dependencies

```toml
[dev-dependencies]
# Testing
tokio-test = "0.4"
wiremock = "0.5"

# Test database
testcontainers = "0.15"
```

---

## 3. Layered Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      HTTP Client / WebSocket                 │
└───────────────────────────┬─────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│                    Middleware Layer                          │
│  - JWT Auth                                                  │
│  - Rate Limiting                                             │
│  - Request ID                                                │
│  - Logging                                                   │
│  - CORS                                                      │
└───────────────────────────┬─────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│                     API Layer (Handlers)                     │
│  - Request validation                                        │
│  - DTO → Domain conversion                                   │
│  - Response formatting                                       │
└───────────────────────────┬─────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│                   Service Layer (Business Logic)             │
│  - Convro Number generation                                  │
│  - JWT creation                                              │
│  - Handshake orchestration                                   │
│  - Message routing                                           │
└───────────────────────────┬─────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│                  Repository Layer (Data Access)              │
│  - SQL queries                                               │
│  - Transaction management                                    │
│  - OTP consumption (SELECT FOR UPDATE)                       │
└───────────────────────────┬─────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│                      PostgreSQL Database                     │
│  - 11 tables (users, devices, prekeys, messages, etc.)      │
│  - SERIALIZABLE isolation                                    │
│  - Immutability triggers                                     │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. Core Components

### 4.1 Main Application (`main.rs`)

```rust
use axum::{Router, routing::get};
use tower_http::trace::TraceLayer;
use std::net::SocketAddr;

mod api;
mod services;
mod repositories;
mod websocket;
mod middleware;
mod models;
mod db;
mod config;
mod errors;
mod utils;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Load configuration
    let config = config::Settings::load()?;

    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter("info,convro_server=debug")
        .init();

    // Connect to database
    let db_pool = db::pool::create_pool(&config.database_url).await?;

    // Run migrations
    sqlx::migrate!("./migrations").run(&db_pool).await?;

    // Create WebSocket hub
    let ws_hub = websocket::hub::Hub::new();

    // Build app state
    let app_state = AppState {
        db_pool,
        ws_hub: ws_hub.clone(),
        config: config.clone(),
    };

    // Build router
    let app = Router::new()
        .route("/health", get(api::health::health_check))
        .nest("/v1", api_routes())
        .with_state(app_state)
        .layer(TraceLayer::new_for_http())
        .layer(middleware::cors::cors_layer())
        .layer(middleware::request_id::request_id_layer());

    // Start WebSocket hub
    tokio::spawn(ws_hub.run());

    // Start server
    let addr: SocketAddr = format!("{}:{}", config.host, config.port).parse()?;
    tracing::info!("🚀 Server listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}

fn api_routes() -> Router<AppState> {
    Router::new()
        .merge(api::auth::routes())
        .merge(api::users::routes())
        .merge(api::devices::routes())
        .merge(api::prekeys::routes())
        .merge(api::messages::routes())
        .merge(api::contacts::routes())
        .merge(api::presence::routes())
        .route("/ws", get(websocket::connection::ws_handler))
}

#[derive(Clone)]
struct AppState {
    db_pool: sqlx::PgPool,
    ws_hub: websocket::hub::HubHandle,
    config: config::Settings,
}
```

---

### 4.2 Auth Handler Example (`api/auth.rs`)

```rust
use axum::{
    Router,
    Json,
    extract::State,
    routing::post,
};
use serde::{Deserialize, Serialize};
use validator::Validate;

use crate::{
    AppState,
    errors::{AppError, AppResult},
    services::auth_service::AuthService,
    models::auth::{AuthTokens, Claims},
};

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/auth/register", post(register))
        .route("/auth/login", post(login))
        .route("/auth/refresh", post(refresh_token))
        .route("/auth/logout", post(logout))
}

#[derive(Debug, Deserialize, Validate)]
struct RegisterRequest {
    #[validate(length(min = 3, max = 50))]
    username: String,

    #[validate(length(min = 8))]
    password: String,

    #[validate(length(max = 100))]
    display_name: Option<String>,
}

#[derive(Debug, Serialize)]
struct RegisterResponse {
    user_id: uuid::Uuid,
    username: String,
    convro_number: String,
    display_name: Option<String>,
    created_at: chrono::DateTime<chrono::Utc>,
    tokens: AuthTokens,
}

async fn register(
    State(state): State<AppState>,
    Json(req): Json<RegisterRequest>,
) -> AppResult<Json<RegisterResponse>> {
    // Validate request
    req.validate()
        .map_err(|e| AppError::ValidationError(e.to_string()))?;

    // Create user via service
    let auth_service = AuthService::new(state.db_pool.clone());
    let (user, tokens) = auth_service.register_user(
        req.username,
        req.password,
        req.display_name,
    ).await?;

    Ok(Json(RegisterResponse {
        user_id: user.user_id,
        username: user.username,
        convro_number: user.convro_number,
        display_name: user.display_name,
        created_at: user.created_at,
        tokens,
    }))
}

#[derive(Debug, Deserialize, Validate)]
struct LoginRequest {
    #[validate(length(min = 3))]
    username: String,

    #[validate(length(min = 1))]
    password: String,
}

async fn login(
    State(state): State<AppState>,
    Json(req): Json<LoginRequest>,
) -> AppResult<Json<RegisterResponse>> {
    // Validate
    req.validate()
        .map_err(|e| AppError::ValidationError(e.to_string()))?;

    // Authenticate
    let auth_service = AuthService::new(state.db_pool.clone());
    let (user, tokens) = auth_service.login(
        req.username,
        req.password,
    ).await?;

    Ok(Json(RegisterResponse {
        user_id: user.user_id,
        username: user.username,
        convro_number: user.convro_number,
        display_name: user.display_name,
        created_at: user.created_at,
        tokens,
    }))
}

#[derive(Debug, Deserialize)]
struct RefreshRequest {
    refresh_token: String,
}

#[derive(Debug, Serialize)]
struct RefreshResponse {
    access_token: String,
    expires_in: u64,
    token_type: String,
}

async fn refresh_token(
    State(state): State<AppState>,
    Json(req): Json<RefreshRequest>,
) -> AppResult<Json<RefreshResponse>> {
    let auth_service = AuthService::new(state.db_pool.clone());
    let access_token = auth_service.refresh_access_token(req.refresh_token).await?;

    Ok(Json(RefreshResponse {
        access_token,
        expires_in: 3600,
        token_type: "Bearer".to_string(),
    }))
}

async fn logout(
    State(state): State<AppState>,
    claims: Claims,  // Extracted by JWT middleware
) -> AppResult<StatusCode> {
    let auth_service = AuthService::new(state.db_pool.clone());
    auth_service.logout(claims.sub).await?;

    Ok(StatusCode::NO_CONTENT)
}
```

---

### 4.3 Auth Service (`services/auth_service.rs`)

```rust
use sqlx::PgPool;
use argon2::{Argon2, PasswordHash, PasswordHasher, PasswordVerifier};
use argon2::password_hash::{SaltString, rand_core::OsRng};
use uuid::Uuid;

use crate::{
    errors::{AppError, AppResult},
    models::{
        user::User,
        auth::{AuthTokens, Claims},
    },
    repositories::user_repo::UserRepository,
    utils::{jwt, convro_number},
};

pub struct AuthService {
    db_pool: PgPool,
}

impl AuthService {
    pub fn new(db_pool: PgPool) -> Self {
        Self { db_pool }
    }

    pub async fn register_user(
        &self,
        username: String,
        password: String,
        display_name: Option<String>,
    ) -> AppResult<(User, AuthTokens)> {
        let user_repo = UserRepository::new(self.db_pool.clone());

        // Check if username exists
        if user_repo.find_by_username(&username).await?.is_some() {
            return Err(AppError::Conflict("Username already exists".to_string()));
        }

        // Hash password
        let password_hash = Self::hash_password(&password)?;

        // Generate Convro Number (random strategy)
        let convro_number = loop {
            let candidate = convro_number::generate_random();
            if user_repo.is_convro_number_available(&candidate).await? {
                break candidate;
            }
        };

        // Create user in DB
        let user = user_repo.create(
            username,
            password_hash,
            convro_number,
            display_name,
        ).await?;

        // Generate JWT tokens
        let tokens = self.generate_tokens(&user)?;

        Ok((user, tokens))
    }

    pub async fn login(
        &self,
        username: String,
        password: String,
    ) -> AppResult<(User, AuthTokens)> {
        let user_repo = UserRepository::new(self.db_pool.clone());

        // Find user
        let user = user_repo.find_by_username(&username).await?
            .ok_or(AppError::Unauthorized("Invalid credentials".to_string()))?;

        // Verify password
        Self::verify_password(&password, &user.password_hash)?;

        // Generate tokens
        let tokens = self.generate_tokens(&user)?;

        // Update last_login
        user_repo.update_last_login(user.user_id).await?;

        Ok((user, tokens))
    }

    pub async fn refresh_access_token(
        &self,
        refresh_token: String,
    ) -> AppResult<String> {
        // Decode refresh token
        let claims = jwt::decode_token(&refresh_token)?;

        // Verify token type
        if claims.token_type != "refresh" {
            return Err(AppError::Unauthorized("Invalid token type".to_string()));
        }

        // Generate new access token
        let access_token = jwt::encode_access_token(claims.sub, claims.convro_number)?;

        Ok(access_token)
    }

    pub async fn logout(&self, user_id: Uuid) -> AppResult<()> {
        // For stateless JWT, just return success
        // In production: add token to blacklist with Redis
        Ok(())
    }

    fn generate_tokens(&self, user: &User) -> AppResult<AuthTokens> {
        let access_token = jwt::encode_access_token(user.user_id, user.convro_number.clone())?;
        let refresh_token = jwt::encode_refresh_token(user.user_id, user.convro_number.clone())?;

        Ok(AuthTokens {
            access_token,
            refresh_token,
            expires_in: 3600,
            token_type: "Bearer".to_string(),
        })
    }

    fn hash_password(password: &str) -> AppResult<String> {
        let salt = SaltString::generate(&mut OsRng);
        let argon2 = Argon2::default();

        let password_hash = argon2
            .hash_password(password.as_bytes(), &salt)
            .map_err(|e| AppError::InternalError(format!("Password hashing failed: {}", e)))?
            .to_string();

        Ok(password_hash)
    }

    fn verify_password(password: &str, hash: &str) -> AppResult<()> {
        let parsed_hash = PasswordHash::new(hash)
            .map_err(|e| AppError::InternalError(format!("Invalid password hash: {}", e)))?;

        Argon2::default()
            .verify_password(password.as_bytes(), &parsed_hash)
            .map_err(|_| AppError::Unauthorized("Invalid credentials".to_string()))
    }
}
```

---

### 4.4 JWT Middleware (`middleware/auth.rs`)

```rust
use axum::{
    extract::Request,
    middleware::Next,
    response::Response,
};
use axum::http::StatusCode;

use crate::{
    errors::{AppError, AppResult},
    models::auth::Claims,
    utils::jwt,
};

pub async fn require_auth(
    mut req: Request,
    next: Next,
) -> Result<Response, StatusCode> {
    // Extract Authorization header
    let auth_header = req.headers()
        .get("Authorization")
        .and_then(|v| v.to_str().ok())
        .ok_or(StatusCode::UNAUTHORIZED)?;

    // Parse "Bearer {token}"
    let token = auth_header
        .strip_prefix("Bearer ")
        .ok_or(StatusCode::UNAUTHORIZED)?;

    // Decode JWT
    let claims = jwt::decode_token(token)
        .map_err(|_| StatusCode::UNAUTHORIZED)?;

    // Verify token type
    if claims.token_type != "access" {
        return Err(StatusCode::UNAUTHORIZED);
    }

    // Insert claims into request extensions
    req.extensions_mut().insert(claims);

    Ok(next.run(req).await)
}

// Axum extractor for Claims
#[axum::async_trait]
impl<S> axum::extract::FromRequestParts<S> for Claims
where
    S: Send + Sync,
{
    type Rejection = StatusCode;

    async fn from_request_parts(
        parts: &mut axum::http::request::Parts,
        _state: &S,
    ) -> Result<Self, Self::Rejection> {
        parts.extensions
            .get::<Claims>()
            .cloned()
            .ok_or(StatusCode::UNAUTHORIZED)
    }
}
```

---

### 4.5 Prekey Repository (`repositories/prekey_repo.rs`)

```rust
use sqlx::PgPool;
use uuid::Uuid;

use crate::{
    errors::{AppError, AppResult},
    models::prekey::{PrekeyBundle, SignedPrekey, OneTimePrekey},
};

pub struct PrekeyRepository {
    db_pool: PgPool,
}

impl PrekeyRepository {
    pub fn new(db_pool: PgPool) -> Self {
        Self { db_pool }
    }

    pub async fn upload_prekeys(
        &self,
        device_identity_id: Uuid,
        signed_prekey: SignedPrekey,
        one_time_prekeys: Vec<OneTimePrekey>,
    ) -> AppResult<Uuid> {
        let mut tx = self.db_pool.begin().await?;

        // Insert signed prekey
        let bundle_id = sqlx::query_scalar!(
            r#"
            INSERT INTO prekey_bundles (
                device_identity_id,
                signed_prekey,
                signed_prekey_signature,
                signed_prekey_id,
                expires_at
            )
            VALUES ($1, $2, $3, $4, $5)
            RETURNING bundle_id
            "#,
            device_identity_id,
            signed_prekey.public_key,
            signed_prekey.signature,
            signed_prekey.spk_id,
            signed_prekey.expires_at,
        )
        .fetch_one(&mut *tx)
        .await?;

        // Insert one-time prekeys
        for otp in one_time_prekeys {
            sqlx::query!(
                r#"
                INSERT INTO one_time_prekeys (
                    device_identity_id,
                    one_time_prekey,
                    otp_key_id
                )
                VALUES ($1, $2, $3)
                "#,
                device_identity_id,
                otp.public_key,
                otp.otp_id,
            )
            .execute(&mut *tx)
            .await?;
        }

        tx.commit().await?;

        Ok(bundle_id)
    }

    pub async fn fetch_bundle(
        &self,
        convro_number: &str,
    ) -> AppResult<Option<PrekeyBundle>> {
        // This uses the VIEW from database schema
        let result = sqlx::query_as!(
            PrekeyBundle,
            r#"
            SELECT
                u.user_id,
                u.convro_number,
                di.device_identity_id,
                di.device_id,
                di.identity_key,
                pb.signed_prekey,
                pb.signed_prekey_signature,
                pb.signed_prekey_id as spk_id,
                otp.otp_id,
                otp.one_time_prekey
            FROM users u
            JOIN device_identities di ON u.user_id = di.user_id
            JOIN prekey_bundles pb ON di.device_identity_id = pb.device_identity_id
            LEFT JOIN LATERAL (
                SELECT otp_id, one_time_prekey
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
            convro_number
        )
        .fetch_optional(&self.db_pool)
        .await?;

        Ok(result)
    }

    pub async fn consume_otp(
        &self,
        otp_id: Uuid,
        consumed_by: Uuid,
    ) -> AppResult<bool> {
        // Call the database function (with SELECT FOR UPDATE)
        let result = sqlx::query_scalar!(
            r#"
            SELECT consume_otp($1, $2) as "consumed!"
            "#,
            otp_id,
            consumed_by,
        )
        .fetch_one(&self.db_pool)
        .await?;

        Ok(result)
    }
}
```

---

## 5. Middleware Pipeline

### 5.1 Rate Limiting (`middleware/rate_limit.rs`)

```rust
use axum::{
    extract::Request,
    middleware::Next,
    response::Response,
    http::StatusCode,
};
use governor::{Quota, RateLimiter};
use std::sync::Arc;
use std::num::NonZeroU32;

pub struct RateLimitLayer {
    limiter: Arc<RateLimiter<String, _, _>>,
}

impl RateLimitLayer {
    pub fn new(requests_per_minute: u32) -> Self {
        let quota = Quota::per_minute(NonZeroU32::new(requests_per_minute).unwrap());
        let limiter = Arc::new(RateLimiter::keyed(quota));

        Self { limiter }
    }

    pub async fn check(
        &self,
        req: Request,
        next: Next,
    ) -> Result<Response, StatusCode> {
        // Extract key (user_id or IP)
        let key = extract_key(&req);

        // Check rate limit
        if self.limiter.check_key(&key).is_err() {
            return Err(StatusCode::TOO_MANY_REQUESTS);
        }

        Ok(next.run(req).await)
    }
}

fn extract_key(req: &Request) -> String {
    // Prefer user_id from JWT, fallback to IP
    req.extensions()
        .get::<Claims>()
        .map(|c| c.sub.to_string())
        .unwrap_or_else(|| "anonymous".to_string())
}
```

---

## 6. WebSocket Hub

### 6.1 Hub (`websocket/hub.rs`)

```rust
use tokio::sync::{mpsc, RwLock};
use std::collections::HashMap;
use std::sync::Arc;
use uuid::Uuid;

pub type HubHandle = Arc<Hub>;

pub struct Hub {
    connections: Arc<RwLock<HashMap<Uuid, mpsc::UnboundedSender<WsMessage>>>>,
}

impl Hub {
    pub fn new() -> HubHandle {
        Arc::new(Self {
            connections: Arc::new(RwLock::new(HashMap::new())),
        })
    }

    pub async fn register(
        &self,
        user_id: Uuid,
        tx: mpsc::UnboundedSender<WsMessage>,
    ) {
        self.connections.write().await.insert(user_id, tx);
        tracing::info!("User {} connected to WebSocket", user_id);
    }

    pub async fn unregister(&self, user_id: &Uuid) {
        self.connections.write().await.remove(user_id);
        tracing::info!("User {} disconnected", user_id);
    }

    pub async fn send_to_user(
        &self,
        user_id: &Uuid,
        message: WsMessage,
    ) -> Result<(), ()> {
        if let Some(tx) = self.connections.read().await.get(user_id) {
            tx.send(message).map_err(|_| ())?;
            Ok(())
        } else {
            Err(())  // User offline
        }
    }

    pub async fn broadcast(&self, message: WsMessage) {
        let connections = self.connections.read().await;
        for tx in connections.values() {
            let _ = tx.send(message.clone());
        }
    }
}

#[derive(Clone, Debug)]
pub enum WsMessage {
    Message { /* ... */ },
    Typing { /* ... */ },
    Presence { /* ... */ },
    Ping,
    Pong,
}
```

---

## 7. Database Layer

### 7.1 Connection Pool (`db/pool.rs`)

```rust
use sqlx::{PgPool, postgres::PgPoolOptions};

pub async fn create_pool(database_url: &str) -> anyhow::Result<PgPool> {
    let pool = PgPoolOptions::new()
        .max_connections(50)
        .min_connections(5)
        .acquire_timeout(std::time::Duration::from_secs(10))
        .connect(database_url)
        .await?;

    tracing::info!("✅ Database connection pool created");

    Ok(pool)
}
```

---

## 8. Configuration

### 8.1 Settings (`config/settings.rs`)

```rust
use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub struct Settings {
    pub host: String,
    pub port: u16,
    pub database_url: String,
    pub jwt_secret: String,
    pub jwt_access_expiry: u64,   // seconds
    pub jwt_refresh_expiry: u64,  // seconds
}

impl Settings {
    pub fn load() -> anyhow::Result<Self> {
        dotenv::dotenv().ok();

        let settings = config::Config::builder()
            .add_source(config::Environment::default())
            .build()?;

        Ok(settings.try_deserialize()?)
    }
}
```

**`.env.example`:**
```bash
HOST=0.0.0.0
PORT=8080
DATABASE_URL=postgres://convro_app:password@localhost:5432/convro
JWT_SECRET=your_secret_key_change_this_in_production
JWT_ACCESS_EXPIRY=3600
JWT_REFRESH_EXPIRY=2592000
```

---

## 9. Error Handling

### 9.1 AppError (`errors/app_error.rs`)

```rust
use axum::{
    response::{IntoResponse, Response},
    http::StatusCode,
    Json,
};
use serde::Serialize;

#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("Database error: {0}")]
    DatabaseError(#[from] sqlx::Error),

    #[error("Validation error: {0}")]
    ValidationError(String),

    #[error("Unauthorized: {0}")]
    Unauthorized(String),

    #[error("Not found: {0}")]
    NotFound(String),

    #[error("Conflict: {0}")]
    Conflict(String),

    #[error("Internal error: {0}")]
    InternalError(String),

    #[error("Rate limit exceeded")]
    RateLimitExceeded,
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, error_code, message) = match self {
            AppError::DatabaseError(_) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                "INTERNAL_ERROR",
                "Database error occurred",
            ),
            AppError::ValidationError(ref msg) => (
                StatusCode::BAD_REQUEST,
                "VALIDATION_ERROR",
                msg.as_str(),
            ),
            AppError::Unauthorized(ref msg) => (
                StatusCode::UNAUTHORIZED,
                "UNAUTHORIZED",
                msg.as_str(),
            ),
            AppError::NotFound(ref msg) => (
                StatusCode::NOT_FOUND,
                "NOT_FOUND",
                msg.as_str(),
            ),
            AppError::Conflict(ref msg) => (
                StatusCode::CONFLICT,
                "CONFLICT",
                msg.as_str(),
            ),
            AppError::InternalError(_) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                "INTERNAL_ERROR",
                "Internal error occurred",
            ),
            AppError::RateLimitExceeded => (
                StatusCode::TOO_MANY_REQUESTS,
                "RATE_LIMIT_EXCEEDED",
                "Too many requests",
            ),
        };

        let error_response = ErrorResponse {
            error: ErrorDetail {
                code: error_code.to_string(),
                message: message.to_string(),
                timestamp: chrono::Utc::now(),
            },
        };

        (status, Json(error_response)).into_response()
    }
}

#[derive(Serialize)]
struct ErrorResponse {
    error: ErrorDetail,
}

#[derive(Serialize)]
struct ErrorDetail {
    code: String,
    message: String,
    timestamp: chrono::DateTime<chrono::Utc>,
}

pub type AppResult<T> = Result<T, AppError>;
```

---

## 10. Testing Strategy

### 10.1 Integration Test Example

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_register_and_login() {
        let app = create_test_app().await;

        // Register
        let register_req = RegisterRequest {
            username: "alice".to_string(),
            password: "SecurePass123!".to_string(),
            display_name: Some("Alice".to_string()),
        };

        let response = app
            .oneshot(
                Request::builder()
                    .uri("/v1/auth/register")
                    .method("POST")
                    .header("Content-Type", "application/json")
                    .body(serde_json::to_string(&register_req).unwrap())
                    .unwrap()
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::CREATED);

        // Login
        let login_req = LoginRequest {
            username: "alice".to_string(),
            password: "SecurePass123!".to_string(),
        };

        let response = app
            .oneshot(
                Request::builder()
                    .uri("/v1/auth/login")
                    .method("POST")
                    .header("Content-Type", "application/json")
                    .body(serde_json::to_string(&login_req).unwrap())
                    .unwrap()
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
    }
}
```

---

## Next Steps

1. **Initialize Rust project:**
   ```bash
   cargo new server --name convro-server
   cd server
   ```

2. **Add dependencies to Cargo.toml**

3. **Implement modules incrementally:**
   - Config + DB pool
   - Error handling
   - Auth (register, login)
   - Devices
   - Prekeys
   - Messages
   - WebSocket

4. **Test each module:**
   - Unit tests
   - Integration tests
   - Load tests (k6)

5. **Deploy:**
   - Docker + docker-compose
   - Kubernetes (optional)

---

**Ready to start implementation?** 🚀

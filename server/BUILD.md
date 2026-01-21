# Convro Server - Build Guide

## Prerequisites

1. **Rust** (1.70+)
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   ```

2. **PostgreSQL** (15+)
   - macOS: `brew install postgresql@15`
   - Linux: `sudo apt install postgresql-15`

3. **SQLx CLI** (for database migrations)
   ```bash
   cargo install sqlx-cli --no-default-features --features postgres
   ```

## Database Setup

### 1. Create Database

```bash
# Start PostgreSQL
# macOS: brew services start postgresql@15
# Linux: sudo systemctl start postgresql

# Create database and user
psql postgres <<SQL
CREATE USER convro_app WITH PASSWORD 'your_secure_password';
CREATE DATABASE convro;
GRANT ALL PRIVILEGES ON DATABASE convro TO convro_app;
\c convro
GRANT ALL ON SCHEMA public TO convro_app;
SQL
```

### 2. Configure Environment

```bash
cd server
cp .env.example .env
# Edit .env and update DATABASE_URL with your password
```

### 3. Run Migrations

```bash
cd server
sqlx database create  # Creates database if it doesn't exist
sqlx migrate run --source ../database  # Runs all migrations
```

### 4. Prepare SQLx Query Cache (for offline builds)

```bash
cargo sqlx prepare --workspace
```

This generates `.sqlx/query-*.json` files containing query metadata, allowing compilation without a database connection.

## Building

### Standard Build (requires database)

```bash
cargo build --release
```

### Offline Build (after running `cargo sqlx prepare`)

```bash
SQLX_OFFLINE=true cargo build --release
```

### Development Build

```bash
cargo check  # Type checking only
cargo build  # Debug build
```

## Running

```bash
cargo run --release
```

Or directly:

```bash
./target/release/convro-server
```

The server will:
1. Load configuration from `.env`
2. Connect to PostgreSQL
3. Run pending migrations
4. Start HTTP server on configured HOST:PORT (default: 0.0.0.0:8080)

## Testing

```bash
# Unit tests
cargo test

# Integration tests (requires database)
cargo test --test integration_tests
```

## Docker Build (Alternative)

```bash
# Build image
docker build -t convro-server .

# Run with docker-compose
docker-compose up
```

## Troubleshooting

### SQLx Compilation Errors

**Error:** `set DATABASE_URL to use query macros online`

**Solution:** Either:
1. Set up database and run `cargo sqlx prepare`
2. Use offline mode: `SQLX_OFFLINE=true cargo check`

### Database Connection Errors

**Error:** `connection refused`

**Solution:**
1. Ensure PostgreSQL is running
2. Check DATABASE_URL in `.env`
3. Verify user permissions

### Migration Errors

**Error:** `migration already applied`

**Solution:**
```bash
sqlx migrate revert --source ../database  # Revert last migration
sqlx migrate run --source ../database     # Re-run migrations
```

## Production Deployment

1. **Change JWT_SECRET** to a secure random value (min 32 chars)
2. **Use strong database password**
3. **Enable TLS** for database connections
4. **Configure CORS** for your domain
5. **Set up monitoring** (Prometheus/Grafana)
6. **Use reverse proxy** (Nginx/Caddy) for HTTPS

## Architecture

- **Web Framework:** Axum 0.7
- **Database:** PostgreSQL 15+ with SQLx
- **Authentication:** JWT (stateless)
- **Password Hashing:** Argon2id
- **Logging:** tracing + tracing-subscriber
- **Concurrency:** Tokio async runtime

## API Documentation

See [API_SPECIFICATION.md](../docs/api/API_SPECIFICATION.md) for complete API documentation.

## WebSocket Protocol

See [API_SPECIFICATION.md](../docs/api/API_SPECIFICATION.md#websocket-protocol) for WebSocket message types and protocol details.

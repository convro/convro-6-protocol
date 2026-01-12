-- ============================================================================
-- C6P Protocol - Production PostgreSQL Database Schema
-- ============================================================================
--
-- ⚠️ CRITICAL SECURITY REQUIREMENTS (Threat Model Compliance):
-- 1. Server NEVER sees encryption keys (zero-knowledge architecture)
-- 2. Atomic state transitions (OTP race conditions prevented)
-- 3. Immutable encrypted blobs (tamper-proof)
-- 4. SERIALIZABLE isolation (concurrency safety)
--
-- This schema supports a complete E2EE messaging system with:
-- - Convro Numbers (universal user IDs)
-- - Device-level E2EE (Island Accord handshake)
-- - Realtime message delivery (WebSocket support)
-- - Push notifications (APNs/FCM tokens)
-- - Offline message queue
-- - Presence tracking
-- - Contact management
--
-- PostgreSQL 15+ required for:
-- - Native UUID generation (gen_random_uuid)
-- - JSON/JSONB support
-- - Advanced indexing
-- - Strong ACID guarantees
-- - Row-level locking (SELECT FOR UPDATE)
--
-- ============================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- SECURITY: Set default transaction isolation level
-- ============================================================================
-- CRITICAL: Prevents OTP race conditions and double-accept attacks
-- Ref: C6P-Threat-Model-CONCISE.pdf, Threats 7, 11

ALTER DATABASE postgres SET default_transaction_isolation TO 'serializable';

-- ============================================================================
-- TABLE: users
-- ============================================================================
-- Stores user accounts with Convro Numbers

CREATE TABLE users (
    -- Primary key
    user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Convro Number (unique identifier like "+99123456")
    convro_number VARCHAR(15) UNIQUE NOT NULL,

    -- Authentication
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL, -- Argon2id hash

    -- Account metadata
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_login TIMESTAMP WITH TIME ZONE,
    account_status VARCHAR(20) DEFAULT 'active', -- active, suspended, deleted

    -- Optional profile (minimal PII)
    display_name VARCHAR(100),

    -- Timestamps
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for fast lookups
CREATE INDEX idx_users_convro_number ON users(convro_number);
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_created_at ON users(created_at DESC);
CREATE INDEX idx_users_account_status ON users(account_status) WHERE account_status != 'active';

-- Comments
COMMENT ON TABLE users IS 'User accounts with Convro Numbers';
COMMENT ON COLUMN users.convro_number IS 'Unique user identifier in format +99XXXXXX';
COMMENT ON COLUMN users.password_hash IS 'Argon2id hash, never store plaintext passwords';

-- ============================================================================
-- TABLE: device_identities
-- ============================================================================
-- Each user can have multiple devices (multi-device support)
-- Each device has its own E2EE identity (Ed25519 + X25519 keys)

CREATE TABLE device_identities (
    -- Primary key
    device_identity_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Owner
    user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,

    -- Device identity (from C6P identity_generate_identity)
    device_id BYTEA NOT NULL, -- Ed25519 public key (32 bytes)
    identity_key BYTEA NOT NULL, -- X25519 public key (32 bytes)

    -- Device metadata
    device_name VARCHAR(100), -- "John's iPhone 14 Pro"
    device_platform VARCHAR(20), -- "ios", "android", "desktop"
    device_os_version VARCHAR(50),
    app_version VARCHAR(20),

    -- Lifecycle
    registered_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_seen TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT TRUE,

    -- Timestamps
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Constraints
    UNIQUE(device_id)
);

-- Indexes
CREATE INDEX idx_device_user ON device_identities(user_id);
CREATE INDEX idx_device_id ON device_identities(device_id);
CREATE INDEX idx_device_active ON device_identities(user_id, is_active) WHERE is_active = TRUE;
CREATE INDEX idx_device_last_seen ON device_identities(last_seen DESC);

-- Comments
COMMENT ON TABLE device_identities IS 'Device-level E2EE identities for multi-device support';
COMMENT ON COLUMN device_identities.device_id IS 'Ed25519 public key identifying this device';
COMMENT ON COLUMN device_identities.identity_key IS 'X25519 public key for key agreement';

-- ============================================================================
-- TABLE: prekey_bundles
-- ============================================================================
-- Stores signed prekeys for each device (rotated periodically)

CREATE TABLE prekey_bundles (
    -- Primary key
    bundle_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Device this bundle belongs to
    device_identity_id UUID NOT NULL REFERENCES device_identities(device_identity_id) ON DELETE CASCADE,

    -- Signed Prekey (SPK)
    signed_prekey BYTEA NOT NULL, -- X25519 public key (32 bytes)
    signed_prekey_signature BYTEA NOT NULL, -- Ed25519 signature (64 bytes)
    signed_prekey_id INTEGER NOT NULL,

    -- Lifecycle
    uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE, -- Rotate weekly (uploaded_at + 7 days)
    is_active BOOLEAN DEFAULT TRUE,

    -- Usage tracking (for rotation reminders)
    usage_count INTEGER DEFAULT 0,

    -- Timestamps
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_prekey_device ON prekey_bundles(device_identity_id);
CREATE INDEX idx_prekey_active ON prekey_bundles(device_identity_id, is_active) WHERE is_active = TRUE;
CREATE INDEX idx_prekey_expires ON prekey_bundles(expires_at) WHERE is_active = TRUE;

-- Comments
COMMENT ON TABLE prekey_bundles IS 'Signed prekeys for handshake, rotated weekly';
COMMENT ON COLUMN prekey_bundles.expires_at IS 'Signed prekeys should be rotated every 7 days';

-- ============================================================================
-- TABLE: one_time_prekeys
-- ============================================================================
-- Pool of single-use prekeys (OTPs) for forward secrecy
-- Each OTP is consumed once during handshake

CREATE TABLE one_time_prekeys (
    -- Primary key
    otp_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Device this OTP belongs to
    device_identity_id UUID NOT NULL REFERENCES device_identities(device_identity_id) ON DELETE CASCADE,

    -- One-Time Prekey
    one_time_prekey BYTEA NOT NULL, -- X25519 public key (32 bytes)
    otp_key_id INTEGER NOT NULL,

    -- Lifecycle
    uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    consumed_at TIMESTAMP WITH TIME ZONE,
    consumed_by UUID REFERENCES users(user_id), -- Who used this OTP

    -- Timestamps
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_otp_device ON one_time_prekeys(device_identity_id);
CREATE INDEX idx_otp_available ON one_time_prekeys(device_identity_id, consumed_at)
    WHERE consumed_at IS NULL;
CREATE INDEX idx_otp_consumed ON one_time_prekeys(consumed_at) WHERE consumed_at IS NOT NULL;

-- Comments
COMMENT ON TABLE one_time_prekeys IS 'Single-use prekeys for forward secrecy in handshake';
COMMENT ON COLUMN one_time_prekeys.consumed_at IS 'NULL = available, NOT NULL = already used';

-- ============================================================================
-- TABLE: sessions
-- ============================================================================
-- Tracks E2EE sessions between devices
--
-- ⚠️ ZERO-KNOWLEDGE ARCHITECTURE:
-- - Server NEVER stores, derives, or sees encryption keys
-- - Only session_id (identifier) and metadata are stored
-- - All E2EE keys managed client-side (iOS Keychain, Android KeyStore)
-- - Compromise of this table reveals metadata only, NOT message content
-- Ref: C6P-Threat-Model-CONCISE.pdf, Section 2.3 Trust Boundaries

CREATE TABLE sessions (
    -- Session ID from C6P protocol (32 bytes)
    session_id BYTEA PRIMARY KEY,

    -- Participants (device-to-device session)
    initiator_device_id UUID NOT NULL REFERENCES device_identities(device_identity_id),
    responder_device_id UUID NOT NULL REFERENCES device_identities(device_identity_id),

    -- User-level mapping (for UI convenience)
    initiator_user_id UUID NOT NULL REFERENCES users(user_id),
    responder_user_id UUID NOT NULL REFERENCES users(user_id),

    -- Session metadata (NOT keys!)
    session_type VARCHAR(20) DEFAULT 'dm', -- 'dm' (direct message), 'group' (future)
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_activity TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Usage statistics
    message_count INTEGER DEFAULT 0,

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    -- Timestamps
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_session_initiator ON sessions(initiator_device_id);
CREATE INDEX idx_session_responder ON sessions(responder_device_id);
CREATE INDEX idx_session_users ON sessions(initiator_user_id, responder_user_id);
CREATE INDEX idx_session_active ON sessions(is_active) WHERE is_active = TRUE;
CREATE INDEX idx_session_last_activity ON sessions(last_activity DESC);

-- Comments
COMMENT ON TABLE sessions IS 'E2EE session metadata - keys are NEVER stored on server!';
COMMENT ON COLUMN sessions.session_id IS 'C6P protocol session identifier';

-- ============================================================================
-- TABLE: messages
-- ============================================================================
-- Stores encrypted messages (server-opaque blobs)
--
-- ⚠️ ZERO-KNOWLEDGE + IMMUTABILITY:
-- - Server CANNOT read message content (encrypted by C6P protocol)
-- - encrypted_blob is IMMUTABLE after creation (tamper-proof)
-- - Any modification attempt triggers database error (see trigger below)
-- - Server only sees: metadata (routing, timestamps, sizes)
-- Ref: C6P-Threat-Model-CONCISE.pdf, Threats 2, 4 (tamper prevention)

CREATE TABLE messages (
    -- Primary key
    message_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Routing (user-level for simplicity)
    from_user_id UUID NOT NULL REFERENCES users(user_id),
    to_user_id UUID NOT NULL REFERENCES users(user_id),
    from_convro_number VARCHAR(15) NOT NULL,
    to_convro_number VARCHAR(15) NOT NULL,

    -- Session this message belongs to
    session_id BYTEA REFERENCES sessions(session_id),

    -- Message type
    message_type VARCHAR(30) NOT NULL,
    -- Types: 'handshake_offer', 'handshake_accept', 'encrypted_message'

    -- Encrypted payload (OPAQUE to server!)
    encrypted_blob BYTEA NOT NULL,

    -- Delivery tracking
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    delivered_at TIMESTAMP WITH TIME ZONE, -- When delivered via WebSocket or polling
    read_at TIMESTAMP WITH TIME ZONE, -- When recipient opened message

    -- Status
    delivery_status VARCHAR(20) DEFAULT 'pending',
    -- Status: 'pending', 'delivered', 'read', 'failed'

    -- Retry tracking (for offline users)
    retry_count INTEGER DEFAULT 0,
    next_retry_at TIMESTAMP WITH TIME ZONE,

    -- Server-side expiration (delete after X days)
    expires_at TIMESTAMP WITH TIME ZONE DEFAULT (NOW() + INTERVAL '30 days'),

    -- Timestamps
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for efficient queries
CREATE INDEX idx_messages_recipient ON messages(to_user_id, delivered_at)
    WHERE delivered_at IS NULL; -- Undelivered messages
CREATE INDEX idx_messages_session ON messages(session_id, created_at DESC);
CREATE INDEX idx_messages_created ON messages(created_at DESC);
CREATE INDEX idx_messages_expires ON messages(expires_at) WHERE delivery_status != 'delivered';
CREATE INDEX idx_messages_from_to ON messages(from_user_id, to_user_id, created_at DESC);

-- Partial index for pending deliveries (hot path)
CREATE INDEX idx_messages_pending ON messages(to_convro_number, created_at)
    WHERE delivery_status = 'pending';

-- Comments
COMMENT ON TABLE messages IS 'Encrypted message blobs - server cannot decrypt!';
COMMENT ON COLUMN messages.encrypted_blob IS 'Encrypted by C6P protocol, opaque to server';
COMMENT ON COLUMN messages.expires_at IS 'Server deletes messages after 30 days for privacy';

-- ============================================================================
-- TABLE: contacts
-- ============================================================================
-- User's contact list (optional, for UX convenience)

CREATE TABLE contacts (
    -- Primary key
    contact_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Owner of this contact entry
    user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,

    -- Contact they added
    contact_convro_number VARCHAR(15) NOT NULL,
    contact_user_id UUID REFERENCES users(user_id), -- Resolved user (if exists)

    -- Display name (user-chosen, not from server)
    display_name VARCHAR(100),

    -- Verification status (fingerprint verification)
    is_verified BOOLEAN DEFAULT FALSE,
    verified_at TIMESTAMP WITH TIME ZONE,

    -- Lifecycle
    added_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Timestamps
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Constraints
    UNIQUE(user_id, contact_convro_number)
);

-- Indexes
CREATE INDEX idx_contacts_user ON contacts(user_id, added_at DESC);
CREATE INDEX idx_contacts_convro ON contacts(contact_convro_number);

-- Comments
COMMENT ON TABLE contacts IS 'User contact lists (client-side feature)';
COMMENT ON COLUMN contacts.is_verified IS 'True if user verified fingerprint out-of-band';

-- ============================================================================
-- TABLE: push_tokens
-- ============================================================================
-- Stores device push notification tokens (APNs for iOS, FCM for Android)

CREATE TABLE push_tokens (
    -- Primary key
    token_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Device this token belongs to
    device_identity_id UUID NOT NULL REFERENCES device_identities(device_identity_id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,

    -- Push token from device
    push_token TEXT NOT NULL,
    platform VARCHAR(20) NOT NULL, -- 'apns' (iOS), 'fcm' (Android)

    -- APNs specific
    apns_environment VARCHAR(20), -- 'production', 'sandbox'

    -- Lifecycle
    registered_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_used_at TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT TRUE,

    -- Timestamps
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Constraints
    UNIQUE(push_token)
);

-- Indexes
CREATE INDEX idx_push_user ON push_tokens(user_id, is_active) WHERE is_active = TRUE;
CREATE INDEX idx_push_device ON push_tokens(device_identity_id);
CREATE INDEX idx_push_token ON push_tokens(push_token) WHERE is_active = TRUE;

-- Comments
COMMENT ON TABLE push_tokens IS 'Device push notification tokens (APNs/FCM)';
COMMENT ON COLUMN push_tokens.push_token IS 'Token from APNs or FCM, device-specific';

-- ============================================================================
-- TABLE: presence
-- ============================================================================
-- Tracks user online/offline status for realtime features

CREATE TABLE presence (
    -- Primary key
    presence_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- User
    user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,

    -- Status
    status VARCHAR(20) NOT NULL DEFAULT 'offline',
    -- Status: 'online', 'offline', 'away'

    -- WebSocket connection tracking
    ws_connection_id TEXT, -- Internal WebSocket connection ID
    connected_at TIMESTAMP WITH TIME ZONE,
    last_heartbeat TIMESTAMP WITH TIME ZONE,

    -- Timestamps
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Constraints
    UNIQUE(user_id)
);

-- Indexes
CREATE INDEX idx_presence_status ON presence(status, updated_at) WHERE status = 'online';
CREATE INDEX idx_presence_heartbeat ON presence(last_heartbeat) WHERE status = 'online';

-- Comments
COMMENT ON TABLE presence IS 'User online/offline status for realtime features';
COMMENT ON COLUMN presence.last_heartbeat IS 'WebSocket sends heartbeat every 30s';

-- ============================================================================
-- TABLE: message_queue
-- ============================================================================
-- Temporary queue for realtime message delivery via WebSocket
-- Messages moved here when recipient is online

CREATE TABLE message_queue (
    -- Primary key
    queue_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Recipient
    user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    convro_number VARCHAR(15) NOT NULL,

    -- Reference to actual message
    message_id UUID NOT NULL REFERENCES messages(message_id) ON DELETE CASCADE,

    -- Queue metadata
    queued_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    priority INTEGER DEFAULT 0, -- Higher priority = deliver first

    -- Delivery attempts
    delivery_attempts INTEGER DEFAULT 0,
    last_attempt_at TIMESTAMP WITH TIME ZONE,

    -- Status
    status VARCHAR(20) DEFAULT 'queued',
    -- Status: 'queued', 'delivering', 'delivered', 'failed'

    -- Timestamps
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for efficient queue processing
CREATE INDEX idx_queue_user ON message_queue(user_id, queued_at)
    WHERE status = 'queued';
CREATE INDEX idx_queue_priority ON message_queue(priority DESC, queued_at)
    WHERE status = 'queued';
CREATE INDEX idx_queue_message ON message_queue(message_id);

-- Comments
COMMENT ON TABLE message_queue IS 'Realtime delivery queue for online users (WebSocket)';
COMMENT ON COLUMN message_queue.priority IS 'Higher priority messages delivered first';

-- ============================================================================
-- TABLE: audit_log
-- ============================================================================
-- Security audit trail for important events

CREATE TABLE audit_log (
    -- Primary key
    log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Event details
    event_type VARCHAR(50) NOT NULL,
    -- Examples: 'user_registered', 'user_login', 'device_added', 'prekey_uploaded',
    --           'handshake_initiated', 'message_sent', 'session_created'

    -- Actor
    user_id UUID REFERENCES users(user_id),
    device_identity_id UUID REFERENCES device_identities(device_identity_id),

    -- Context
    event_data JSONB, -- Additional event-specific data
    ip_address INET,
    user_agent TEXT,

    -- Result
    success BOOLEAN NOT NULL,
    error_message TEXT,

    -- Timestamp
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_audit_user ON audit_log(user_id, created_at DESC);
CREATE INDEX idx_audit_event ON audit_log(event_type, created_at DESC);
CREATE INDEX idx_audit_created ON audit_log(created_at DESC);
CREATE INDEX idx_audit_failures ON audit_log(success, created_at DESC) WHERE success = FALSE;

-- Comments
COMMENT ON TABLE audit_log IS 'Security audit trail for all significant events';
COMMENT ON COLUMN audit_log.event_data IS 'JSON blob with event-specific details';

-- ============================================================================
-- FUNCTIONS & TRIGGERS
-- ============================================================================

-- Function: Update updated_at timestamp automatically
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for auto-updating updated_at
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_device_identities_updated_at BEFORE UPDATE ON device_identities
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_prekey_bundles_updated_at BEFORE UPDATE ON prekey_bundles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_one_time_prekeys_updated_at BEFORE UPDATE ON one_time_prekeys
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_sessions_updated_at BEFORE UPDATE ON sessions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_messages_updated_at BEFORE UPDATE ON messages
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_contacts_updated_at BEFORE UPDATE ON contacts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_push_tokens_updated_at BEFORE UPDATE ON push_tokens
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_presence_updated_at BEFORE UPDATE ON presence
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_message_queue_updated_at BEFORE UPDATE ON message_queue
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- SECURITY: Immutability Protection
-- ============================================================================
-- Ref: C6P-Threat-Model-CONCISE.pdf, Threats 2, 4 (tamper prevention)

-- Function: Prevent modification of immutable encrypted blobs
CREATE OR REPLACE FUNCTION prevent_encrypted_blob_modification()
RETURNS TRIGGER AS $$
BEGIN
    -- Prevent any modification of encrypted_blob after creation
    IF OLD.encrypted_blob IS DISTINCT FROM NEW.encrypted_blob THEN
        RAISE EXCEPTION 'encrypted_blob is immutable and cannot be modified after creation'
            USING ERRCODE = 'integrity_constraint_violation',
                  HINT = 'Messages are tamper-proof by design (C6P Threat Model)',
                  DETAIL = format('Attempted to modify message_id: %s', OLD.message_id);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger: Enforce message blob immutability
CREATE TRIGGER enforce_message_blob_immutability
BEFORE UPDATE ON messages
FOR EACH ROW
EXECUTE FUNCTION prevent_encrypted_blob_modification();

COMMENT ON FUNCTION prevent_encrypted_blob_modification() IS
'⚠️ SECURITY: Prevents tampering with encrypted message content (Threats 2, 4)';

-- Function: Auto-expire old messages
CREATE OR REPLACE FUNCTION cleanup_expired_messages()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM messages
    WHERE expires_at < NOW()
      AND delivery_status = 'delivered';

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Function: Get available OTPs for a device
CREATE OR REPLACE FUNCTION get_available_otp_count(p_device_identity_id UUID)
RETURNS INTEGER AS $$
DECLARE
    otp_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO otp_count
    FROM one_time_prekeys
    WHERE device_identity_id = p_device_identity_id
      AND consumed_at IS NULL;

    RETURN otp_count;
END;
$$ LANGUAGE plpgsql;

-- Function: Consume an OTP (mark as used)
-- ⚠️ CRITICAL: Uses row-level locking to prevent race conditions
-- Ref: C6P-Threat-Model-CONCISE.pdf, Threat 7 (OTP double-use prevention)
CREATE OR REPLACE FUNCTION consume_otp(
    p_otp_id UUID,
    p_consumed_by_user_id UUID
)
RETURNS BOOLEAN AS $$
DECLARE
    otp_record RECORD;
BEGIN
    -- CRITICAL: Row-level locking prevents concurrent access (Threat 7)
    -- SELECT FOR UPDATE blocks other transactions from reading this row
    -- until the current transaction commits or rolls back
    SELECT * INTO otp_record
    FROM one_time_prekeys
    WHERE otp_id = p_otp_id
    FOR UPDATE;  -- ⚠️ BLOCKS concurrent access

    -- OTP not found
    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    -- OTP already consumed (should never happen with SERIALIZABLE + FOR UPDATE)
    IF otp_record.consumed_at IS NOT NULL THEN
        RAISE EXCEPTION 'OTP already consumed (ID: %, consumed_at: %, consumed_by: %)',
            p_otp_id, otp_record.consumed_at, otp_record.consumed_by
            USING ERRCODE = 'integrity_constraint_violation',
                  HINT = 'This OTP was already used in another handshake';
    END IF;

    -- Mark as consumed atomically
    UPDATE one_time_prekeys
    SET consumed_at = NOW(),
        consumed_by = p_consumed_by_user_id
    WHERE otp_id = p_otp_id;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- VIEWS
-- ============================================================================

-- View: User session summary (for debugging/admin)
CREATE OR REPLACE VIEW user_sessions_summary AS
SELECT
    u.user_id,
    u.convro_number,
    u.username,
    COUNT(DISTINCT s.session_id) AS active_sessions,
    COUNT(DISTINCT d.device_identity_id) AS active_devices,
    MAX(s.last_activity) AS last_session_activity
FROM users u
LEFT JOIN device_identities d ON u.user_id = d.user_id AND d.is_active = TRUE
LEFT JOIN sessions s ON u.user_id IN (s.initiator_user_id, s.responder_user_id) AND s.is_active = TRUE
GROUP BY u.user_id, u.convro_number, u.username;

-- View: Undelivered messages per user
CREATE OR REPLACE VIEW undelivered_messages_summary AS
SELECT
    u.user_id,
    u.convro_number,
    COUNT(m.message_id) AS undelivered_count,
    MIN(m.created_at) AS oldest_undelivered,
    MAX(m.created_at) AS newest_undelivered
FROM users u
LEFT JOIN messages m ON u.user_id = m.to_user_id AND m.delivered_at IS NULL
GROUP BY u.user_id, u.convro_number
HAVING COUNT(m.message_id) > 0;

-- View: Device prekey health check
CREATE OR REPLACE VIEW device_prekey_health AS
SELECT
    d.device_identity_id,
    d.device_name,
    u.convro_number,
    pb.bundle_id IS NOT NULL AS has_signed_prekey,
    pb.expires_at AS spk_expires_at,
    COUNT(otp.otp_id) FILTER (WHERE otp.consumed_at IS NULL) AS available_otps,
    COUNT(otp.otp_id) FILTER (WHERE otp.consumed_at IS NOT NULL) AS consumed_otps
FROM device_identities d
JOIN users u ON d.user_id = u.user_id
LEFT JOIN prekey_bundles pb ON d.device_identity_id = pb.device_identity_id AND pb.is_active = TRUE
LEFT JOIN one_time_prekeys otp ON d.device_identity_id = otp.device_identity_id
WHERE d.is_active = TRUE
GROUP BY d.device_identity_id, d.device_name, u.convro_number, pb.bundle_id, pb.expires_at;

-- ============================================================================
-- INITIAL DATA
-- ============================================================================

-- Reserved Convro Numbers (for testing, admin accounts, etc.)
INSERT INTO users (convro_number, username, password_hash, account_status, display_name) VALUES
    ('+9900000000', 'admin', '$argon2id$v=19$m=65536,t=3,p=4$DUMMY_HASH', 'active', 'System Admin')
ON CONFLICT (convro_number) DO NOTHING;

-- ============================================================================
-- PERMISSIONS (for server application user)
-- ============================================================================

-- Create application role (server backend will use this)
DO $$ BEGIN
    CREATE ROLE convro_app WITH LOGIN PASSWORD 'CHANGE_THIS_PASSWORD';
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'Role convro_app already exists';
END $$;

-- Grant necessary permissions
GRANT CONNECT ON DATABASE postgres TO convro_app;
GRANT USAGE ON SCHEMA public TO convro_app;

-- Read/write permissions on tables
GRANT SELECT, INSERT, UPDATE ON users, device_identities, prekey_bundles,
    one_time_prekeys, sessions, messages, contacts, push_tokens, presence,
    message_queue, audit_log TO convro_app;

-- Delete permission only where needed
GRANT DELETE ON messages, message_queue TO convro_app;

-- Sequence permissions (for ID generation)
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO convro_app;

-- View permissions
GRANT SELECT ON user_sessions_summary, undelivered_messages_summary,
    device_prekey_health TO convro_app;

-- Function permissions
GRANT EXECUTE ON FUNCTION cleanup_expired_messages() TO convro_app;
GRANT EXECUTE ON FUNCTION get_available_otp_count(UUID) TO convro_app;
GRANT EXECUTE ON FUNCTION consume_otp(UUID, UUID) TO convro_app;
GRANT EXECUTE ON FUNCTION prevent_encrypted_blob_modification() TO convro_app;

-- ============================================================================
-- END OF SCHEMA
-- ============================================================================

-- Summary stats
DO $$ BEGIN
    RAISE NOTICE 'C6P Protocol database schema created successfully!';
    RAISE NOTICE 'Tables: 11 core tables + 1 audit';
    RAISE NOTICE 'Indexes: Optimized for realtime messaging queries';
    RAISE NOTICE 'Functions: 3 utility functions';
    RAISE NOTICE 'Views: 3 monitoring views';
    RAISE NOTICE '';
    RAISE NOTICE 'Next steps:';
    RAISE NOTICE '1. Change convro_app password: ALTER ROLE convro_app WITH PASSWORD ''your_secure_password'';';
    RAISE NOTICE '2. Configure connection pooling (PgBouncer recommended)';
    RAISE NOTICE '3. Set up backups (pg_dump, continuous archiving)';
    RAISE NOTICE '4. Monitor with pg_stat_statements';
END $$;

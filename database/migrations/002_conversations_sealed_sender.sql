-- Migration: Conversations + Sealed Sender
-- Version: v1.1
-- Date: 2026-01-13
-- Description: Add conversations materialized view and sealed sender table for privacy

-- ============================================================================
-- Part 1: Add privacy_mode to users
-- ============================================================================

ALTER TABLE users ADD COLUMN IF NOT EXISTS privacy_mode VARCHAR(20) DEFAULT 'standard';

COMMENT ON COLUMN users.privacy_mode IS 'Privacy level: standard (visible sender) or sealed (hidden sender)';

-- ============================================================================
-- Part 2: Sealed Sender Messages Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS messages_sealed (
    -- Primary key
    message_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Routing (ONLY recipient visible to server)
    to_user_id UUID NOT NULL REFERENCES users(user_id),

    -- Message type (server only sees "sealed_sender")
    message_type VARCHAR(30) NOT NULL DEFAULT 'sealed_sender',

    -- Encrypted envelope (64KB padded)
    encrypted_envelope BYTEA NOT NULL,

    -- Obfuscated timestamp (rounded to 5min)
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Delivery tracking
    delivered_at TIMESTAMP WITH TIME ZONE,

    -- Status
    delivery_status VARCHAR(20) DEFAULT 'pending',

    -- Expiration
    expires_at TIMESTAMP WITH TIME ZONE DEFAULT (NOW() + INTERVAL '30 days'),

    -- Timestamps
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Constraints
    CHECK (message_type = 'sealed_sender'),
    CHECK (octet_length(encrypted_envelope) = 65536)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_messages_sealed_recipient ON messages_sealed(to_user_id, delivery_status);
CREATE INDEX IF NOT EXISTS idx_messages_sealed_delivery ON messages_sealed(delivery_status, created_at);
CREATE INDEX IF NOT EXISTS idx_messages_sealed_expiration ON messages_sealed(expires_at) WHERE delivery_status = 'delivered';
CREATE INDEX IF NOT EXISTS idx_messages_sealed_pending ON messages_sealed(to_user_id, created_at) WHERE delivery_status = 'pending';

-- Comments
COMMENT ON TABLE messages_sealed IS '⚠️ SEALED SENDER: Sender identity hidden from server';
COMMENT ON COLUMN messages_sealed.encrypted_envelope IS 'Encrypted sender + message (64KB padded)';
COMMENT ON COLUMN messages_sealed.created_at IS 'Rounded to 5min for timing obfuscation';

-- ============================================================================
-- Part 3: Conversations Materialized View
-- ============================================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS user_conversations AS
SELECT
    CASE
        WHEN s.initiator_user_id < s.responder_user_id
        THEN s.initiator_user_id || '_' || s.responder_user_id
        ELSE s.responder_user_id || '_' || s.initiator_user_id
    END as conversation_id,
    u.user_id as owner_user_id,
    CASE
        WHEN s.initiator_user_id = u.user_id
        THEN s.responder_user_id
        ELSE s.initiator_user_id
    END as participant_user_id,
    s.session_id,
    s.created_at as conversation_started_at,
    s.last_activity,
    s.message_count as total_messages,
    lm.message_id as last_message_id,
    lm.message_type as last_message_type,
    lm.created_at as last_message_at,
    COALESCE(unread.count, 0) as unread_count,
    s.is_active
FROM sessions s
CROSS JOIN users u
LEFT JOIN LATERAL (
    SELECT message_id, message_type, created_at
    FROM messages
    WHERE session_id = s.session_id
    ORDER BY created_at DESC
    LIMIT 1
) lm ON TRUE
LEFT JOIN LATERAL (
    SELECT COUNT(*) as count
    FROM messages
    WHERE session_id = s.session_id
    AND to_user_id = u.user_id
    AND delivery_status = 'pending'
) unread ON TRUE
WHERE
    (s.initiator_user_id = u.user_id OR s.responder_user_id = u.user_id)
    AND s.is_active = TRUE;

-- Indexes
CREATE UNIQUE INDEX IF NOT EXISTS idx_conversations_owner_participant
    ON user_conversations(owner_user_id, participant_user_id);
CREATE INDEX IF NOT EXISTS idx_conversations_last_activity
    ON user_conversations(owner_user_id, last_activity DESC);

COMMENT ON MATERIALIZED VIEW user_conversations IS 'User conversation list aggregation';

-- ============================================================================
-- Part 4: Functions
-- ============================================================================

CREATE OR REPLACE FUNCTION cleanup_expired_sealed_messages()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM messages_sealed
    WHERE expires_at < NOW() AND delivery_status = 'delivered';
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION refresh_conversations_materialized_view()
RETURNS TRIGGER AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY user_conversations;
    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING 'Failed to refresh user_conversations: %', SQLERRM;
        RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Part 5: Triggers
-- ============================================================================

CREATE TRIGGER IF NOT EXISTS enforce_sealed_envelope_immutability
BEFORE UPDATE ON messages_sealed
FOR EACH ROW
EXECUTE FUNCTION prevent_encrypted_blob_modification();

CREATE TRIGGER IF NOT EXISTS update_messages_sealed_updated_at
BEFORE UPDATE ON messages_sealed
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER IF NOT EXISTS trigger_refresh_conversations_on_message
AFTER INSERT OR UPDATE ON messages
FOR EACH STATEMENT
EXECUTE FUNCTION refresh_conversations_materialized_view();

-- ============================================================================
-- Part 6: Permissions
-- ============================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON messages_sealed TO convro_app;
GRANT SELECT ON user_conversations TO convro_app;
GRANT EXECUTE ON FUNCTION cleanup_expired_sealed_messages() TO convro_app;
GRANT EXECUTE ON FUNCTION refresh_conversations_materialized_view() TO convro_app;

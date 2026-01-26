-- Migration: Allow handshake messages (variable size, different message_type)
-- Reason: Handshake messages (C6P wire format) are small (<1KB), not 64KB
--         message_type can be 'handshake_offer', 'handshake_accept', 'sealed', etc.

-- Step 1: Drop existing check constraints
ALTER TABLE messages_sealed
DROP CONSTRAINT IF EXISTS messages_sealed_message_type_check;

ALTER TABLE messages_sealed
DROP CONSTRAINT IF EXISTS messages_sealed_check;

ALTER TABLE messages_sealed
DROP CONSTRAINT IF EXISTS messages_sealed_check1;

-- Step 2: Add new constraint (allow any message_type except empty)
ALTER TABLE messages_sealed
ADD CONSTRAINT messages_sealed_message_type_check
CHECK (message_type IS NOT NULL AND length(message_type) > 0);

-- Step 3: No size constraint on encrypted_envelope (allow variable sizes)
-- Handshake messages: ~770 bytes (C6P wire format)
-- Sealed messages: 65536 bytes (64KB padded)

-- Step 4: Update column comment
COMMENT ON COLUMN messages_sealed.encrypted_envelope IS 'Encrypted envelope: 64KB for sealed messages, variable for handshakes';
COMMENT ON COLUMN messages_sealed.message_type IS 'Message type: handshake_offer, handshake_accept, sealed, etc.';

-- Verify the changes
-- SELECT conname, pg_get_constraintdef(oid)
-- FROM pg_constraint
-- WHERE conrelid = 'messages_sealed'::regclass AND contype = 'c';

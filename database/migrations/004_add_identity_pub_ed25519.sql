-- Add identity_pub_ed25519 column to device_identities table
-- This is the Ed25519 public key used for signature verification
ALTER TABLE device_identities
ADD COLUMN identity_pub_ed25519 BYTEA;

-- Update comment for device_id to reflect correct size
COMMENT ON COLUMN device_identities.device_id IS 'Device ID (16 bytes, derived from Ed25519 public key)';

-- Add comment for new column
COMMENT ON COLUMN device_identities.identity_pub_ed25519 IS 'Ed25519 public key for signature verification (32 bytes)';

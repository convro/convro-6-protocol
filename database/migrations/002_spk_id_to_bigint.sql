-- Migration: Change signed_prekey_id from INTEGER (i32) to BIGINT (i64)
-- Reason: iOS C6P protocol uses 8-byte SPK IDs for signature creation
--         Backend must store full 8 bytes to enable signature verification

-- Step 1: Alter the column type
ALTER TABLE prekey_bundles
ALTER COLUMN signed_prekey_id TYPE BIGINT;

-- Step 2: Verify the change
-- SELECT column_name, data_type
-- FROM information_schema.columns
-- WHERE table_name = 'prekey_bundles' AND column_name = 'signed_prekey_id';

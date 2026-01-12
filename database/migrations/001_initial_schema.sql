-- ============================================================================
-- Migration: 001_initial_schema
-- Description: Create initial database schema for C6P Protocol
-- Author: Convro Team
-- Date: 2026-01-12
-- ============================================================================

-- This migration creates the complete database schema including:
-- - User accounts with Convro Numbers
-- - Device identities for E2EE
-- - Prekey infrastructure (signed prekeys + OTPs)
-- - Sessions and messages
-- - Contacts, push tokens, presence
-- - Audit logging

BEGIN;

-- Load main schema
\i ../schema.sql

-- Verify tables exist
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'users') THEN
        RAISE EXCEPTION 'Migration failed: users table not created';
    END IF;

    RAISE NOTICE 'Migration 001_initial_schema completed successfully!';
END $$;

COMMIT;

-- ============================================================================
-- CareerPath Stage 4: Secure Supabase Storage & File Metadata Schema Migration
-- Migration ID: 20261029000001_stage4_storage_schema.sql
-- Description: Creates private storage buckets (resumes, profile-images),
--              the student_files metadata table, foreign keys, and RLS policies.
-- ============================================================================

-- Enable pgcrypto / uuid-ossp for UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ----------------------------------------------------------------------------
-- 1. Create Private Storage Buckets (resumes & profile-images)
-- ----------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'resumes',
    'resumes',
    false,
    5242880, -- 5 MB limit
    ARRAY['application/pdf']::text[]
)
ON CONFLICT (id) DO UPDATE SET
    public = false,
    file_size_limit = 5242880,
    allowed_mime_types = ARRAY['application/pdf']::text[];

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'profile-images',
    'profile-images',
    false,
    2097152, -- 2 MB limit
    ARRAY['image/png', 'image/jpeg']::text[]
)
ON CONFLICT (id) DO UPDATE SET
    public = false,
    file_size_limit = 2097152,
    allowed_mime_types = ARRAY['image/png', 'image/jpeg']::text[];

-- ----------------------------------------------------------------------------
-- 2. Create student_files Metadata Table
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS student_files (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    firebase_uid TEXT NOT NULL REFERENCES student_profiles(firebase_uid) ON DELETE CASCADE,
    bucket_name TEXT NOT NULL,
    storage_path TEXT NOT NULL UNIQUE,
    original_filename TEXT NOT NULL,
    content_type TEXT NOT NULL,
    file_size_bytes BIGINT NOT NULL,
    file_category TEXT NOT NULL CHECK (file_category IN ('resume', 'profile_image')),
    upload_status TEXT NOT NULL DEFAULT 'completed' CHECK (upload_status IN ('pending', 'completed', 'failed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexing for fast query resolution and user isolation
CREATE INDEX IF NOT EXISTS idx_student_files_uid ON student_files(firebase_uid);
CREATE INDEX IF NOT EXISTS idx_student_files_category ON student_files(file_category);
CREATE INDEX IF NOT EXISTS idx_student_files_storage_path ON student_files(storage_path);

-- ----------------------------------------------------------------------------
-- 3. Link Profile Image to student_profiles
-- ----------------------------------------------------------------------------
ALTER TABLE student_profiles 
ADD COLUMN IF NOT EXISTS profile_image_file_id UUID REFERENCES student_files(id) ON DELETE SET NULL;

-- ----------------------------------------------------------------------------
-- 4. Row Level Security (RLS) Configuration
-- ----------------------------------------------------------------------------
ALTER TABLE student_files ENABLE ROW LEVEL SECURITY;

-- Block unauthorized public/anon direct access to metadata
REVOKE ALL ON student_files FROM anon, authenticated;

-- Storage RLS: Ensure storage objects in private buckets cannot be queried by anon
DROP POLICY IF EXISTS "Deny anon access to resumes" ON storage.objects;
CREATE POLICY "Deny anon access to resumes" ON storage.objects
FOR ALL TO anon USING (false);

DROP POLICY IF EXISTS "Deny anon access to profile images" ON storage.objects;
CREATE POLICY "Deny anon access to profile images" ON storage.objects
FOR ALL TO anon USING (false);

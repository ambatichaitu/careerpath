-- ============================================================================
-- CareerPath Stage 3: Initial Database Schema Migration
-- Migration ID: 20261029000000_stage3_initial_schema.sql
-- Description: Creates student profiles, skills, domains, job roles, selections,
--              resource tables, indexes, and enables Row Level Security (RLS).
-- ============================================================================

-- Enable UUID extension if needed
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ----------------------------------------------------------------------------
-- Table 1: student_profiles
-- Maps 1:1 with verified Firebase Authentication UID
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS student_profiles (
    firebase_uid TEXT PRIMARY KEY,
    full_name TEXT NOT NULL,
    email TEXT NOT NULL,
    college_name TEXT DEFAULT '',
    branch TEXT DEFAULT '',
    academic_year TEXT DEFAULT '1',
    graduation_year INTEGER,
    onboarding_completed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_student_profiles_email ON student_profiles(email);

-- ----------------------------------------------------------------------------
-- Table 2: skills
-- Normalized master catalog of technical and essential skills
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS skills (
    skill_id SERIAL PRIMARY KEY,
    skill_name TEXT UNIQUE NOT NULL,
    skill_category TEXT DEFAULT 'Technical',
    description TEXT
);

CREATE INDEX IF NOT EXISTS idx_skills_name ON skills(skill_name);

-- ----------------------------------------------------------------------------
-- Table 3: student_skills
-- Junction table tracking confirmed student skills
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS student_skills (
    firebase_uid TEXT NOT NULL REFERENCES student_profiles(firebase_uid) ON DELETE CASCADE,
    skill_id INTEGER NOT NULL REFERENCES skills(skill_id) ON DELETE CASCADE,
    confirmation_source TEXT NOT NULL DEFAULT 'manual', -- 'manual', 'resume', 'onboarding'
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (firebase_uid, skill_id)
);

CREATE INDEX IF NOT EXISTS idx_student_skills_uid ON student_skills(firebase_uid);
CREATE INDEX IF NOT EXISTS idx_student_skills_skill ON student_skills(skill_id);

-- ----------------------------------------------------------------------------
-- Table 4: career_domains
-- Master catalog of engineering and software career tracks
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS career_domains (
    domain_id SERIAL PRIMARY KEY,
    domain_name TEXT UNIQUE NOT NULL,
    description TEXT
);

CREATE INDEX IF NOT EXISTS idx_career_domains_name ON career_domains(domain_name);

-- ----------------------------------------------------------------------------
-- Table 5: student_interests
-- Junction table tracking multiple career domain interests per student
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS student_interests (
    firebase_uid TEXT NOT NULL REFERENCES student_profiles(firebase_uid) ON DELETE CASCADE,
    domain_id INTEGER NOT NULL REFERENCES career_domains(domain_id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (firebase_uid, domain_id)
);

CREATE INDEX IF NOT EXISTS idx_student_interests_uid ON student_interests(firebase_uid);

-- ----------------------------------------------------------------------------
-- Table 6: job_roles
-- O*NET Career Roles catalog (901 roles)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS job_roles (
    role_id SERIAL PRIMARY KEY,
    onet_code TEXT UNIQUE NOT NULL,
    job_title TEXT NOT NULL,
    description TEXT,
    career_domain TEXT,
    education_requirements TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_job_roles_onet ON job_roles(onet_code);
CREATE INDEX IF NOT EXISTS idx_job_roles_title ON job_roles(job_title);
CREATE INDEX IF NOT EXISTS idx_job_roles_domain ON job_roles(career_domain);

-- ----------------------------------------------------------------------------
-- Table 7: job_role_skills
-- Mapping between job roles and required/in-demand skills with importance weight
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS job_role_skills (
    role_id INTEGER NOT NULL REFERENCES job_roles(role_id) ON DELETE CASCADE,
    skill_id INTEGER NOT NULL REFERENCES skills(skill_id) ON DELETE CASCADE,
    importance_weight NUMERIC(4, 2) DEFAULT 1.00,
    skill_type TEXT DEFAULT 'technical', -- 'technical', 'in_demand', 'essential'
    PRIMARY KEY (role_id, skill_id)
);

CREATE INDEX IF NOT EXISTS idx_job_role_skills_role ON job_role_skills(role_id);
CREATE INDEX IF NOT EXISTS idx_job_role_skills_skill ON job_role_skills(skill_id);

-- ----------------------------------------------------------------------------
-- Table 8: student_career_selections
-- Tracks selected or targeted roles by students
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS student_career_selections (
    selection_id SERIAL PRIMARY KEY,
    firebase_uid TEXT NOT NULL REFERENCES student_profiles(firebase_uid) ON DELETE CASCADE,
    selected_role_id INTEGER NOT NULL REFERENCES job_roles(role_id) ON DELETE CASCADE,
    selected_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_student_selections_uid ON student_career_selections(firebase_uid);

-- ----------------------------------------------------------------------------
-- Additional Resource Tables (Section 7)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS learning_resources (
    resource_id SERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    resource_type TEXT DEFAULT 'course', -- 'course', 'documentation', 'tutorial'
    platform TEXT,
    external_url TEXT,
    skill_id INTEGER REFERENCES skills(skill_id) ON DELETE SET NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS certifications (
    certification_id SERIAL PRIMARY KEY,
    certification_name TEXT NOT NULL,
    issuing_organization TEXT,
    skill_id INTEGER REFERENCES skills(skill_id) ON DELETE SET NULL,
    external_url TEXT,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS internships (
    internship_id SERIAL PRIMARY KEY,
    domain_id INTEGER REFERENCES career_domains(domain_id) ON DELETE SET NULL,
    role_title TEXT NOT NULL,
    source_platform TEXT,
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS interview_questions (
    question_id SERIAL PRIMARY KEY,
    role_id INTEGER REFERENCES job_roles(role_id) ON DELETE CASCADE,
    skill_id INTEGER REFERENCES skills(skill_id) ON DELETE SET NULL,
    question_text TEXT NOT NULL,
    topic TEXT,
    difficulty_level TEXT DEFAULT 'Medium',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- Security: Row Level Security (RLS) Configuration
-- ----------------------------------------------------------------------------
ALTER TABLE student_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE skills ENABLE ROW LEVEL SECURITY;
ALTER TABLE student_skills ENABLE ROW LEVEL SECURITY;
ALTER TABLE career_domains ENABLE ROW LEVEL SECURITY;
ALTER TABLE student_interests ENABLE ROW LEVEL SECURITY;
ALTER TABLE job_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE job_role_skills ENABLE ROW LEVEL SECURITY;
ALTER TABLE student_career_selections ENABLE ROW LEVEL SECURITY;
ALTER TABLE learning_resources ENABLE ROW LEVEL SECURITY;
ALTER TABLE certifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE internships ENABLE ROW LEVEL SECURITY;
ALTER TABLE interview_questions ENABLE ROW LEVEL SECURITY;

-- Block unauthorized public/anon access to student private data
REVOKE ALL ON student_profiles FROM anon, authenticated;
REVOKE ALL ON student_skills FROM anon, authenticated;
REVOKE ALL ON student_interests FROM anon, authenticated;
REVOKE ALL ON student_career_selections FROM anon, authenticated;

-- Allow read-only access to catalog/reference tables for anon and authenticated
GRANT SELECT ON skills TO anon, authenticated;
GRANT SELECT ON career_domains TO anon, authenticated;
GRANT SELECT ON job_roles TO anon, authenticated;
GRANT SELECT ON job_role_skills TO anon, authenticated;
GRANT SELECT ON learning_resources TO anon, authenticated;
GRANT SELECT ON certifications TO anon, authenticated;
GRANT SELECT ON internships TO anon, authenticated;
GRANT SELECT ON interview_questions TO anon, authenticated;

DROP POLICY IF EXISTS "Public read catalog skills" ON skills;
CREATE POLICY "Public read catalog skills" ON skills FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read catalog career_domains" ON career_domains;
CREATE POLICY "Public read catalog career_domains" ON career_domains FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read catalog job_roles" ON job_roles;
CREATE POLICY "Public read catalog job_roles" ON job_roles FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read catalog job_role_skills" ON job_role_skills;
CREATE POLICY "Public read catalog job_role_skills" ON job_role_skills FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read catalog learning_resources" ON learning_resources;
CREATE POLICY "Public read catalog learning_resources" ON learning_resources FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read catalog certifications" ON certifications;
CREATE POLICY "Public read catalog certifications" ON certifications FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read catalog internships" ON internships;
CREATE POLICY "Public read catalog internships" ON internships FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read catalog interview_questions" ON interview_questions;
CREATE POLICY "Public read catalog interview_questions" ON interview_questions FOR SELECT USING (true);

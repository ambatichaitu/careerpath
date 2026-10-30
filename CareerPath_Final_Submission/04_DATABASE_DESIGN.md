# CareerPath – Database Design & Schema Specification (Document D)

## 1. Database Architecture Overview
The database layer is hosted on Supabase PostgreSQL. It is structured into 12 normalized relational tables, supported by foreign keys, check constraints, unique indexes, and Row-Level Security (RLS) policies.

---

## 2. Table Catalog

### 1. `student_profiles`
Main table mapping Firebase user identities to academic attributes.
- `firebase_uid` (VARCHAR(128), PRIMARY KEY) – Unique Firebase user identifier.
- `email` (VARCHAR(255), NOT NULL, UNIQUE) – Student's verified institutional or personal email.
- `full_name` (VARCHAR(255)) – Student's display name.
- `academic_year` (INTEGER, CHECK: 1 <= academic_year <= 4) – Engineering study year.
- `interest_domain` (VARCHAR(100)) – Primary specialization domain.
- `profile_image_file_id` (UUID, REFERENCES student_files(file_id)) – Active profile image pointer.
- `created_at`, `updated_at` (TIMESTAMPTZ) – Audit timestamps.

### 2. `skills`
Master catalog of standardized industry technical competencies.
- `skill_id` (SERIAL, PRIMARY KEY) – Auto-incrementing identifier.
- `skill_name` (VARCHAR(100), UNIQUE, NOT NULL) – Normalized skill name (e.g., "Python", "Docker", "SQL").
- `skill_category` (VARCHAR(50), DEFAULT 'Technical') – Categorization.

### 3. `student_skills`
Junction table tracking verified skills acquired by each student.
- `firebase_uid` (VARCHAR(128), REFERENCES student_profiles(firebase_uid) ON DELETE CASCADE).
- `skill_id` (INTEGER, REFERENCES skills(skill_id) ON DELETE CASCADE).
- `proficiency_level` (VARCHAR(20), DEFAULT 'Intermediate').
- PRIMARY KEY (`firebase_uid`, `skill_id`).

### 4. `career_domains`
Catalog of overarching career domains (e.g., Software Engineering, Data Science, Mechanical Systems, Electronics).
- `domain_id` (SERIAL, PRIMARY KEY).
- `domain_name` (VARCHAR(100), UNIQUE, NOT NULL).

### 5. `student_interests`
Junction table tracking student interest domains.
- `firebase_uid` (VARCHAR(128), REFERENCES student_profiles(firebase_uid) ON DELETE CASCADE).
- `domain_id` (INTEGER, REFERENCES career_domains(domain_id) ON DELETE CASCADE).
- PRIMARY KEY (`firebase_uid`, `domain_id`).

### 6. `job_roles`
Master catalog of 901 career roles extracted from O*NET.
- `role_id` (SERIAL, PRIMARY KEY).
- `onet_code` (VARCHAR(20), UNIQUE, NOT NULL) – O*NET standard code (e.g., "15-1252.00").
- `job_title` (VARCHAR(255), NOT NULL) – Professional title (e.g., "Software Developers").
- `description` (TEXT) – Role overview and core responsibilities.
- `career_domain` (VARCHAR(100)) – Associated RIASEC / engineering domain.
- `education_requirements` (VARCHAR(100)) – Typical entry education.

### 7. `job_role_skills`
Junction table mapping required skills to each career role with weights.
- `role_id` (INTEGER, REFERENCES job_roles(role_id) ON DELETE CASCADE).
- `skill_id` (INTEGER, REFERENCES skills(skill_id) ON DELETE CASCADE).
- `importance_weight` (NUMERIC(3,2), DEFAULT 1.00) – Multiplier (1.25 for in-demand skills).
- `skill_type` (VARCHAR(20), DEFAULT 'technical') – 'technical' or 'in_demand'.
- PRIMARY KEY (`role_id`, `skill_id`).

### 8. `student_career_selections`
Records each student's chosen Target Career Goal.
- `selection_id` (SERIAL, PRIMARY KEY).
- `firebase_uid` (VARCHAR(128), REFERENCES student_profiles(firebase_uid) ON DELETE CASCADE, UNIQUE).
- `role_id` (INTEGER, REFERENCES job_roles(role_id) ON DELETE CASCADE).
- `selected_at` (TIMESTAMPTZ, DEFAULT NOW()).

### 9. `learning_resources`
Curated external educational courses, tutorials, and documentations.
- `resource_id` (SERIAL, PRIMARY KEY).
- `role_id` (INTEGER, REFERENCES job_roles(role_id) ON DELETE CASCADE).
- `title` (VARCHAR(255), NOT NULL) – Course or learning module title.
- `provider` (VARCHAR(100)) – Coursera, edX, Udemy, freeCodeCamp, etc.
- `resource_url` (TEXT, NOT NULL) – Verified outbound deep link.
- `resource_type` (VARCHAR(50)) – Course, Specialization, Documentation.

### 10. `certifications`
Industry-recognized technical certifications.
- `cert_id` (SERIAL, PRIMARY KEY).
- `role_id` (INTEGER, REFERENCES job_roles(role_id) ON DELETE CASCADE).
- `title` (VARCHAR(255), NOT NULL) – Certification name (e.g., "AWS Solutions Architect").
- `issuing_body` (VARCHAR(100)) – AWS, Google Cloud, Microsoft, Cisco, CompTIA.
- `verification_url` (TEXT) – Outbound verification or registration portal.

### 11. `internships`
Internship listings and search platforms.
- `internship_id` (SERIAL, PRIMARY KEY).
- `role_id` (INTEGER, REFERENCES job_roles(role_id) ON DELETE CASCADE).
- `title` (VARCHAR(255), NOT NULL).
- `company` (VARCHAR(150)).
- `location` (VARCHAR(100)).
- `application_url` (TEXT, NOT NULL).

### 12. `interview_questions`
Technical, algorithmic, and domain interview preparation questions.
- `question_id` (SERIAL, PRIMARY KEY).
- `role_id` (INTEGER, REFERENCES job_roles(role_id) ON DELETE CASCADE).
- `question_text` (TEXT, NOT NULL).
- `answer_guideline` (TEXT).
- `difficulty` (VARCHAR(20)) – Beginner, Intermediate, Advanced.

### 13. `student_files`
Secure metadata index for uploaded PDF resumes and profile images.
- `file_id` (UUID, PRIMARY KEY, DEFAULT gen_random_uuid()).
- `firebase_uid` (VARCHAR(128), REFERENCES student_profiles(firebase_uid) ON DELETE CASCADE).
- `bucket_name` (VARCHAR(50), NOT NULL) – Strictly 'resumes' or 'profile-images'.
- `storage_path` (TEXT, NOT NULL) – Isolated path (`{firebase_uid}/{uuid}.{ext}`).
- `original_filename` (VARCHAR(255), NOT NULL).
- `mime_type` (VARCHAR(100), NOT NULL).
- `file_size_bytes` (INTEGER, NOT NULL).
- `uploaded_at` (TIMESTAMPTZ, DEFAULT NOW()).

---

## 3. Row-Level Security (RLS) Policy Architecture
All student-owned tables enforce strict RLS policies ensuring that:
1. Public users have zero read/write access.
2. Authenticated students can only read, update, or delete records where `firebase_uid = auth.uid()`.
3. Backend service-role operations execute administrative tasks while FastAPI rigorously validates token claims before database queries.

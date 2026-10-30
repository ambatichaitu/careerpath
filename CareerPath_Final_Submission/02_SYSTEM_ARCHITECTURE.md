# CareerPath – System Architecture (Document B)

## 1. High-Level Architectural Diagram

```
+---------------------------------------------------------------------------------+
|                                 CLIENT TIER                                     |
|                                                                                 |
|   +------------------------------------+   +--------------------------------+   |
|   |         Android Mobile App         |   |         Web Application        |   |
|   |          (Flutter / Dart)          |   |          (Flutter Web)         |   |
|   +-----------------+------------------+   +---------------+----------------+   |
+---------------------|--------------------------------------|--------------------+
                      |                                      |
                      | 1. ID Token / Bearer Header          |
                      v                                      v
+---------------------------------------------------------------------------------+
|                               AUTHENTICATION TIER                               |
|                                                                                 |
|                        Firebase Authentication Service                          |
|                             (Project: careerpath-26fa0)                         |
|     - Identity Provider (Email / Password)                                      |
|     - Email Verification Token Dispatches                                       |
|     - Cryptographic RS256 JWT ID Token Issuance                                 |
+-------------------------------------+-------------------------------------------+
                                      |
                                      | 2. Validated JWT Header
                                      v
+---------------------------------------------------------------------------------+
|                                 BACKEND TIER                                    |
|                                                                                 |
|                          Python FastAPI Application                             |
|                                                                                 |
|   +-------------------------------------------------------------------------+   |
|   | Security & Gateway Layer (security.py)                                  |   |
|   |   - Firebase Admin SDK Token Verification (auth.verify_id_token)        |   |
|   |   - Strict Student UID Ownership Validation                             |   |
|   +-------------------------------------------------------------------------+   |
|   | Domain Services                                                         |   |
|   |   - RecommendationEngine (recommendation_engine.py): O*NET Matching     |   |
|   |   - StorageService (storage_service.py): PDF / Image Validation         |   |
|   |   - Database Layer (database.py): Supabase PostgreSQL Integration       |   |
|   +-------------------------------------------------------------------------+   |
+---------------------+-------------------------------------+---------------------+
                      |                                     |
                      | 3. Service Role Operations          | 4. 60-Sec Signed URLs
                      v                                     v
+-----------------------------------+ +-------------------------------------------+
|           DATA STORAGE            | |               OBJECT STORAGE              |
|                                   | |                                           |
|       Supabase PostgreSQL         | |             Supabase Storage              |
|   - 12 Relational Tables          | |   - resumes (Private Bucket, 5MB Max)     |
|   - Row-Level Security (RLS)      | |   - profile-images (Private, 2MB Max)     |
|   - O*NET Career & Skill Mappings | |   - PyMuPDF / PIL Sanitization            |
+-----------------------------------+ +-------------------------------------------+
```

---

## 2. Component Descriptions

### A. Frontend Layer (Flutter + Dart)
- Developed using Flutter 3.47.8 and Dart 3.13.7.
- **State & Gatekeeper Architecture:** `AuthGate` listens to Firebase Auth streams and transitions seamlessly across 6 discrete states:
  - *Initializing:* Loading spinner.
  - *Unauthenticated:* `LoginScreen` (Login, Register tab, Password reset modal).
  - *Email Verification Required:* `EmailVerificationScreen` with 60-second cooldown timer.
  - *Profile Onboarding Incomplete:* `OnboardingWizardScreen` (3 steps: Personal details, Year, Domain & Skills, PDF Resume upload).
  - *Completed Profile:* `DashboardScreen` (KPIs, Target Career banner, Role recommendations, Search, Filter chips).
  - *Service Unavailable:* Graceful retry screen with offline notifications.

### B. Authentication Layer (Firebase Authentication)
- Manages user identity for project `careerpath-26fa0`.
- Issues signed JSON Web Tokens (JWT) upon login.
- Handles user registration, email verification enforcement, and password reset flows.

### C. Backend API Layer (FastAPI)
- Modular REST API built with Python 3.12 and FastAPI.
- **Dependency Injection:** Endpoints declare `auth_user: AuthenticatedUser = Depends(get_current_user)`.
- Validates token authenticity using `firebase_admin.auth.verify_id_token(token)`.
- Enforces data isolation: requests modifying student resources must match `auth_user.uid`.
- Fail-safe architecture: unconfigured cloud connections trigger explicit `DatabaseUnavailableError` mapped to HTTP 503 instead of masking errors.

### D. Database Tier (Supabase PostgreSQL)
- Relational schema of 12 tables managing profiles, skills, domain interests, career catalogs, learning resources, and target selections.
- Tables enforce Row-Level Security (RLS) policies as defense-in-depth against unauthorized access.

### E. Private Storage Tier (Supabase Storage)
- Buckets: `resumes` and `profile-images`.
- Strictly private: objects cannot be accessed via public URLs.
- Access granted exclusively via 60-second cryptographic signed URLs generated server-side.
- Pre-upload validation: magic bytes verified with PyMuPDF, image sanitization and EXIF stripping executed with Pillow.

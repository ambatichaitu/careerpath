# CareerPath – Security Architecture & Audit Report (Document G)

## 1. Security Philosophy: Defense-in-Depth
CareerPath follows a zero-trust, multi-layered security architecture designed to prevent unauthorized access, privilege escalation, cross-student information disclosure, and malicious file uploads.

---

## 2. Security Layers Breakdown

### A. Authentication Security
- **Sole Identity Provider:** Firebase Authentication manages identity for project `careerpath-26fa0`.
- **Token Verification:** The FastAPI backend does not trust arbitrary user-supplied identifiers. Protected endpoints require a valid RS256-signed Firebase ID Token passed via the `Authorization: Bearer <token>` header.
- **Claims Inspection:** `get_current_user` in `security.py` decodes the token using the Google-managed public key certificate set, verifying token expiration, audience, issuer, and signature integrity.
- **Invalid Tokens Rejected:** Missing, malformed, expired, or revoked tokens immediately produce HTTP 401 Unauthorized without exposing system internals.

### B. Authorization & Cross-Student Isolation
- **UID Derivation:** The student's `firebase_uid` is derived strictly from the verified JWT payload (`auth_user.uid`).
- **Strict Ownership Checks:** Endpoints reading or mutating student data (profiles, skills, target careers, resumes, profile photos) enforce `firebase_uid == auth_user.uid`.
- **Cross-User Protection:** Student A cannot view, modify, or delete Student B's profile, resume, or career selections. Automated regression tests verify this isolation.

### C. Private Storage & Cryptographic Pre-Signed URLs
- **Private Buckets:** The Supabase Storage buckets `resumes` and `profile-images` are private with zero public read permissions.
- **Short-Lived Signed URLs:** File downloads use server-generated HMAC signed URLs with an aggressive 60-second time-to-live (TTL). Once expired, the URL cannot be reused.
- **Partitioned Object Paths:** All uploaded files are stored under `{firebase_uid}/{uuid}.{ext}`, preventing filename collisions and path traversal attempts.

### D. Multi-Stage File Upload Validation Pipeline
1. *Size Limit Enforcement:*
   - Resumes: Maximum 5 MB (HTTP 413 on violation).
   - Profile Images: Maximum 2 MB (HTTP 413 on violation).
2. *Magic Bytes & Structural Verification:*
   - Resumes: PyMuPDF inspects file headers for valid `%PDF` signatures and validates structural integrity before reading content. Corrupted or executable files masquerading as PDFs are rejected with HTTP 400.
   - Images: Pillow (`PIL`) opens and re-encodes the image stream.
3. *EXIF & Metadata Stripping:*
   - All profile images are re-rendered into clean RGB/RGBA buffers with all embedded EXIF metadata (GPS coordinates, camera identifiers, personal timestamps) stripped out.

### E. Secrets & Credential Protection
- **No Client Secrets:** No database connection strings, Supabase service-role keys, or private API secrets are embedded in the Flutter client, Android resources, or compiled APK.
- **Environment Isolation:** Backend configuration is loaded exclusively from `.env` via `python-dotenv`.
- **Git Protection:** Comprehensive `.gitignore` rules prevent `.env`, service account JSONs, keystores, and credentials from entering version control.
- **Fail-Safe Mode:** If cloud database credentials are missing or invalid, the backend immediately halts and returns HTTP 503 (`DatabaseUnavailableError`) rather than silently falling back to insecure in-memory stores in production.

### F. Android Manifest Hardening
- Only necessary permissions (`INTERNET`, `ACCESS_NETWORK_STATE`) are declared.
- Cleartext release HTTP traffic is prohibited; all network calls utilize TLS encryption.
- Android `<queries>` intent filters strictly limit outbound URL schemes to `https` and `http`.

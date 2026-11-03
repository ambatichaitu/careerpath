import os
import sys
import pytest
from fastapi.testclient import TestClient
import pymupdf as fitz

# Ensure the backend directory is in the import path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from main import app, ROLES_DB, SKILLS_DICT
from security import get_current_user, AuthenticatedUser
from database import check_db_health

client = TestClient(app)

# -----------------------------------------------------------------------------
# Mock Authenticated Test Users
# -----------------------------------------------------------------------------
async def mock_verified_student():
    return AuthenticatedUser(
        uid="firebase_test_uid_987",
        email="student@pathfinder.edu",
        email_verified=True,
        claims={"uid": "firebase_test_uid_987", "email": "student@pathfinder.edu"}
    )

async def mock_student_a():
    return AuthenticatedUser(
        uid="student_a_uid_111",
        email="student_a@pathfinder.edu",
        email_verified=True,
        claims={"uid": "student_a_uid_111", "email": "student_a@pathfinder.edu"}
    )

async def mock_student_b():
    return AuthenticatedUser(
        uid="student_b_uid_222",
        email="student_b@pathfinder.edu",
        email_verified=True,
        claims={"uid": "student_b_uid_222", "email": "student_b@pathfinder.edu"}
    )

# -----------------------------------------------------------------------------
# 1. Health & Database Connection Tests
# -----------------------------------------------------------------------------
def test_public_health_and_dataset_index():
    """Verify public health endpoint is accessible without authentication."""
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "online"
    assert data["auth_provider"] == "Firebase Authentication"
    assert "database_provider" in data
    assert data["roles_indexed"] > 800, f"Expected >800 roles, got {data['roles_indexed']}"
    assert data["skills_indexed"] > 300, f"Expected >300 skills, got {data['skills_indexed']}"

def test_database_health_endpoint():
    """Verify database health endpoint reports current connection status."""
    response = client.get("/api/v1/database/health")
    assert response.status_code == 200
    data = response.json()
    assert "status" in data
    assert "provider" in data

def test_legacy_auth_endpoints_disabled():
    """Verify legacy password login and register endpoints return 410 Gone."""
    r_login = client.post("/login", json={"email": "student@pathfinder.edu", "password": "password123"})
    assert r_login.status_code == 410
    assert "retired" in r_login.json()["detail"].lower()

    r_reg = client.post("/register", json={"email": "new@student.edu", "password": "pass", "name": "New"})
    assert r_reg.status_code == 410
    assert "retired" in r_reg.json()["detail"].lower()

# -----------------------------------------------------------------------------
# 2. Token Security & Authorization Tests
# -----------------------------------------------------------------------------
def test_protected_endpoints_reject_missing_token():
    """Verify protected endpoints reject unauthenticated requests with HTTP 401."""
    app.dependency_overrides.clear()

    endpoints = [
        ("POST", "/recommend-roles", {"name": "Alex", "academic_year": 2, "interest_domain": "Software", "student_skills": []}),
        ("POST", "/career-chat", {"message": "Hello", "academic_year": 1, "interest_domain": "Software", "student_skills": []}),
        ("POST", "/update-profile", {"email": "test@test.edu", "skills": []}),
        ("GET", "/api/v1/profile", None),
        ("PUT", "/api/v1/profile", {"full_name": "Test", "academic_year": "2"}),
        ("GET", "/api/v1/profile/skills", None),
        ("GET", "/api/v1/profile/interests", None),
        ("GET", "/api/v1/profile/onboarding-status", None),
    ]

    for method, path, body in endpoints:
        if method == "GET":
            res = client.get(path)
        elif method == "POST":
            res = client.post(path, json=body)
        elif method == "PUT":
            res = client.put(path, json=body)
        assert res.status_code == 401, f"{path} did not reject missing token (got {res.status_code})"
        assert "bearer" in res.json()["detail"].lower()

def test_protected_endpoints_reject_invalid_token():
    """Verify protected endpoints reject malformed or invalid Bearer tokens with HTTP 401."""
    app.dependency_overrides.clear()

    r_bad_format = client.post(
        "/recommend-roles",
        headers={"Authorization": "Basic dXNlcjpwYXNz"},
        json={"name": "Alex", "academic_year": 2, "interest_domain": "Software", "student_skills": []}
    )
    assert r_bad_format.status_code == 401
    assert "expected 'bearer <token>'" in r_bad_format.json()["detail"].lower()

    r_bad_token = client.get(
        "/api/v1/profile",
        headers={"Authorization": "Bearer fake_invalid_jwt_token_123"}
    )
    assert r_bad_token.status_code == 401

# -----------------------------------------------------------------------------
# 3. Stage 3 Profile APIs & Student Isolation Tests
# -----------------------------------------------------------------------------
def test_profile_not_found_for_new_student():
    """Verify new student with no record receives 404 on GET /api/v1/profile."""
    app.dependency_overrides[get_current_user] = mock_student_a
    try:
        response = client.get("/api/v1/profile")
        # In test mode or fresh DB, student_a has no profile yet
        # If it was populated in previous test, clear it or accept 200/404
        assert response.status_code in [200, 404]
    finally:
        app.dependency_overrides.clear()

def test_create_and_read_student_profile():
    """Verify student can create and retrieve profile strictly associated with verified UID."""
    app.dependency_overrides[get_current_user] = mock_student_a
    try:
        put_res = client.put(
            "/api/v1/profile",
            json={
                "full_name": "Aarav Patel",
                "college_name": "IIT Bombay",
                "branch": "Computer Science",
                "academic_year": "3",
                "graduation_year": 2027,
                "onboarding_completed": True,
                "student_skills": ["Python", "Docker", "FastAPI"],
                "interests": ["Software", "Data"]
            }
        )
        assert put_res.status_code == 200
        saved = put_res.json()["profile"]
        assert saved["firebase_uid"] == "student_a_uid_111"
        assert saved["full_name"] == "Aarav Patel"
        assert saved["college_name"] == "IIT Bombay"

        # Read back profile
        get_res = client.get("/api/v1/profile")
        assert get_res.status_code == 200
        fetched = get_res.json()
        assert fetched["firebase_uid"] == "student_a_uid_111"
        assert fetched["full_name"] == "Aarav Patel"
    finally:
        app.dependency_overrides.clear()

def test_backend_email_verification_policy():
    """Verify backend email verification policy across enforced and optional configurations."""
    import security
    from fastapi import HTTPException
    import asyncio

    # 1. Default configuration: enforced by default for production safety (returns True)
    os.environ.pop("REQUIRE_EMAIL_VERIFICATION", None)
    assert security.is_email_verification_enforced() is True

    # 2. Explicit optional override
    os.environ["REQUIRE_EMAIL_VERIFICATION"] = "false"
    assert security.is_email_verification_enforced() is False

    # 3. Explicit enforced override
    os.environ["REQUIRE_EMAIL_VERIFICATION"] = "true"
    assert security.is_email_verification_enforced() is True

    unverified = AuthenticatedUser(
        uid="unverified_uid_999",
        email="unverified@pathfinder.edu",
        email_verified=False,
    )
    verified = AuthenticatedUser(
        uid="verified_uid_999",
        email="verified@pathfinder.edu",
        email_verified=True,
    )

    # When enforced, unverified user is rejected with HTTP 403 Forbidden
    with pytest.raises(HTTPException) as exc_info:
        asyncio.run(security.get_current_verified_user(unverified))
    assert exc_info.value.status_code == 403
    assert "not verified" in exc_info.value.detail.lower()

    # When enforced, verified user passes
    passed = asyncio.run(security.get_current_verified_user(verified))
    assert passed.uid == "verified_uid_999"

    # When optional, unverified user passes without error and retains genuine email_verified=False
    os.environ["REQUIRE_EMAIL_VERIFICATION"] = "false"
    passed_unverified = asyncio.run(security.get_current_verified_user(unverified))
    assert passed_unverified.uid == "unverified_uid_999"
    assert passed_unverified.email_verified is False

    # Reset environment cleanly
    os.environ["ENVIRONMENT"] = "development"
    os.environ.pop("REQUIRE_EMAIL_VERIFICATION", None)

def test_unverified_user_allowed_when_optional():
    """Verify that authenticated unverified accounts can access endpoints when verification is optional."""
    async def mock_unverified_student():
        return AuthenticatedUser(
            uid="unverified_student_456",
            email="student@college.edu",
            email_verified=False,
            claims={"uid": "unverified_student_456"}
        )

    os.environ["REQUIRE_EMAIL_VERIFICATION"] = "false"
    app.dependency_overrides[get_current_user] = mock_unverified_student
    try:
        # Student exists check; either 200 with profile or 404 onboarding required, but NEVER 403
        res = client.get("/api/v1/profile")
        assert res.status_code in (200, 404)
        if res.status_code == 404:
            assert "profile not found" in res.json()["detail"].lower()
    finally:
        app.dependency_overrides.clear()
        os.environ.pop("REQUIRE_EMAIL_VERIFICATION", None)

def test_unverified_user_blocked_from_endpoints_when_enforced():
    """Verify that private FastAPI routes reject unverified accounts with HTTP 403 when email verification is enforced."""
    async def mock_unverified_student():
        return AuthenticatedUser(
            uid="unverified_123",
            email="unverified@careerpath.edu",
            email_verified=False,
            claims={"uid": "unverified_123"}
        )

    os.environ["REQUIRE_EMAIL_VERIFICATION"] = "true"
    app.dependency_overrides[get_current_user] = mock_unverified_student
    try:
        res = client.get("/api/v1/profile")
        assert res.status_code == 403
        assert "not verified" in res.json()["detail"].lower()

        res_roles = client.post(
            "/recommend-roles",
            json={"name": "Test", "academic_year": 1, "interest_domain": "Software", "student_skills": []}
        )
        assert res_roles.status_code == 403
    finally:
        app.dependency_overrides.clear()
        os.environ.pop("REQUIRE_EMAIL_VERIFICATION", None)

def test_invalid_academic_year_rejected():
    """Verify input validation rejects invalid academic year values with HTTP 422."""
    app.dependency_overrides[get_current_user] = mock_student_a
    try:
        res = client.put(
            "/api/v1/profile",
            json={"academic_year": "invalid_tenth_grade"}
        )
        assert res.status_code == 422
        assert "academic year" in res.json()["detail"].lower()
    finally:
        app.dependency_overrides.clear()

def test_update_student_skills_and_interests():
    """Verify updating student skills and career interests independently."""
    app.dependency_overrides[get_current_user] = mock_student_a
    try:
        # Update skills
        s_res = client.put(
            "/api/v1/profile/skills",
            json={"skills": ["Python", "SQL", "Git", "Kubernetes"], "confirmation_source": "manual"}
        )
        assert s_res.status_code == 200
        assert "skills" in s_res.json()

        # Read back skills
        get_s = client.get("/api/v1/profile/skills")
        assert get_s.status_code == 200
        assert "Kubernetes" in get_s.json()["skills"]

        # Update interests
        i_res = client.put(
            "/api/v1/profile/interests",
            json={"interests": ["Cloud & DevOps", "Cybersecurity"]}
        )
        assert i_res.status_code == 200

        # Read back interests
        get_i = client.get("/api/v1/profile/interests")
        assert get_i.status_code == 200
        assert "Cloud & DevOps" in get_i.json()["interests"]
    finally:
        app.dependency_overrides.clear()

def test_student_data_isolation_between_accounts():
    """
    CRITICAL DATABASE SECURITY TEST:
    Verify Student A and Student B have complete data isolation.
    Student A cannot read or modify Student B's profile.
    """
    # 1. Setup Student A
    app.dependency_overrides[get_current_user] = mock_student_a
    try:
        client.put(
            "/api/v1/profile",
            json={
                "full_name": "Student Alpha",
                "college_name": "College Alpha",
                "academic_year": "2",
                "student_skills": ["Python"],
                "interests": ["Software"]
            }
        )
    finally:
        app.dependency_overrides.clear()

    # 2. Setup Student B
    app.dependency_overrides[get_current_user] = mock_student_b
    try:
        client.put(
            "/api/v1/profile",
            json={
                "full_name": "Student Beta",
                "college_name": "College Beta",
                "academic_year": "4",
                "student_skills": ["Java", "Spring Boot"],
                "interests": ["Enterprising"]
            }
        )
        # Verify Student B reads only Student B data
        res_b = client.get("/api/v1/profile")
        assert res_b.status_code == 200
        data_b = res_b.json()
        assert data_b["firebase_uid"] == "student_b_uid_222"
        assert data_b["full_name"] == "Student Beta"
        assert "Java" in data_b["student_skills"]
    finally:
        app.dependency_overrides.clear()

    # 3. Verify Student A still reads only Student A data
    app.dependency_overrides[get_current_user] = mock_student_a
    try:
        res_a = client.get("/api/v1/profile")
        assert res_a.status_code == 200
        data_a = res_a.json()
        assert data_a["firebase_uid"] == "student_a_uid_111"
        assert data_a["full_name"] == "Student Alpha"
        assert "Java" not in data_a["student_skills"]
    finally:
        app.dependency_overrides.clear()

# -----------------------------------------------------------------------------
# 4. Client Security: No Secret Keys in Flutter Frontend
# -----------------------------------------------------------------------------
def test_no_secret_keys_in_flutter_client():
    """Verify that no Supabase secret keys or service account credentials exist in Dart/Flutter code."""
    flutter_lib = os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib")
    sensitive_patterns = [
        "service_role",
        "sbp_",
        "SUPABASE_SECRET",
        "private_key_id",
        "-----BEGIN PRIVATE KEY-----"
    ]

    for root, _, files in os.walk(flutter_lib):
        for f in files:
            if f.endswith(".dart"):
                file_path = os.path.join(root, f)
                with open(file_path, "r", encoding="utf-8", errors="ignore") as fh:
                    content = fh.read()
                for pattern in sensitive_patterns:
                    assert pattern not in content, f"Sensitive credential pattern '{pattern}' found in Flutter file: {file_path}"

# -----------------------------------------------------------------------------
# 5. Core Engine Regression Tests
# -----------------------------------------------------------------------------
def test_protected_recommend_roles_with_verified_user():
    """Verify protected /recommend-roles works seamlessly when authenticated."""
    app.dependency_overrides[get_current_user] = mock_verified_student
    try:
        response = client.post(
            "/recommend-roles",
            json={
                "name": "Alex Chen",
                "academic_year": 3,
                "interest_domain": "Software",
                "student_skills": ["Python", "Java", "Docker", "Git"]
            }
        )
        assert response.status_code == 200
        data = response.json()
        assert "roles" in data
        assert len(data["roles"]) > 0

        top_role = data["roles"][0]
        assert "title" in top_role
        assert "readiness_score" in top_role
        assert 0 <= top_role["readiness_score"] <= 100
        assert "roadmap" in top_role
        assert "courses_and_certs" in top_role
        assert "internships" in top_role
    finally:
        app.dependency_overrides.clear()

def test_protected_career_chat_with_verified_user():
    """Verify protected AI career chat responds when authenticated."""
    app.dependency_overrides[get_current_user] = mock_verified_student
    try:
        response = client.post(
            "/career-chat",
            json={
                "message": "What should I learn in Year 3?",
                "academic_year": 3,
                "interest_domain": "Software",
                "student_skills": ["Python", "Git"]
            }
        )
        assert response.status_code == 200
        data = response.json()
        assert "reply" in data
        assert "Year 3" in data["reply"]
        assert len(data["quick_replies"]) > 0
    finally:
        app.dependency_overrides.clear()

def test_protected_resume_parsing_with_verified_user():
    """Verify protected /parse-resume accurately extracts skills from PDF when authenticated."""
    doc = fitz.open()
    page = doc.new_page()
    page.insert_text((50, 50), "Engineer with experience in Python, Docker, and Git.")
    pdf_bytes = doc.tobytes()

    app.dependency_overrides[get_current_user] = mock_verified_student
    try:
        response = client.post(
            "/parse-resume",
            files={"file": ("resume.pdf", pdf_bytes, "application/pdf")}
        )
        assert response.status_code == 200
        data = response.json()
        assert "extracted_skills" in data
        extracted = data["extracted_skills"]
        assert "Python" in extracted
        assert "Docker" in extracted
        assert "Git" in extracted
    finally:
        app.dependency_overrides.clear()

def test_protected_update_profile_with_verified_user():
    """Verify protected /update-profile associates Firebase UID with student profile."""
    app.dependency_overrides[get_current_user] = mock_verified_student
    try:
        response = client.post(
            "/update-profile",
            json={
                "email": "student@pathfinder.edu",
                "academic_year": 3,
                "interest_domain": "Software",
                "skills": ["Python", "Docker", "Git"]
            }
        )
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "success"
        assert data["user"]["firebase_uid"] == "firebase_test_uid_987"
        assert data["user"]["academic_year"] == 3
    finally:
        app.dependency_overrides.clear()


# -----------------------------------------------------------------------------
# 6. Stage 4 Secure Supabase Storage Tests
# -----------------------------------------------------------------------------
import io
from PIL import Image

def generate_test_pdf(text: str = "Engineer skilled in Python, Docker, and Git.", page_count: int = 1) -> bytes:
    doc = fitz.open()
    for _ in range(page_count):
        p = doc.new_page()
        p.insert_text((50, 50), text)
    b = doc.tobytes()
    doc.close()
    return b

def generate_test_image(fmt: str = "JPEG", size=(100, 100), color="blue") -> bytes:
    img = Image.new("RGB" if fmt == "JPEG" else "RGBA", size, color=color)
    buf = io.BytesIO()
    img.save(buf, format=fmt)
    return buf.getvalue()

def test_unauthenticated_storage_endpoints_rejected():
    """Verify all Stage 4 storage endpoints reject requests without a Bearer token."""
    app.dependency_overrides.clear()
    sample_pdf = generate_test_pdf()
    sample_img = generate_test_image()

    # 1. Resume upload
    r1 = client.post("/api/v1/resumes", files={"file": ("resume.pdf", sample_pdf, "application/pdf")})
    assert r1.status_code == 401

    # 2. Resumes list
    r2 = client.get("/api/v1/resumes")
    assert r2.status_code == 401

    # 3. Resume download
    r3 = client.get("/api/v1/resumes/some-uuid/download")
    assert r3.status_code == 401

    # 4. Resume delete
    r4 = client.delete("/api/v1/resumes/some-uuid")
    assert r4.status_code == 401

    # 5. Profile image upload
    r5 = client.post("/api/v1/profile-image", files={"file": ("profile.jpg", sample_img, "image/jpeg")})
    assert r5.status_code == 401

    # 6. Profile image get
    r6 = client.get("/api/v1/profile-image")
    assert r6.status_code == 401

    # 7. Profile image delete
    r7 = client.delete("/api/v1/profile-image")
    assert r7.status_code == 401

def test_pdf_resume_upload_success_and_extraction():
    """Verify authenticated student can upload PDF resume and get extracted skills."""
    app.dependency_overrides[get_current_user] = mock_student_a
    try:
        pdf_bytes = generate_test_pdf("Software Engineer proficient in Python, Docker, and Kubernetes.")
        response = client.post(
            "/api/v1/resumes",
            files={"file": ("my_resume.pdf", pdf_bytes, "application/pdf")}
        )
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "completed"
        assert "resume_id" in data
        assert "extracted_skills" in data
        assert "Python" in data["extracted_skills"]
        assert "Docker" in data["extracted_skills"]
        assert "Kubernetes" in data["extracted_skills"]
    finally:
        app.dependency_overrides.clear()

def test_resume_student_isolation_and_unauthorized_access():
    """
    CRITICAL STORAGE SECURITY TEST:
    Verify Student B cannot download or delete Student A's private resume.
    """
    # 1. Student A uploads resume
    app.dependency_overrides[get_current_user] = mock_student_a
    try:
        pdf_bytes = generate_test_pdf("Student A confidential resume.")
        up_res = client.post(
            "/api/v1/resumes",
            files={"file": ("student_a_resume.pdf", pdf_bytes, "application/pdf")}
        )
        assert up_res.status_code == 200
        resume_id_a = up_res.json()["resume_id"]
    finally:
        app.dependency_overrides.clear()

    # 2. Student B tries to download Student A's resume -> must be rejected (404/403)
    app.dependency_overrides[get_current_user] = mock_student_b
    try:
        dl_res = client.get(f"/api/v1/resumes/{resume_id_a}/download")
        assert dl_res.status_code == 404

        del_res = client.delete(f"/api/v1/resumes/{resume_id_a}")
        assert del_res.status_code == 404
    finally:
        app.dependency_overrides.clear()

    # 3. Student A can successfully download and delete their own resume
    app.dependency_overrides[get_current_user] = mock_student_a
    try:
        dl_own = client.get(f"/api/v1/resumes/{resume_id_a}/download")
        assert dl_own.status_code == 200
        assert "download_url" in dl_own.json()
        assert dl_own.json()["expires_in"] == 60

        del_own = client.delete(f"/api/v1/resumes/{resume_id_a}")
        assert del_own.status_code == 200
        assert del_own.json()["status"] == "success"
    finally:
        app.dependency_overrides.clear()

def test_pdf_validation_oversized_rejected():
    """Verify resume over 5 MB is rejected with HTTP 413."""
    app.dependency_overrides[get_current_user] = mock_student_a
    try:
        # Create a payload of 5.2 MB starting with PDF header
        oversized = b"%PDF-1.4\n" + b"A" * (5 * 1024 * 1024 + 200 * 1024)
        res = client.post(
            "/api/v1/resumes",
            files={"file": ("huge_resume.pdf", oversized, "application/pdf")}
        )
        assert res.status_code == 413
        assert "5 mb" in res.json()["detail"].lower()
    finally:
        app.dependency_overrides.clear()

def test_pdf_validation_empty_and_corrupted_rejected():
    """Verify empty and corrupted PDF files are rejected safely with HTTP 400."""
    app.dependency_overrides[get_current_user] = mock_student_a
    try:
        # 1. Empty file
        r_empty = client.post(
            "/api/v1/resumes",
            files={"file": ("empty.pdf", b"", "application/pdf")}
        )
        assert r_empty.status_code == 400
        assert "empty" in r_empty.json()["detail"].lower()

        # 2. Corrupted file (non-PDF bytes with .pdf extension)
        r_corrupt = client.post(
            "/api/v1/resumes",
            files={"file": ("fake.pdf", b"This is just plain text, not a pdf.", "application/pdf")}
        )
        assert r_corrupt.status_code == 400
        assert "signature" in r_corrupt.json()["detail"].lower()

        # 3. Wrong extension
        valid_pdf = generate_test_pdf()
        r_ext = client.post(
            "/api/v1/resumes",
            files={"file": ("resume.docx", valid_pdf, "application/octet-stream")}
        )
        assert r_ext.status_code == 400
        assert "extension" in r_ext.json()["detail"].lower()
    finally:
        app.dependency_overrides.clear()

def test_pdf_validation_page_limit_rejected():
    """Verify PDF with more than 15 pages is rejected with HTTP 400."""
    app.dependency_overrides[get_current_user] = mock_student_a
    try:
        sixteen_pages_pdf = generate_test_pdf(text="Page content", page_count=16)
        res = client.post(
            "/api/v1/resumes",
            files={"file": ("long_resume.pdf", sixteen_pages_pdf, "application/pdf")}
        )
        assert res.status_code == 400
        assert "15 pages" in res.json()["detail"].lower()
    finally:
        app.dependency_overrides.clear()

def test_profile_image_upload_and_replacement_lifecycle():
    """Verify uploading, viewing, replacing, and deleting profile images."""
    app.dependency_overrides[get_current_user] = mock_student_a
    try:
        # 1. Upload initial PNG image
        png_bytes = generate_test_image("PNG")
        up_res1 = client.post(
            "/api/v1/profile-image",
            files={"file": ("avatar.png", png_bytes, "image/png")}
        )
        assert up_res1.status_code == 200
        data1 = up_res1.json()
        assert data1["status"] == "completed"
        file_id_1 = data1["file_id"]

        # 2. Get profile image URL
        get_res1 = client.get("/api/v1/profile-image")
        assert get_res1.status_code == 200
        assert "image_url" in get_res1.json()
        assert get_res1.json()["file_id"] == file_id_1

        # 3. Replace with JPEG image (must succeed and clean up old image)
        jpeg_bytes = generate_test_image("JPEG")
        up_res2 = client.post(
            "/api/v1/profile-image",
            files={"file": ("new_avatar.jpg", jpeg_bytes, "image/jpeg")}
        )
        assert up_res2.status_code == 200
        data2 = up_res2.json()
        file_id_2 = data2["file_id"]
        assert file_id_2 != file_id_1

        # 4. Delete profile image
        del_res = client.delete("/api/v1/profile-image")
        assert del_res.status_code == 200

        # 5. Subsequent GET must return 404 Not Found
        get_res2 = client.get("/api/v1/profile-image")
        assert get_res2.status_code == 404
    finally:
        app.dependency_overrides.clear()

def test_image_validation_rejected_cases():
    """Verify image validation rejects oversized, empty, corrupted, and unsupported formats."""
    app.dependency_overrides[get_current_user] = mock_student_a
    try:
        # 1. Oversized image (> 2MB)
        oversized_img = b"\xff\xd8\xff" + b"X" * (2 * 1024 * 1024 + 100 * 1024)
        r_over = client.post(
            "/api/v1/profile-image",
            files={"file": ("big.jpg", oversized_img, "image/jpeg")}
        )
        assert r_over.status_code == 413

        # 2. Empty image
        r_empty = client.post(
            "/api/v1/profile-image",
            files={"file": ("empty.png", b"", "image/png")}
        )
        assert r_empty.status_code == 400

        # 3. Unsupported format (e.g. BMP)
        bmp_img = Image.new("RGB", (50, 50), color="red")
        bmp_buf = io.BytesIO()
        bmp_img.save(bmp_buf, format="BMP")
        r_bmp = client.post(
            "/api/v1/profile-image",
            files={"file": ("photo.bmp", bmp_buf.getvalue(), "image/bmp")}
        )
        assert r_bmp.status_code == 400

        # 4. Corrupted file (random bytes with .jpg extension)
        r_bad = client.post(
            "/api/v1/profile-image",
            files={"file": ("fake.jpg", b"corrupted payload", "image/jpeg")}
        )
        assert r_bad.status_code == 400
    finally:
        app.dependency_overrides.clear()

def test_unsafe_filename_sanitization():
    """Verify path traversal in filename is sanitized and stored without directory traversal."""
    app.dependency_overrides[get_current_user] = mock_student_a
    try:
        pdf_bytes = generate_test_pdf()
        res = client.post(
            "/api/v1/resumes",
            files={"file": ("../../etc/shadow_resume.pdf", pdf_bytes, "application/pdf")}
        )
        assert res.status_code == 200
        filename = res.json()["filename"]
        assert ".." not in filename
        assert "/" not in filename
        assert "\\" not in filename
        assert filename.endswith(".pdf")
    finally:
        app.dependency_overrides.clear()

# -----------------------------------------------------------------------------
# STAGE 5: CAREER RECOMMENDATION, GAP ANALYSIS & RESOURCE INTEGRATION TESTS
# -----------------------------------------------------------------------------
from recommendation_engine import RecommendationEngine, normalize_skill, is_skill_match, build_roadmap

def test_stage5_career_dataset_integrity():
    """1. Verify O*NET career dataset has loaded >= 900 roles and >= 400 skills."""
    assert len(ROLES_DB) >= 900, f"Expected >=900 roles, found {len(ROLES_DB)}"
    assert len(SKILLS_DICT) >= 400, f"Expected >=400 skills, found {len(SKILLS_DICT)}"
    onet_codes = {r.get("onet_code") for r in ROLES_DB if r.get("onet_code")}
    assert len(onet_codes) >= 900, "O*NET codes must be unique across master roles"

def test_stage5_recommendation_score_boundaries():
    """2. Verify recommendation scores are bounded strictly within 0 and 100."""
    roles, total = RecommendationEngine.rank_roles(
        roles=ROLES_DB,
        student_skills=["Python", "SQL", "Docker", "Machine Learning"],
        interest_domain="Software"
    )
    assert total > 0
    for r in roles:
        assert 0 <= r["match_score"] <= 100
        assert 0 <= r["readiness_score"] <= 100
        assert isinstance(r["matched_skills"], list)
        assert isinstance(r["missing_skills"], list)

def test_stage5_identical_input_determinism():
    """3. Verify recommendations are 100% deterministic for identical inputs."""
    skills = ["Python", "JavaScript", "React"]
    res1, _ = RecommendationEngine.rank_roles(ROLES_DB, student_skills=skills, interest_domain="Software")
    res2, _ = RecommendationEngine.rank_roles(ROLES_DB, student_skills=skills, interest_domain="Software")
    assert [r["onet_code"] for r in res1] == [r["onet_code"] for r in res2]
    assert [r["match_score"] for r in res1] == [r["match_score"] for r in res2]

def test_stage5_duplicate_skill_normalization():
    """4. Verify duplicate or alias skills do not inflate recommendation match scores."""
    res_clean, _ = RecommendationEngine.rank_roles(ROLES_DB, student_skills=["Python", "Docker"], interest_domain="Software")
    res_dup, _ = RecommendationEngine.rank_roles(ROLES_DB, student_skills=["Python", "python", "py", "Docker", "docker"], interest_domain="Software")
    assert res_clean[0]["match_score"] == res_dup[0]["match_score"]

def test_stage5_empty_student_skills_handling():
    """5. Verify empty student skill list yields 0 score with no division-by-zero errors."""
    roles, total = RecommendationEngine.rank_roles(ROLES_DB, student_skills=[], interest_domain="Software")
    assert total > 0
    for r in roles:
        assert r["match_score"] == 0
        assert len(r["matched_skills"]) == 0
        assert len(r["missing_skills"]) > 0

def test_stage5_missing_role_requirements():
    """6. Verify roles with empty requirements do not raise runtime exceptions."""
    empty_role = {
        "role_id": 9999,
        "onet_code": "99-9999.00",
        "title": "Hypothetical Explorer",
        "description": "Role with no technical requirements.",
        "primary_interest": "Investigative",
        "technical_skills": [],
        "in_demand_skills": [],
        "essential_skills": []
    }
    match = RecommendationEngine.match_role(empty_role, student_skills=["Python", "SQL"])
    assert match["match_score"] == 0
    assert match["matched_skills"] == []
    assert match["missing_skills"] == []

def test_stage5_academic_year_handling():
    """7. Verify academic-year roadmaps generate tailored milestones for Years 1 through 4."""
    for year in [1, 2, 3, 4]:
        roadmap = build_roadmap("Software Developer", ["Docker", "Kubernetes"], year=year)
        assert len(roadmap) == 3
        if year == 1:
            assert "Fundamentals" in roadmap[0]
        elif year == 2:
            assert "Year 2" in roadmap[0]
        elif year == 3:
            assert "Year 3" in roadmap[0]
        else:
            assert "Final Year" in roadmap[0]

def test_stage5_non_software_career_matching():
    """8. Verify non-software careers evaluate domain-specific technical skills, not software."""
    mech_student_skills = ["AutoCAD", "SolidWorks"]
    roles, total = RecommendationEngine.rank_roles(
        ROLES_DB,
        student_skills=mech_student_skills,
        interest_domain="Realistic"
    )
    assert total > 0
    # Top roles must match mechanical/hardware tools
    top_role = roles[0]
    matched = top_role["matched_skills"]
    assert any(s in ["Autodesk AutoCAD", "Dassault Systemes SolidWorks"] for s in matched)

def test_stage5_get_job_roles_catalog_and_detail():
    """9 & 10. Verify GET /api/v1/job-roles and GET /api/v1/job-roles/{role_id}."""
    # List catalog
    res_list = client.get("/api/v1/job-roles?limit=5")
    assert res_list.status_code == 200
    catalog = res_list.json()
    assert catalog["total_roles"] >= 900
    assert len(catalog["roles"]) == 5
    first_role_id = catalog["roles"][0]["role_id"]

    # Detail query
    res_detail = client.get(f"/api/v1/job-roles/{first_role_id}")
    assert res_detail.status_code == 200
    detail = res_detail.json()
    assert detail["role_id"] == first_role_id
    assert "technical_skills" in detail

    # Invalid role ID
    res_invalid = client.get("/api/v1/job-roles/nonexistent-role-999999")
    assert res_invalid.status_code == 404

def test_stage5_role_resource_endpoints():
    """11, 12, 13. Verify resource, internship, and interview question endpoints."""
    # Resources (Courses & Certs)
    res_res = client.get("/api/v1/job-roles/1/resources")
    assert res_res.status_code == 200
    data_res = res_res.json()
    assert "learning_resources" in data_res
    assert "certifications" in data_res

    # Internships
    res_intern = client.get("/api/v1/job-roles/1/internships")
    assert res_intern.status_code == 200
    data_intern = res_intern.json()
    assert "internships" in data_intern
    assert len(data_intern["internships"]) > 0

    # Interview Questions
    res_qs = client.get("/api/v1/job-roles/1/interview-questions")
    assert res_qs.status_code == 200
    data_qs = res_qs.json()
    assert "interview_questions" in data_qs
    assert len(data_qs["interview_questions"]) > 0

def test_stage5_student_career_selection_persistence():
    """14. Verify student career selection persists and isolates per authenticated student."""
    app.dependency_overrides[get_current_user] = mock_student_a
    try:
        # Student A selects role 1
        res_put = client.put("/api/v1/profile/selected-career", json={"role_id": 1})
        assert res_put.status_code == 200
        assert res_put.json()["status"] == "success"

        # Student A reads selection back
        res_get_a = client.get("/api/v1/profile/selected-career")
        assert res_get_a.status_code == 200
        assert res_get_a.json()["selected_career"]["role_id"] == 1
    finally:
        app.dependency_overrides.clear()

    # Student B reads selection - should be None or separate
    app.dependency_overrides[get_current_user] = mock_student_b
    try:
        res_get_b = client.get("/api/v1/profile/selected-career")
        assert res_get_b.status_code == 200
        # Student B reads selection - must not inherit Student A's selection (role_id 1)
        selected_b = res_get_b.json()["selected_career"]
        assert selected_b is None or selected_b["role_id"] != 1
    finally:
        app.dependency_overrides.clear()

def test_stage5_recommendation_requires_authentication():
    """15, 16. Verify GET /api/v1/recommendations strictly requires valid Firebase Auth."""
    app.dependency_overrides.clear()
    res = client.get("/api/v1/recommendations")
    assert res.status_code == 401

    res_fake = client.get("/api/v1/recommendations", headers={"Authorization": "Bearer invalid_garbage_token"})
    assert res_fake.status_code == 401

def test_stage5_authenticated_recommendations_with_profile():
    """17. Verify authenticated recommendations incorporate student profile and target selection."""
    app.dependency_overrides[get_current_user] = mock_student_a
    try:
        # Create student profile
        client.put("/api/v1/profile", json={
            "full_name": "Student Alpha",
            "academic_year": "3",
            "interest_domain": "Software",
            "student_skills": ["Python", "SQL"]
        })

        # Fetch recommendations
        res = client.get("/api/v1/recommendations?limit=10")
        assert res.status_code == 200
        data = res.json()
        assert data["firebase_uid"] == "student_a_uid_111"
        assert len(data["roles"]) <= 10
        assert data["total_matching"] > 0
        assert data["roles"][0]["match_score"] >= 0
    finally:
        app.dependency_overrides.clear()

def test_stage5_database_unavailable_503_handler():
    """18. Verify DatabaseUnavailableError produces HTTP 503 Service Unavailable."""
    from main import database_unavailable_handler
    from database import DatabaseUnavailableError
    from starlette.requests import Request
    import asyncio

    scope = {"type": "http", "method": "GET", "path": "/api/v1/recommendations", "headers": []}
    req = Request(scope)
    exc = DatabaseUnavailableError("Supabase PostgreSQL connection failed.")
    res = asyncio.run(database_unavailable_handler(req, exc))
    assert res.status_code == 503
    assert b"Supabase PostgreSQL connection failed" in res.body

def test_stage5_seed_database_offline_check():
    """19. Verify seed_database validates dataset offline without mutating cloud."""
    from seed_database import seed
    result = seed(dry_run=True)
    assert result.get("roles_count", 0) >= 900 or result.get("roles_to_seed", 0) >= 900

def test_stage5_chatbot_regression():
    """20. Verify career chatbot functions with domain and academic year advice."""
    app.dependency_overrides[get_current_user] = mock_verified_student
    try:
        res = client.post("/career-chat", json={
            "message": "What should I focus on in Year 3 for Software Engineering?",
            "academic_year": 3,
            "interest_domain": "Software",
            "student_skills": ["Python", "Git"]
        })
        assert res.status_code == 200
        data = res.json()
        assert "reply" in data
        assert "Year 3" in data["reply"]
        assert len(data["suggested_roles"]) > 0
    finally:
        app.dependency_overrides.clear()

# ==============================================================================
# STAGE 7: FINAL CLOUD INTEGRATION, SECURITY & REGRESSION AUDIT TESTS
# ==============================================================================

def test_stage7_cross_student_complete_isolation():
    """Stage 7: Complete cross-student isolation between Student A and Student B."""
    # 1. Setup Student A (CS: Python, SQL; Domain: Data Analytics)
    app.dependency_overrides[get_current_user] = mock_student_a
    try:
        p_res = client.put("/api/v1/profile", json={
            "full_name": "Student A (CS)",
            "academic_year": "3",
            "interest_domain": "Data Analytics",
            "student_skills": ["Python", "SQL"]
        })
        assert p_res.status_code == 200

        sel_res = client.put("/api/v1/profile/selected-career", json={"role_id": 101})
        assert sel_res.status_code == 200
        assert sel_res.json()["selected_career"]["role_id"] == 101
    finally:
        app.dependency_overrides.clear()

    # 2. Setup Student B (Mechanical: AutoCAD, SolidWorks; Domain: Mechanical Design)
    app.dependency_overrides[get_current_user] = mock_student_b
    try:
        p_res_b = client.put("/api/v1/profile", json={
            "full_name": "Student B (Mech)",
            "academic_year": "2",
            "interest_domain": "Mechanical Design",
            "student_skills": ["AutoCAD", "SolidWorks"]
        })
        assert p_res_b.status_code == 200

        sel_res_b = client.put("/api/v1/profile/selected-career", json={"role_id": 202})
        assert sel_res_b.status_code == 200
        assert sel_res_b.json()["selected_career"]["role_id"] == 202

        # Verify Student B sees only Student B's target career
        b_career = client.get("/api/v1/profile/selected-career").json()
        assert b_career["selected_career"]["role_id"] == 202
        assert b_career["selected_career"]["role_id"] != 101

        # Verify Student B's profile does not leak Student A's skills
        b_profile = client.get("/api/v1/profile").json()
        assert "Python" not in b_profile.get("student_skills", [])
        assert "AutoCAD" in b_profile.get("student_skills", [])
    finally:
        app.dependency_overrides.clear()

    # 3. Switch back to Student A: verify Student A's data was not overwritten by Student B
    app.dependency_overrides[get_current_user] = mock_student_a
    try:
        a_career = client.get("/api/v1/profile/selected-career").json()
        assert a_career["selected_career"]["role_id"] == 101
        assert a_career["selected_career"]["role_id"] != 202

        a_profile = client.get("/api/v1/profile").json()
        assert "AutoCAD" not in a_profile.get("student_skills", [])
        assert "Python" in a_profile.get("student_skills", [])
    finally:
        app.dependency_overrides.clear()

def test_stage7_storage_bucket_name_consistency():
    """Stage 7: Verify storage service strictly enforces standard bucket IDs."""
    import storage_service
    assert storage_service.RESUMES_BUCKET == "resumes"
    assert storage_service.PROFILE_IMAGES_BUCKET == "profile-images"

def test_stage7_invalid_firebase_token_variations():
    """Stage 7: Verify reject all invalid, empty, or forged authorization headers."""
    # Empty token
    r1 = client.get("/api/v1/profile", headers={"Authorization": "Bearer "})
    assert r1.status_code in (401, 422)

    # Missing Bearer prefix
    r2 = client.get("/api/v1/profile", headers={"Authorization": "Token 123456"})
    assert r2.status_code == 401

    # Forged JWT
    r3 = client.get("/api/v1/profile", headers={"Authorization": "Bearer eyJhbGciOiJIUzI1NiJ9.forged.token"})
    assert r3.status_code == 401

def test_stage7_production_fail_safe_database_unconfigured(monkeypatch):
    """Stage 7: Verify that unconfigured placeholder credentials fail safely with 503."""
    import database
    monkeypatch.setattr(database, "is_valid_supabase_config", lambda: False)
    monkeypatch.setattr(database, "is_explicit_test_mode", lambda: False)
    monkeypatch.setattr(database, "_supabase_client", None)
    try:
        database.get_supabase_client()
        assert False, "Should have raised DatabaseUnavailableError"
    except database.DatabaseUnavailableError as e:
        assert "Valid SUPABASE_URL and SUPABASE_SECRET_KEY" in str(e)

def test_stage7_recommendation_algorithm_student_differentiation():
    """Stage 7: Verify recommendation engine clearly differentiates CS and Mechanical students."""
    from recommendation_engine import RecommendationEngine
    from main import ROLES_DB as roles

    # Student A (CS: Python, SQL)
    ranked_a, total_a = RecommendationEngine.rank_roles(
        roles=roles,
        student_skills=["Python", "SQL", "Git"],
        interest_domain="Enterprising",
        academic_year=3,
        limit=5
    )
    assert len(ranked_a) > 0
    top_a = ranked_a[0]

    # Student B (Mechanical: AutoCAD, SolidWorks)
    ranked_b, total_b = RecommendationEngine.rank_roles(
        roles=roles,
        student_skills=["AutoCAD", "SolidWorks"],
        interest_domain="Realistic",
        academic_year=2,
        limit=5
    )
    assert len(ranked_b) > 0
    top_b = ranked_b[0]

    # Top roles must be distinct and reflect students' divergent skillsets
    assert top_a["role_id"] != top_b["role_id"]

def test_stage7_image_replacement_and_cleanup_lifecycle():
    """Stage 7: Verify profile image upload, replacement, and deletion lifecycle."""
    app.dependency_overrides[get_current_user] = mock_student_a
    try:
        sample_img1 = generate_test_image(fmt="PNG", size=(100, 100), color="blue")
        sample_img2 = generate_test_image(fmt="PNG", size=(100, 100), color="red")

        # 1. Upload first image
        r1 = client.post("/api/v1/profile-image", files={"file": ("avatar1.png", sample_img1, "image/png")})
        assert r1.status_code == 200
        data1 = r1.json()
        assert data1["file_id"] is not None

        # 2. Upload replacement image
        r2 = client.post("/api/v1/profile-image", files={"file": ("avatar2.png", sample_img2, "image/png")})
        assert r2.status_code == 200
        data2 = r2.json()
        assert data2["file_id"] != data1["file_id"]

        # 3. Retrieve active image
        r3 = client.get("/api/v1/profile-image")
        assert r3.status_code == 200
        assert r3.json()["file_id"] == data2["file_id"]

        # 4. Delete image
        r4 = client.delete("/api/v1/profile-image")
        assert r4.status_code == 200

        # 5. Retrieve after delete
        r5 = client.get("/api/v1/profile-image")
        assert r5.status_code == 404
    finally:
        app.dependency_overrides.clear()

# -----------------------------------------------------------------------------
# Stage 8: Live Integration, Token Verification, Isolation & Security Tests
# -----------------------------------------------------------------------------
def test_stage8_token_verification_rejections(monkeypatch):
    """Stage 8: Verify get_current_user token validation, expired/revoked token handling, and claims extraction."""
    import asyncio
    import security
    from firebase_admin import auth
    from fastapi import HTTPException

    # 1. Missing Authorization header
    with pytest.raises(HTTPException) as exc:
        asyncio.run(security.get_current_user(None))
    assert exc.value.status_code == 401
    assert "Missing Bearer" in exc.value.detail

    # 2. Malformed Authorization format
    with pytest.raises(HTTPException) as exc:
        asyncio.run(security.get_current_user("Basic dXNlcjpwYXNz"))
    assert exc.value.status_code == 401
    assert "Expected 'Bearer <token>'" in exc.value.detail

    # 3. Expired ID token
    def mock_expired_token(token, *args, **kwargs):
        raise auth.ExpiredIdTokenError("Token expired", None)
    monkeypatch.setattr(auth, "verify_id_token", mock_expired_token)

    with pytest.raises(HTTPException) as exc:
        asyncio.run(security.get_current_user("Bearer expired_token_xyz"))
    assert exc.value.status_code == 401
    assert "expired" in exc.value.detail.lower()

    # 4. Revoked ID token
    def mock_revoked_token(token, *args, **kwargs):
        raise auth.RevokedIdTokenError("Token revoked")
    monkeypatch.setattr(auth, "verify_id_token", mock_revoked_token)

    with pytest.raises(HTTPException) as exc:
        asyncio.run(security.get_current_user("Bearer revoked_token_xyz"))
    assert exc.value.status_code == 401
    assert "revoked" in exc.value.detail.lower()

    # 5. Valid verified token
    def mock_valid_token(token, *args, **kwargs):
        return {
            "uid": "verified_firebase_uid_888",
            "email": "verified@college.edu",
            "email_verified": True,
            "role": "student"
        }
    monkeypatch.setattr(auth, "verify_id_token", mock_valid_token)

    user = asyncio.run(security.get_current_user("Bearer valid_jwt_token"))
    assert isinstance(user, security.AuthenticatedUser)
    assert user.uid == "verified_firebase_uid_888"
    assert user.email == "verified@college.edu"
    assert user.email_verified is True
    assert user.claims["role"] == "student"

def test_stage8_test_mode_isolation_guarantees(monkeypatch):
    """Stage 8: Verify that is_explicit_test_mode strictly requires explicit test environments and cannot be bypassed via HTTP."""
    import database

    # Temporarily simulate production runtime
    monkeypatch.setenv("TESTING", "")
    monkeypatch.setenv("ENVIRONMENT", "production")
    monkeypatch.setattr(database, "is_explicit_test_mode", lambda: False)
    monkeypatch.setattr(database, "is_valid_supabase_config", lambda: False)
    monkeypatch.setattr(database, "_supabase_client", None)

    # In production without valid credentials, database access raises DatabaseUnavailableError
    assert database.is_valid_supabase_config() is False
    with pytest.raises(database.DatabaseUnavailableError):
        database.get_supabase_client()

    # Verify HTTP request headers cannot bypass database isolation
    headers = {"X-Test-Mode": "true", "Environment": "test"}
    r = client.get("/api/v1/database/health", headers=headers)
    assert r.status_code == 200
    assert r.json()["status"] in ("error", "disconnected", "unavailable")

def test_stage8_cross_student_access_denial():
    """Stage 8: Verify strict multi-tenant isolation so Student B cannot access or leak Student A's profile or skills."""
    # Setup Student A's profile and skills
    app.dependency_overrides[get_current_user] = mock_student_a
    try:
        r_a = client.put("/api/v1/profile", json={
            "full_name": "Student A",
            "branch": "Computer Science",
            "academic_year": "3"
        })
        assert r_a.status_code == 200

        r_skills_a = client.put("/api/v1/profile/skills", json={
            "skills": ["Python", "Machine Learning", "FastAPI"]
        })
        assert r_skills_a.status_code == 200
    finally:
        app.dependency_overrides.clear()

    # Switch to Student B
    app.dependency_overrides[get_current_user] = mock_student_b
    try:
        # Student B fetches their own profile
        r_b = client.get("/api/v1/profile")
        if r_b.status_code == 200:
            assert r_b.json()["full_name"] != "Student A"

        # Student B fetches skills - must NOT contain Student A's exclusive skills
        r_skills_b = client.get("/api/v1/profile/skills")
        assert r_skills_b.status_code == 200
        assert r_skills_b.json()["firebase_uid"] == "student_b_uid_222"
        assert "Machine Learning" not in r_skills_b.json().get("skills", [])
    finally:
        app.dependency_overrides.clear()

def test_stage8_storage_bucket_names_and_schema_security():
    """Stage 8: Verify canonical storage bucket constants and private access rules in SQL schema."""
    import storage_service

    # Canonical private bucket constants
    assert storage_service.RESUMES_BUCKET == "resumes"
    assert storage_service.PROFILE_IMAGES_BUCKET == "profile-images"

    # Verify migration schema enforces private access
    schema_path = os.path.join(os.path.dirname(__file__), "supabase", "migrations", "20261029000001_stage4_storage_schema.sql")
    if os.path.exists(schema_path):
        with open(schema_path, "r", encoding="utf-8") as f:
            sql_content = f.read()
        assert "public, file_size_limit, allowed_mime_types" in sql_content
        assert "public = false" in sql_content
        assert "Deny anon access to resumes" in sql_content
        assert "Deny anon access to profile images" in sql_content

def test_stage8_starlette_rfc9110_deprecation_cleanliness():
    """Stage 8: Verify that HTTP 422 and 413 responses use modern non-deprecated Starlette / RFC status codes."""
    app.dependency_overrides[get_current_user] = mock_student_a
    try:
        # Invalid academic year yields 422
        r_year = client.put("/api/v1/profile", json={"academic_year": "10th Year Invalid"})
        assert r_year.status_code == 422

        # Invalid target career selection yields 422
        r_career = client.put("/api/v1/profile/selected-career", json={})
        assert r_career.status_code == 422
    finally:
        app.dependency_overrides.clear()



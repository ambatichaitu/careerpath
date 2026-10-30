import os
import json
import re
from typing import List, Optional, Dict, Any
from datetime import datetime, timezone

from fastapi import FastAPI, UploadFile, File, HTTPException, status, Depends
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr

from security import get_current_user, get_current_verified_user, AuthenticatedUser
from database import (
    get_student_profile,
    upsert_student_profile,
    get_student_skills,
    set_student_skills,
    get_student_interests,
    set_student_interests,
    get_onboarding_status,
    check_db_health,
    DatabaseUnavailableError,
    list_student_files,
    get_file_record,
    get_profile_image_file_id,
    get_student_selected_career,
    set_student_selected_career,
    get_learning_resources_for_role,
    get_certifications_for_role,
    get_internships_for_role,
    get_interview_questions_for_role,
)
from storage_service import StorageService, RESUMES_BUCKET, PROFILE_IMAGES_BUCKET
from recommendation_engine import RecommendationEngine, is_skill_match, build_roadmap

# Initialize FastAPI App
app = FastAPI(
    title="CareerPath Recommendation & Guidance API",
    description="Backend API providing Firebase-authenticated access to O*NET role matching, resume parsing, and interactive AI career advising.",
    version="2.4.0"
)

@app.exception_handler(DatabaseUnavailableError)
async def database_unavailable_handler(request, exc):
    return JSONResponse(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        content={"detail": str(exc)}
    )

# ---------------------------------------------------------
# Dynamic CORS Configuration from Environment
# ---------------------------------------------------------
env_origins = os.getenv(
    "ALLOWED_ORIGINS",
    "http://localhost:3000,http://127.0.0.1:8000,http://localhost:8000,https://careerpath-26fa0.web.app,https://careerpath-26fa0.firebaseapp.com"
)
allowed_origins = [orig.strip() for orig in env_origins.split(",") if orig.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------
# Dynamic File Path Resolution
# ---------------------------------------------------------
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

def resolve_file(filename: str) -> str:
    """Finds a file whether running from root, backend, or parent directory."""
    candidates = [
        os.path.join(BASE_DIR, filename),
        os.path.join(BASE_DIR, "backend", filename),
        os.path.join(BASE_DIR, "..", filename),
        os.path.join(BASE_DIR, "..", "backend", filename),
        filename
    ]
    for path in candidates:
        if os.path.exists(path):
            return os.path.abspath(path)
    return os.path.join(BASE_DIR, filename)

ROLES_FILE = resolve_file("master_roles.json")
SKILLS_FILE = resolve_file("skills_dictionary.json")
USERS_DB_FILE = resolve_file("users_db.json")

# Load Master Roles
if os.path.exists(ROLES_FILE):
    with open(ROLES_FILE, "r", encoding="utf-8") as f:
        ROLES_DB = json.load(f)
    for idx, r in enumerate(ROLES_DB):
        r["role_id"] = idx + 1
    print(f"[INFO] Loaded {len(ROLES_DB)} roles from {ROLES_FILE}")
else:
    ROLES_DB = []
    print(f"[WARNING] {ROLES_FILE} not found. Roles DB initialized empty.")

def find_role(role_identifier: Any) -> Optional[Dict[str, Any]]:
    """Locates a role in catalog by integer role_id or string onet_code."""
    if not role_identifier:
        return None
    ident = str(role_identifier).strip().lower()
    for r in ROLES_DB:
        if str(r.get("role_id")) == ident or str(r.get("onet_code", "")).lower() == ident:
            return r
    return None

# Load Skills Dictionary
if os.path.exists(SKILLS_FILE):
    with open(SKILLS_FILE, "r", encoding="utf-8") as f:
        SKILLS_DICT = json.load(f)
    print(f"[INFO] Loaded {len(SKILLS_DICT)} skills from {SKILLS_FILE}")
else:
    SKILLS_DICT = [
        "Python", "Java", "C++", "JavaScript", "TypeScript", "SQL", "Git", "Docker",
        "Kubernetes", "AWS", "Azure", "Machine Learning", "Data Analysis", "React",
        "Flutter", "Node.js", "Linux", "AutoCAD", "SolidWorks", "Power BI", "Cybersecurity"
    ]

# ---------------------------------------------------------
# Profile Storage Helpers (Preserved for non-auth data)
# ---------------------------------------------------------
def load_users() -> Dict[str, Any]:
    if not os.path.exists(USERS_DB_FILE):
        return {}
    try:
        with open(USERS_DB_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        print(f"[ERROR] Failed to load users DB: {e}")
        return {}

def save_users(users: Dict[str, Any]):
    try:
        with open(USERS_DB_FILE, "w", encoding="utf-8") as f:
            json.dump(users, f, indent=2, ensure_ascii=False)
    except Exception as e:
        print(f"[ERROR] Failed to save users DB: {e}")

# ---------------------------------------------------------
# Pydantic Request / Response Models
# ---------------------------------------------------------
class ProfileUpdateRequest(BaseModel):
    email: str
    academic_year: Optional[int] = None
    interest_domain: Optional[str] = None
    skills: Optional[List[str]] = None

class StudentProfileRequest(BaseModel):
    name: str
    academic_year: int
    interest_domain: str
    student_skills: List[str]

class CareerChatRequest(BaseModel):
    message: str
    academic_year: int = 1
    interest_domain: str = "Software"
    student_skills: List[str] = []
    conversation_history: Optional[List[Dict[str, str]]] = []

class ProfileUpdateV1Request(BaseModel):
    full_name: Optional[str] = None
    college_name: Optional[str] = None
    branch: Optional[str] = None
    academic_year: Optional[str] = None
    graduation_year: Optional[int] = None
    onboarding_completed: Optional[bool] = None
    student_skills: Optional[List[str]] = None
    interests: Optional[List[str]] = None

class SkillsUpdateV1Request(BaseModel):
    skills: List[str]
    confirmation_source: Optional[str] = "manual"

class InterestsUpdateV1Request(BaseModel):
    interests: List[str]

class CareerSelectionRequest(BaseModel):
    role_id: Optional[int] = None
    onet_code: Optional[str] = None

VALID_ACADEMIC_YEARS = {
    "1", "2", "3", "4", "5",
    "1st year", "2nd year", "3rd year", "4th year", "final year",
    "graduate", "postgraduate", "pg", "alumni"
}

def validate_academic_year(year_str: Optional[str]):
    if year_str is None:
        return
    clean = str(year_str).strip().lower()
    if clean not in VALID_ACADEMIC_YEARS:
        try:
            val = int(clean)
            if 1 <= val <= 6:
                return
        except ValueError:
            pass
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=f"Invalid academic year '{year_str}'. Allowed values: 1, 2, 3, 4, 1st Year, 2nd Year, 3rd Year, 4th Year, Graduate."
        )

# ---------------------------------------------------------
# 1. PUBLIC HEALTH & METADATA ENDPOINT
# ---------------------------------------------------------
@app.get("/")
def root():
    db_status = check_db_health()
    return {
        "app": "CareerPath Recommendation & Guidance API",
        "version": "2.3.0",
        "status": "online",
        "auth_provider": "Firebase Authentication",
        "database_provider": db_status["provider"],
        "database_connected": db_status["live"],
        "storage_buckets": [RESUMES_BUCKET, PROFILE_IMAGES_BUCKET],
        "roles_indexed": len(ROLES_DB),
        "skills_indexed": len(SKILLS_DICT)
    }

# ---------------------------------------------------------
# 2. RETIRED LEGACY AUTHENTICATION ENDPOINTS (Task 14)
# ---------------------------------------------------------
@app.post("/register", status_code=status.HTTP_410_GONE)
def legacy_register():
    raise HTTPException(
        status_code=status.HTTP_410_GONE,
        detail="Legacy password registration is retired. Please authenticate using Firebase Authentication on the client."
    )

@app.post("/login", status_code=status.HTTP_410_GONE)
def legacy_login():
    raise HTTPException(
        status_code=status.HTTP_410_GONE,
        detail="Legacy password login is retired. Please authenticate using Firebase Authentication on the client."
    )

# ---------------------------------------------------------
# 3. PROTECTED PROFILE MANAGEMENT (Task 13)
# ---------------------------------------------------------
@app.post("/update-profile")
def update_profile(
    req: ProfileUpdateRequest,
    auth_user: AuthenticatedUser = Depends(get_current_verified_user)
):
    email_clean = req.email.strip().lower()
    users = load_users()

    if email_clean not in users:
        users[email_clean] = {
            "email": email_clean,
            "firebase_uid": auth_user.uid,
            "academic_year": req.academic_year or 1,
            "interest_domain": req.interest_domain or "Software",
            "skills": req.skills or [],
            "updated_at": datetime.now(timezone.utc).isoformat()
        }
    else:
        if req.academic_year is not None:
            users[email_clean]["academic_year"] = req.academic_year
        if req.interest_domain is not None:
            users[email_clean]["interest_domain"] = req.interest_domain
        if req.skills is not None:
            users[email_clean]["skills"] = req.skills
        users[email_clean]["firebase_uid"] = auth_user.uid
        users[email_clean]["updated_at"] = datetime.now(timezone.utc).isoformat()

    save_users(users)
    
    # Mirror update to PostgreSQL / Supabase store
    try:
        upsert_student_profile(auth_user.uid, {
            "email": email_clean,
            "academic_year": str(req.academic_year) if req.academic_year is not None else "1",
            "interest_domain": req.interest_domain or "Software",
            "student_skills": req.skills or []
        })
    except Exception as e:
        print(f"[WARNING] Database sync warning: {e}")

    return {
        "status": "success",
        "message": "Profile updated successfully.",
        "user": users[email_clean]
    }

# ---------------------------------------------------------
# STAGE 3: STUDENT PROFILE & DATABASE APIS (Task 5)
# ---------------------------------------------------------
@app.get("/api/v1/database/health")
def database_health():
    """Returns database connection status."""
    return check_db_health()

@app.get("/api/v1/profile")
def get_current_profile(auth_user: AuthenticatedUser = Depends(get_current_verified_user)):
    """Retrieves authenticated student's profile linked to verified Firebase UID."""
    profile = get_student_profile(auth_user.uid)
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Student profile not found. Please complete onboarding."
        )
    return profile

@app.put("/api/v1/profile")
def update_current_profile(
    req: ProfileUpdateV1Request,
    auth_user: AuthenticatedUser = Depends(get_current_verified_user)
):
    """Upserts authenticated student's profile strictly associated with verified Firebase UID."""
    validate_academic_year(req.academic_year)
    update_data = req.model_dump(exclude_unset=True)
    update_data["email"] = auth_user.email
    saved = upsert_student_profile(auth_user.uid, update_data)
    return {
        "status": "success",
        "message": "Student profile updated successfully.",
        "profile": saved
    }

@app.get("/api/v1/profile/skills")
def get_profile_skills(auth_user: AuthenticatedUser = Depends(get_current_verified_user)):
    """Retrieves verified student's technical and confirmed skills."""
    skills = get_student_skills(auth_user.uid)
    return {"firebase_uid": auth_user.uid, "skills": skills}

@app.put("/api/v1/profile/skills")
def update_profile_skills(
    req: SkillsUpdateV1Request,
    auth_user: AuthenticatedUser = Depends(get_current_verified_user)
):
    """Updates confirmed skills for verified student."""
    set_student_skills(auth_user.uid, req.skills, req.confirmation_source or "manual")
    return {
        "status": "success",
        "skills": req.skills
    }

@app.get("/api/v1/profile/interests")
def get_profile_interests(auth_user: AuthenticatedUser = Depends(get_current_verified_user)):
    """Retrieves career domain interests for verified student."""
    interests = get_student_interests(auth_user.uid)
    return {"firebase_uid": auth_user.uid, "interests": interests}

@app.put("/api/v1/profile/interests")
def update_profile_interests(
    req: InterestsUpdateV1Request,
    auth_user: AuthenticatedUser = Depends(get_current_verified_user)
):
    """Updates career domain interests for verified student."""
    set_student_interests(auth_user.uid, req.interests)
    return {
        "status": "success",
        "interests": req.interests
    }

@app.get("/api/v1/profile/onboarding-status")
def get_profile_onboarding_status(auth_user: AuthenticatedUser = Depends(get_current_verified_user)):
    """Checks onboarding completion state for routing decisions."""
    return get_onboarding_status(auth_user.uid)

# ---------------------------------------------------------
# 4. PROTECTED RESUME PARSING (Task 13)
# ---------------------------------------------------------
@app.post("/parse-resume")
async def parse_resume(
    file: UploadFile = File(...),
    auth_user: AuthenticatedUser = Depends(get_current_verified_user)
):
    try:
        import pymupdf as fitz
    except ImportError:
        try:
            import fitz
        except ImportError:
            raise HTTPException(status_code=500, detail="PyMuPDF is not installed on server.")

    pdf_bytes = await file.read()
    try:
        doc = fitz.open(stream=pdf_bytes, filetype="pdf")
        full_text = " ".join([page.get_text("text") for page in doc]).lower()
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Could not read PDF resume: {str(e)}")

    extracted = [skill for skill in SKILLS_DICT if skill.lower() in full_text]
    return {"extracted_skills": extracted[:25]}

# ---------------------------------------------------------
# STAGE 4: SECURE STORAGE & RESUME/IMAGE APIS (Tasks 7, 8, 9)
# ---------------------------------------------------------
@app.post("/api/v1/resumes")
async def upload_student_resume(
    file: UploadFile = File(...),
    auth_user: AuthenticatedUser = Depends(get_current_verified_user)
):
    """
    Stage 4: Uploads PDF resume to private Supabase Storage, saves metadata,
    and runs PyMuPDF skill extraction engine.
    """
    pdf_bytes = await file.read()
    orig_name = file.filename or "resume.pdf"
    
    # 1. Validate and save to Supabase Storage + PostgreSQL metadata with rollback
    record = StorageService.save_student_resume(
        firebase_uid=auth_user.uid,
        content=pdf_bytes,
        original_filename=orig_name
    )

    # 2. Extract skills from validated PDF bytes
    try:
        import pymupdf as fitz
        doc = fitz.open(stream=pdf_bytes, filetype="pdf")
        full_text = " ".join([page.get_text("text") for page in doc]).lower()
        doc.close()
        extracted = [skill for skill in SKILLS_DICT if skill.lower() in full_text]
    except Exception as e:
        print(f"[WARNING] PyMuPDF skill extraction notice: {e}")
        extracted = []

    return {
        "status": "completed",
        "message": "Resume uploaded and analyzed successfully.",
        "resume_id": record["id"],
        "filename": record["original_filename"],
        "file_size_bytes": record["file_size_bytes"],
        "extracted_skills": extracted[:25],
        "suggested_skills": extracted[:25]
    }

@app.get("/api/v1/resumes")
def list_resumes(auth_user: AuthenticatedUser = Depends(get_current_verified_user)):
    """Lists private resumes uploaded by the authenticated student."""
    files = list_student_files(auth_user.uid, file_category="resume")
    return {
        "firebase_uid": auth_user.uid,
        "resumes": [
            {
                "id": f["id"],
                "filename": f["original_filename"],
                "file_size_bytes": f["file_size_bytes"],
                "content_type": f["content_type"],
                "created_at": f["created_at"]
            }
            for f in files
        ]
    }

@app.get("/api/v1/resumes/{resume_id}/download")
def download_resume(
    resume_id: str,
    auth_user: AuthenticatedUser = Depends(get_current_verified_user)
):
    """Generates a short-lived signed access URL (60 seconds) after verifying ownership."""
    record = get_file_record(resume_id, auth_user.uid)
    if not record or record.get("file_category") != "resume":
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Resume document not found or unauthorized access."
        )

    signed_url = StorageService.get_signed_url(
        bucket=RESUMES_BUCKET,
        storage_path=record["storage_path"],
        expires_in=60
    )
    return {
        "resume_id": resume_id,
        "download_url": signed_url,
        "filename": record["original_filename"],
        "expires_in": 60
    }

@app.delete("/api/v1/resumes/{resume_id}")
def delete_resume(
    resume_id: str,
    auth_user: AuthenticatedUser = Depends(get_current_verified_user)
):
    """Deletes resume document from private storage and PostgreSQL metadata."""
    StorageService.delete_resume_file(resume_id, auth_user.uid)
    return {
        "status": "success",
        "message": "Resume deleted successfully."
    }

@app.post("/api/v1/profile-image")
async def upload_profile_image(
    file: UploadFile = File(...),
    auth_user: AuthenticatedUser = Depends(get_current_verified_user)
):
    """
    Stage 4: Validates, strips EXIF metadata, re-encodes, and saves profile image
    to private Supabase Storage, linking to the student's profile.
    """
    image_bytes = await file.read()
    orig_name = file.filename or "profile.jpg"

    record = StorageService.save_student_profile_image(
        firebase_uid=auth_user.uid,
        content=image_bytes,
        original_filename=orig_name
    )

    return {
        "status": "completed",
        "message": "Profile picture updated successfully.",
        "file_id": record["id"],
        "filename": record["original_filename"],
        "file_size_bytes": record["file_size_bytes"]
    }

@app.get("/api/v1/profile-image")
def get_current_profile_image(auth_user: AuthenticatedUser = Depends(get_current_verified_user)):
    """Retrieves short-lived signed URL for authenticated student's profile picture."""
    file_id = get_profile_image_file_id(auth_user.uid)
    if not file_id:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No profile picture currently set."
        )

    record = get_file_record(file_id, auth_user.uid)
    if not record or record.get("file_category") != "profile_image":
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile picture record not found."
        )

    signed_url = StorageService.get_signed_url(
        bucket=PROFILE_IMAGES_BUCKET,
        storage_path=record["storage_path"],
        expires_in=60
    )
    return {
        "file_id": file_id,
        "image_url": signed_url,
        "expires_in": 60
    }

@app.delete("/api/v1/profile-image")
def delete_profile_image(auth_user: AuthenticatedUser = Depends(get_current_verified_user)):
    """Removes profile picture from private storage and resets profile pointer."""
    StorageService.delete_profile_image_file(auth_user.uid)
    return {
        "status": "success",
        "message": "Profile picture removed successfully."
    }

# ---------------------------------------------------------
# STAGE 5: CAREER RECOMMENDATION, GAP ANALYSIS & SELECTION APIS
# ---------------------------------------------------------
@app.get("/api/v1/recommendations")
def get_career_recommendations(
    domain: Optional[str] = None,
    search: Optional[str] = None,
    limit: int = 30,
    offset: int = 0,
    auth_user: AuthenticatedUser = Depends(get_current_verified_user)
):
    """
    Stage 5: Deterministic, explainable career role recommendations
    connected to authenticated student's persistent profile, confirmed skills, and interests.
    """
    profile = get_student_profile(auth_user.uid)
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Student profile not found. Please complete onboarding first."
        )

    # Authoritative student skills & interests from Supabase
    skills = get_student_skills(auth_user.uid)
    if not skills:
        skills = profile.get("student_skills", []) or profile.get("skills", [])

    interests = get_student_interests(auth_user.uid)
    if not interests:
        interests = profile.get("interests", [])

    raw_year = profile.get("academic_year", 1)
    try:
        academic_year = int(str(raw_year).split()[0])
    except (ValueError, IndexError):
        academic_year = 1

    # Effective search domain
    effective_domain = domain
    if not effective_domain and interests:
        effective_domain = interests[0]
    elif not effective_domain:
        effective_domain = profile.get("interest_domain")

    paged_roles, total_matching = RecommendationEngine.rank_roles(
        roles=ROLES_DB,
        student_skills=skills,
        interest_domain=effective_domain,
        search_query=search,
        academic_year=academic_year,
        limit=limit,
        offset=offset
    )

    # Include student's targeted career selection if set
    selected = get_student_selected_career(auth_user.uid)
    selected_summary = None
    if selected:
        s_role_id = selected.get("selected_role_id") or selected.get("role_id")
        matched_target = find_role(s_role_id)
        if matched_target:
            selected_summary = RecommendationEngine.match_role(
                role=matched_target,
                student_skills=skills,
                academic_year=academic_year,
                role_index=matched_target.get("role_id")
            )

    return {
        "firebase_uid": auth_user.uid,
        "total_roles": len(ROLES_DB),
        "total_matching": total_matching,
        "limit": limit,
        "offset": offset,
        "selected_career": selected_summary,
        "student_skills_count": len(skills),
        "roles": paged_roles
    }

@app.get("/api/v1/job-roles")
def list_job_roles(
    domain: Optional[str] = None,
    search: Optional[str] = None,
    limit: int = 50,
    offset: int = 0
):
    """Browses the master catalog of 901 O*NET career roles."""
    filtered = []
    domain_clean = (domain or "").strip().lower()
    search_clean = (search or "").strip().lower()

    for r in ROLES_DB:
        if domain_clean and domain_clean != "all":
            if (
                domain_clean not in r.get("primary_interest", "").lower()
                and domain_clean not in r.get("title", "").lower()
            ):
                continue
        if search_clean:
            if (
                search_clean not in r.get("title", "").lower()
                and search_clean not in r.get("description", "").lower()
            ):
                continue
        filtered.append({
            "role_id": r.get("role_id"),
            "onet_code": r.get("onet_code"),
            "title": r.get("title"),
            "domain": r.get("primary_interest"),
            "typical_education": r.get("typical_education"),
            "technical_skills_count": len(r.get("technical_skills", [])),
            "in_demand_skills_count": len(r.get("in_demand_skills", []))
        })

    total_count = len(filtered)
    return {
        "total_roles": len(ROLES_DB),
        "total_matching": total_count,
        "limit": limit,
        "offset": offset,
        "roles": filtered[offset:offset + limit]
    }

@app.get("/api/v1/job-roles/{role_id}")
def get_job_role_detail(role_id: str):
    """Retrieves full details for a specific career role."""
    r = find_role(role_id)
    if not r:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Job role '{role_id}' not found in catalog."
        )
    return {
        "role_id": r.get("role_id"),
        "onet_code": r.get("onet_code"),
        "title": r.get("title"),
        "description": r.get("description"),
        "domain": r.get("primary_interest"),
        "typical_education": r.get("typical_education"),
        "technical_skills": r.get("technical_skills", []),
        "in_demand_skills": r.get("in_demand_skills", []),
        "essential_skills": r.get("essential_skills", [])
    }

@app.get("/api/v1/job-roles/{role_id}/skills")
def get_role_skill_gap_analysis(
    role_id: str,
    auth_user: AuthenticatedUser = Depends(get_current_verified_user)
):
    """Performs explainable skill gap analysis between authenticated student and target role."""
    r = find_role(role_id)
    if not r:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Job role '{role_id}' not found in catalog."
        )

    profile = get_student_profile(auth_user.uid)
    skills = get_student_skills(auth_user.uid)
    if not skills and profile:
        skills = profile.get("student_skills", []) or profile.get("skills", [])

    raw_year = profile.get("academic_year", 1) if profile else 1
    try:
        academic_year = int(str(raw_year).split()[0])
    except (ValueError, IndexError):
        academic_year = 1

    match_data = RecommendationEngine.match_role(
        role=r,
        student_skills=skills,
        academic_year=academic_year,
        role_index=r.get("role_id")
    )

    return {
        "firebase_uid": auth_user.uid,
        "role_id": match_data["role_id"],
        "onet_code": match_data["onet_code"],
        "title": match_data["title"],
        "match_score": match_data["match_score"],
        "matched_skills": match_data["matched_skills"],
        "missing_skills": match_data["missing_skills"],
        "foundational_skills": match_data["foundational_skills"],
        "recommended_next_skills": match_data["recommended_next_skills"],
        "in_demand_skills": match_data["in_demand_skills"],
        "explanation": match_data["explanation"]
    }

@app.get("/api/v1/job-roles/{role_id}/resources")
def get_role_resources(role_id: str):
    """Retrieves learning resources and professional certifications for a role."""
    r = find_role(role_id)
    if not r:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Job role '{role_id}' not found."
        )
    courses = get_learning_resources_for_role(r.get("role_id"), r.get("primary_interest"))
    certs = get_certifications_for_role(r.get("role_id"), r.get("primary_interest"))
    return {
        "role_id": r.get("role_id"),
        "onet_code": r.get("onet_code"),
        "title": r.get("title"),
        "learning_resources": courses,
        "certifications": certs
    }

@app.get("/api/v1/job-roles/{role_id}/internships")
def get_role_internships(role_id: str):
    """Retrieves verified internship search streams and curated opportunities."""
    r = find_role(role_id)
    if not r:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Job role '{role_id}' not found."
        )
    internships = get_internships_for_role(r.get("title", "Engineering"), r.get("primary_interest"))
    return {
        "role_id": r.get("role_id"),
        "onet_code": r.get("onet_code"),
        "title": r.get("title"),
        "internships": internships
    }

@app.get("/api/v1/job-roles/{role_id}/interview-questions")
def get_role_interview_questions(role_id: str):
    """Retrieves categorized interview questions for role preparation."""
    r = find_role(role_id)
    if not r:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Job role '{role_id}' not found."
        )
    questions = get_interview_questions_for_role(r.get("role_id"), r.get("title", "Engineer"))
    return {
        "role_id": r.get("role_id"),
        "onet_code": r.get("onet_code"),
        "title": r.get("title"),
        "interview_questions": questions
    }

@app.put("/api/v1/profile/selected-career")
def select_target_career(
    req: CareerSelectionRequest,
    auth_user: AuthenticatedUser = Depends(get_current_verified_user)
):
    """Saves student's chosen career path target in Supabase PostgreSQL."""
    identifier = str(req.role_id) if req.role_id is not None else (req.onet_code or "")
    if not identifier:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="Either role_id or onet_code must be provided."
        )

    r = find_role(identifier)
    if not r:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Selected career role '{identifier}' does not exist in catalog."
        )

    target_role_id = r.get("role_id", 1)
    saved = set_student_selected_career(auth_user.uid, target_role_id)
    return {
        "status": "success",
        "message": f"Successfully selected target career: {r.get('title')}",
        "selected_career": {
            "role_id": target_role_id,
            "onet_code": r.get("onet_code"),
            "title": r.get("title"),
            "domain": r.get("primary_interest"),
            "selected_at": saved.get("selected_at")
        }
    }

@app.get("/api/v1/profile/selected-career")
def get_selected_target_career(
    auth_user: AuthenticatedUser = Depends(get_current_verified_user)
):
    """Retrieves the target career path selected by the authenticated student."""
    selection = get_student_selected_career(auth_user.uid)
    if not selection:
        return {
            "firebase_uid": auth_user.uid,
            "selected_career": None
        }

    role_id = selection.get("selected_role_id") or selection.get("role_id")
    r = find_role(str(role_id)) if role_id else None
    return {
        "firebase_uid": auth_user.uid,
        "selected_career": {
            "role_id": role_id,
            "onet_code": r.get("onet_code") if r else "N/A",
            "title": r.get("title") if r else "Selected Role",
            "domain": r.get("primary_interest") if r else "",
            "selected_at": selection.get("selected_at")
        } if r else selection
    }

# ---------------------------------------------------------
# BACKWARDS-COMPATIBLE ENDPOINT
# ---------------------------------------------------------
@app.post("/recommend-roles")
async def recommend_roles(
    profile: StudentProfileRequest,
    auth_user: AuthenticatedUser = Depends(get_current_verified_user)
):
    """Backwards-compatible recommendation endpoint powered by RecommendationEngine."""
    paged_roles, _ = RecommendationEngine.rank_roles(
        roles=ROLES_DB,
        student_skills=profile.student_skills,
        interest_domain=profile.interest_domain,
        academic_year=profile.academic_year,
        limit=30,
        offset=0
    )
    return {"roles": paged_roles}

# ---------------------------------------------------------
# 6. PROTECTED AI CAREER GUIDANCE CHATBOT (Task 13)
# ---------------------------------------------------------
@app.post("/career-chat")
async def career_chat(
    req: CareerChatRequest,
    auth_user: AuthenticatedUser = Depends(get_current_verified_user)
):
    user_msg = req.message.strip()
    msg_lower = user_msg.lower()
    student_skills = req.student_skills or []
    student_set = {s.lower() for s in student_skills}
    year = req.academic_year
    domain = req.interest_domain

    matching_roles = []
    for r in ROLES_DB:
        title_low = r.get("title", "").lower()
        interest_low = r.get("primary_interest", "").lower()
        tech_skills = [s.lower() for s in r.get("technical_skills", [])]

        overlap = [s for s in tech_skills if s in student_set]
        readiness = round((len(overlap) / max(len(tech_skills), 1)) * 100)

        is_relevant = (
            any(w in title_low for w in msg_lower.split() if len(w) > 3)
            or domain.lower() in interest_low
            or domain.lower() in title_low
            or any(sk.lower() in msg_lower for sk in student_skills)
        )
        if is_relevant:
            missing = [s for s in r.get("technical_skills", []) if s.lower() not in student_set]
            matching_roles.append({
                "title": r.get("title"),
                "readiness_score": readiness,
                "matched_skills": [s for s in r.get("technical_skills", []) if s.lower() in student_set],
                "missing_skills": missing[:4],
                "in_demand_skills": r.get("in_demand_skills", [])[:3],
                "typical_education": r.get("typical_education", "Bachelor's Degree")
            })

    matching_roles.sort(key=lambda x: x["readiness_score"], reverse=True)
    top_suggestions = matching_roles[:3]

    reply_lines = []
    quick_replies = []

    if any(q in msg_lower for q in ["year 1", "year 2", "year 3", "year 4", "first year", "second year", "third year", "final year"]):
        target_year = year
        if "year 1" in msg_lower or "first year" in msg_lower:
            target_year = 1
        elif "year 2" in msg_lower or "second year" in msg_lower:
            target_year = 2
        elif "year 3" in msg_lower or "third year" in msg_lower:
            target_year = 3
        elif "year 4" in msg_lower or "final year" in msg_lower:
            target_year = 4

        reply_lines.append(f"🎓 **Strategic Roadmap for Year {target_year} ({domain} Track)**\n")
        if target_year == 1:
            reply_lines.append(
                "As a **1st Year Student**, your focus is building foundational programming and curiosity:\n"
                "• **Master 1 Core Language**: Deep dive into Python or Java/C++.\n"
                "• **Data Structures & Algorithms (DSA)**: Arrays, Linked Lists, Stacks, Queues.\n"
                "• **Version Control**: Set up Git and GitHub; push small labs and assignments.\n"
                "• **Exploration**: Participate in college hackathons and beginner tech communities."
            )
            quick_replies = ["Which starter projects should I build?", "Which language is best for Year 1?", "How to get started with Git?"]
        elif target_year == 2:
            reply_lines.append(
                "As a **2nd Year Student**, your focus is building software systems:\n"
                "• **CS Fundamentals**: OOP, Relational Databases (SQL), Operating Systems.\n"
                "• **Applied Frameworks**: Explore FastAPI/Django for Python or Spring Boot for Java.\n"
                "• **Portfolio Projects**: Build 2 full-stack projects and deploy them live.\n"
                "• **Resume Groundwork**: Document architecture diagrams and GitHub READMEs."
            )
            quick_replies = ["Which jobs fit Java & Python?", "Top project ideas for Year 2", "How do I prepare for internships?"]
        elif target_year == 3:
            reply_lines.append(
                "As a **3rd Year Student**, your focus is **Internship Readiness & Skill Gap Closure**:\n"
                "• **Close Skill Gaps**: Focus on Docker, Cloud Deployment (AWS/GCP), and CI/CD.\n"
                "• **DSA Grinding**: Practice LeetCode medium problems on Trees, Graphs, and DP.\n"
                "• **Internship Applications**: Apply to 30+ openings on LinkedIn, Wellfound, campus drives.\n"
                "• **Certifications**: Complete an entry-level cloud or specialized credential."
            )
            quick_replies = ["How do I get my first internship?", "What certifications boost my resume?", "Review my readiness score"]
        else:
            reply_lines.append(
                "As a **Final Year Student**, you are in placement and conversion mode:\n"
                "• **Interview Drills**: Master system design tradeoffs, DB indexing, microservices.\n"
                "• **Behavioral Mastery (STAR)**: Prepare 4 compelling stories of challenges and leadership.\n"
                "• **ATS Optimization**: Tailor resume keywords directly against job descriptions.\n"
                "• **Capstones**: Polish your capstone project with live demos and metrics."
            )
            quick_replies = ["How to clear behavioral interviews?", "High-paying tech roles right now", "ATS resume tips"]
    else:
        known_str = ", ".join(student_skills) if student_skills else "foundational tools"
        reply_lines.append(f"👋 **Hi {domain} Explorer!** (Year {year} Student)\n")
        reply_lines.append(
            f"I evaluated your profile against our **O*NET Career Database**. Current recorded skills: **{known_str}**.\n\n"
            "Key recommendations:\n"
            f"• **Target Role Fit**: Your strongest alignment is in **{domain} Engineering**.\n"
            "• **Skill Acceleration**: Adding **Docker**, **Cloud Services**, and **System Design** yields the highest leap in interview callbacks.\n"
            f"• **Milestone**: Maintain at least 2 active, well-documented projects on GitHub."
        )
        quick_replies = [f"What should I learn in Year {year}?", "Which jobs fit Java & Python?", "How do I boost my readiness score?"]

    return {
        "reply": "\n".join(reply_lines),
        "suggested_roles": top_suggestions,
        "quick_replies": quick_replies,
        "student_profile": {
            "year": year,
            "domain": domain,
            "skills_count": len(student_skills)
        }
    }

if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", "8000"))
    reload = os.getenv("ENVIRONMENT", "development").lower() != "production"
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=reload)

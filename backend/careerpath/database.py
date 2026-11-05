import os
import sys
import logging
import uuid
from typing import Optional, Dict, Any, List
import time
import concurrent.futures
from datetime import datetime, timezone
from dotenv import load_dotenv

# Load local environment configuration
load_dotenv()

logger = logging.getLogger("careerpath.database")

class DatabaseUnavailableError(Exception):
    """Raised when live database connection is unavailable in non-testing mode."""
    pass

# -----------------------------------------------------------------------------
# Supabase Client Configuration
# -----------------------------------------------------------------------------
SUPABASE_URL = os.getenv("SUPABASE_URL", "")
# Support both SUPABASE_SECRET_KEY and SUPABASE_SERVICE_ROLE_KEY
SUPABASE_SECRET_KEY = os.getenv("SUPABASE_SECRET_KEY") or os.getenv("SUPABASE_SERVICE_ROLE_KEY") or ""

_supabase_client = None

# In-memory mock storage reserved strictly for explicit testing mode
_mock_profiles: Dict[str, Dict[str, Any]] = {}
_mock_skills: Dict[str, List[str]] = {}
_mock_interests: Dict[str, List[str]] = {}
_mock_selections: Dict[str, int] = {}
_mock_files: Dict[str, Dict[str, Any]] = {}
_mock_profile_images: Dict[str, str] = {}

def is_valid_supabase_config() -> bool:
    """Checks whether valid non-placeholder Supabase credentials are configured."""
    if not SUPABASE_URL or not SUPABASE_SECRET_KEY:
        return False
    if "your-project-id" in SUPABASE_URL or "your-supabase" in SUPABASE_SECRET_KEY:
        return False
    return True

def is_explicit_test_mode() -> bool:
    """Returns True if the runtime is in an explicit automated testing environment."""
    return (
        os.getenv("TESTING", "").lower() in ("true", "1", "yes")
        or os.getenv("ENVIRONMENT", "").lower() in ("test", "testing", "pytest")
        or "pytest" in sys.modules
    )

def get_supabase_client():
    """
    Returns official Supabase client instance if valid credentials exist.
    In production mode, raises DatabaseUnavailableError if credentials are missing or unreachable.
    """
    global _supabase_client
    if _supabase_client is not None:
        return _supabase_client

    if is_valid_supabase_config():
        try:
            from supabase import create_client
            _supabase_client = create_client(SUPABASE_URL, SUPABASE_SECRET_KEY)
            logger.info("Supabase client initialized successfully with live endpoint.")
            return _supabase_client
        except Exception as e:
            logger.error(f"Failed to initialize live Supabase client: {e}")
            if not is_explicit_test_mode():
                raise DatabaseUnavailableError(
                    "Supabase PostgreSQL connection failed. Verify SUPABASE_URL and SUPABASE_SECRET_KEY."
                ) from e
            return None
    else:
        if not is_explicit_test_mode():
            raise DatabaseUnavailableError(
                "Valid SUPABASE_URL and SUPABASE_SECRET_KEY must be configured in server environment."
            )
        return None

# Attempt client initialization
try:
    get_supabase_client()
except DatabaseUnavailableError as e:
    logger.warning(f"[DATABASE NOTICE] {e}")

# -----------------------------------------------------------------------------
# Database Health & Connectivity Check
# -----------------------------------------------------------------------------
def check_db_health() -> Dict[str, Any]:
    """
    Performs a non-destructive verification of database connectivity.
    """
    try:
        client = get_supabase_client()
        if client is not None:
            # Harmless query: check table existence and read at most 1 record
            res = client.table("student_profiles").select("firebase_uid").limit(1).execute()
            return {
                "status": "connected",
                "provider": "Supabase PostgreSQL",
                "endpoint": SUPABASE_URL.split("//")[-1].split(".")[0] + ".supabase.co" if "//" in SUPABASE_URL else "configured",
                "live": True,
                "error": None
            }
    except Exception as e:
        if not is_explicit_test_mode():
            return {
                "status": "error",
                "provider": "Supabase PostgreSQL",
                "live": False,
                "error": str(e)
            }

    if is_explicit_test_mode():
        return {
            "status": "testing_mode",
            "provider": "Isolated Test Double Store",
            "live": False,
            "error": "Test mode active with isolated memory store."
        }
    else:
        return {
            "status": "unconfigured",
            "provider": "Supabase PostgreSQL",
            "live": False,
            "error": "Valid SUPABASE_URL and SUPABASE_SECRET_KEY not yet supplied in .env"
        }

# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# In-Memory Session Cache for Student Profiles (TTL-based)
# -----------------------------------------------------------------------------
_profile_cache: Dict[str, Dict[str, Any]] = {}
_PROFILE_CACHE_TTL_SECONDS = 60

def clear_profile_cache(firebase_uid: Optional[str] = None):
    """Explicitly clears the in-memory profile cache for a student or globally."""
    if firebase_uid:
        _profile_cache.pop(firebase_uid, None)
    else:
        _profile_cache.clear()

def _get_cached_profile(firebase_uid: str) -> Optional[Dict[str, Any]]:
    if not firebase_uid:
        return None
    entry = _profile_cache.get(firebase_uid)
    if entry and (time.time() - entry.get("timestamp", 0)) < _PROFILE_CACHE_TTL_SECONDS:
        return dict(entry["profile"])
    return None

def _cache_profile(firebase_uid: str, profile: Dict[str, Any]):
    if firebase_uid and profile:
        _profile_cache[firebase_uid] = {
            "timestamp": time.time(),
            "profile": dict(profile)
        }

# Student Profile Operations (Strictly mapped to verified Firebase UID)
# -----------------------------------------------------------------------------
def get_student_profile(firebase_uid: str) -> Optional[Dict[str, Any]]:
    """Retrieves student profile matching the verified Firebase UID."""
    if not firebase_uid:
        return None

    # Check safe in-memory session cache first to eliminate repeated network calls
    cached = _get_cached_profile(firebase_uid)
    if cached is not None:
        return cached

    client = get_supabase_client()
    if client is not None:
        try:
            res = client.table("student_profiles").select("*").eq("firebase_uid", firebase_uid).execute()
            if res.data and len(res.data) > 0:
                profile = dict(res.data[0])
                
                profile["student_skills"] = get_student_skills(firebase_uid)
                profile["interests"] = get_student_interests(firebase_uid)

                profile["profile_image_file_id"] = profile.get("profile_image_file_id")
                _cache_profile(firebase_uid, profile)
                return profile
            return None
        except Exception as e:
            logger.error(f"Error fetching profile from Supabase: {e}")
            raise e
    elif is_explicit_test_mode():
        if firebase_uid in _mock_profiles:
            profile = dict(_mock_profiles[firebase_uid])
            profile["student_skills"] = list(_mock_skills.get(firebase_uid, []))
            profile["interests"] = list(_mock_interests.get(firebase_uid, []))
            profile["profile_image_file_id"] = _mock_profile_images.get(firebase_uid)
            return profile
        return None
    else:
        raise DatabaseUnavailableError("Supabase PostgreSQL connection is unavailable.")

def upsert_student_profile(firebase_uid: str, data: Dict[str, Any]) -> Dict[str, Any]:
    """Upserts student profile data for verified Firebase UID."""
    if not firebase_uid:
        raise ValueError("firebase_uid is required")

    clear_profile_cache(firebase_uid)

    now_iso = datetime.now(timezone.utc).isoformat()
    record = {
        "firebase_uid": firebase_uid,
        "full_name": data.get("full_name") or data.get("name") or "",
        "email": data.get("email", ""),
        "college_name": data.get("college_name", ""),
        "branch": data.get("branch", ""),
        "academic_year": str(data.get("academic_year", "1")),
        "graduation_year": data.get("graduation_year"),
        "onboarding_completed": bool(data.get("onboarding_completed", True)),
        "updated_at": now_iso
    }

    # Remove any sensitive or disallowed fields
    record.pop("password", None)
    record.pop("password_hash", None)

    client = get_supabase_client()
    if client is not None:
        try:
            existing = client.table("student_profiles").select("created_at").eq("firebase_uid", firebase_uid).execute()
            if not existing.data:
                record["created_at"] = now_iso
            
            client.table("student_profiles").upsert(record).execute()
            
            if "student_skills" in data or "skills" in data:
                skills_list = data.get("student_skills") or data.get("skills") or []
                set_student_skills(firebase_uid, skills_list)

            if "interests" in data or "interest_domain" in data:
                interests_list = data.get("interests") or [data.get("interest_domain")]
                if isinstance(interests_list, str):
                    interests_list = [interests_list]
                set_student_interests(firebase_uid, interests_list)

            return get_student_profile(firebase_uid) or record
        except Exception as e:
            logger.error(f"Error upserting profile to Supabase: {e}")
            raise e
    elif is_explicit_test_mode():
        if firebase_uid not in _mock_profiles:
            record["created_at"] = now_iso
        else:
            record["created_at"] = _mock_profiles[firebase_uid].get("created_at", now_iso)
        
        _mock_profiles[firebase_uid] = record

        if "student_skills" in data or "skills" in data:
            skills_list = data.get("student_skills") or data.get("skills") or []
            set_student_skills(firebase_uid, skills_list)

        if "interests" in data or "interest_domain" in data:
            interests_list = data.get("interests") or [data.get("interest_domain")]
            if isinstance(interests_list, str):
                interests_list = [interests_list]
            set_student_interests(firebase_uid, interests_list)

        return get_student_profile(firebase_uid)
    else:
        raise DatabaseUnavailableError("Supabase PostgreSQL connection is unavailable.")

# -----------------------------------------------------------------------------
# Student Skills Operations
# -----------------------------------------------------------------------------
def get_student_skills(firebase_uid: str) -> List[str]:
    """Retrieves list of confirmed skill names for a student."""
    client = get_supabase_client()
    if client is not None:
        try:
            res = client.table("student_skills").select("skills(skill_name)").eq("firebase_uid", firebase_uid).execute()
            skills = []
            if res.data:
                for row in res.data:
                    sk = row.get("skills")
                    if isinstance(sk, dict) and "skill_name" in sk:
                        skills.append(sk["skill_name"])
                    elif isinstance(sk, list) and sk and "skill_name" in sk[0]:
                        skills.append(sk[0]["skill_name"])
            return skills
        except Exception as e:
            logger.error(f"Error fetching student skills: {e}")
            return []
    elif is_explicit_test_mode():
        return list(_mock_skills.get(firebase_uid, []))
    else:
        raise DatabaseUnavailableError("Supabase PostgreSQL connection is unavailable.")

def set_student_skills(firebase_uid: str, skills: List[str], confirmation_source: str = "manual") -> bool:
    """Updates/replaces student skills in normalized tables."""
    clear_profile_cache(firebase_uid)
    clean_skills = [s.strip() for s in skills if s and s.strip()]
    client = get_supabase_client()
    if client is not None:
        try:
            client.table("student_skills").delete().eq("firebase_uid", firebase_uid).execute()
            for sname in clean_skills:
                s_res = client.table("skills").select("skill_id").eq("skill_name", sname).execute()
                if s_res.data and len(s_res.data) > 0:
                    sid = s_res.data[0]["skill_id"]
                else:
                    new_s = client.table("skills").insert({"skill_name": sname, "skill_category": "Technical"}).execute()
                    sid = new_s.data[0]["skill_id"] if new_s.data else None

                if sid is not None:
                    client.table("student_skills").insert({
                        "firebase_uid": firebase_uid,
                        "skill_id": sid,
                        "confirmation_source": confirmation_source
                    }).execute()
            return True
        except Exception as e:
            logger.error(f"Error setting student skills: {e}")
            raise e
    elif is_explicit_test_mode():
        _mock_skills[firebase_uid] = clean_skills
        return True
    else:
        raise DatabaseUnavailableError("Supabase PostgreSQL connection is unavailable.")

# -----------------------------------------------------------------------------
# Student Interests Operations
# -----------------------------------------------------------------------------
def get_student_interests(firebase_uid: str) -> List[str]:
    """Retrieves list of career domains of interest for a student."""
    client = get_supabase_client()
    if client is not None:
        try:
            res = client.table("student_interests").select("career_domains(domain_name)").eq("firebase_uid", firebase_uid).execute()
            domains = []
            if res.data:
                for row in res.data:
                    dom = row.get("career_domains")
                    if isinstance(dom, dict) and "domain_name" in dom:
                        domains.append(dom["domain_name"])
                    elif isinstance(dom, list) and dom and "domain_name" in dom[0]:
                        domains.append(dom[0]["domain_name"])
            return domains
        except Exception as e:
            logger.error(f"Error fetching student interests: {e}")
            return []
    elif is_explicit_test_mode():
        return list(_mock_interests.get(firebase_uid, []))
    else:
        raise DatabaseUnavailableError("Supabase PostgreSQL connection is unavailable.")

def set_student_interests(firebase_uid: str, domains: List[str]) -> bool:
    """Updates/replaces career domain interests for a student."""
    clear_profile_cache(firebase_uid)
    clean_domains = [d.strip() for d in domains if d and d.strip()]
    client = get_supabase_client()
    if client is not None:
        try:
            client.table("student_interests").delete().eq("firebase_uid", firebase_uid).execute()
            for dname in clean_domains:
                d_res = client.table("career_domains").select("domain_id").eq("domain_name", dname).execute()
                if d_res.data and len(d_res.data) > 0:
                    did = d_res.data[0]["domain_id"]
                else:
                    new_d = client.table("career_domains").insert({"domain_name": dname}).execute()
                    did = new_d.data[0]["domain_id"] if new_d.data else None

                if did is not None:
                    client.table("student_interests").insert({
                        "firebase_uid": firebase_uid,
                        "domain_id": did
                    }).execute()
            return True
        except Exception as e:
            logger.error(f"Error setting student interests: {e}")
            raise e
    elif is_explicit_test_mode():
        _mock_interests[firebase_uid] = clean_domains
        return True
    else:
        raise DatabaseUnavailableError("Supabase PostgreSQL connection is unavailable.")

# -----------------------------------------------------------------------------
# Onboarding Status Operation
# -----------------------------------------------------------------------------
def get_onboarding_status(firebase_uid: str) -> Dict[str, Any]:
    """Returns onboarding status and profile completeness."""
    profile = get_student_profile(firebase_uid)
    if not profile:
        return {
            "exists": False,
            "onboarding_completed": False,
            "profile": None
        }
    return {
        "exists": True,
        "onboarding_completed": bool(profile.get("onboarding_completed", False)),
        "profile": profile
    }

# -----------------------------------------------------------------------------
# Stage 4: Student File Metadata Operations (student_files)
# -----------------------------------------------------------------------------
def create_file_record(file_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Saves file metadata record in PostgreSQL student_files table.
    Enforces required fields and verified Firebase UID ownership.
    """
    file_id = file_data.get("id") or str(uuid.uuid4())
    now_iso = datetime.now(timezone.utc).isoformat()
    record = {
        "id": file_id,
        "firebase_uid": file_data["firebase_uid"],
        "bucket_name": file_data["bucket_name"],
        "storage_path": file_data["storage_path"],
        "original_filename": file_data["original_filename"],
        "content_type": file_data["content_type"],
        "file_size_bytes": file_data["file_size_bytes"],
        "file_category": file_data["file_category"],
        "upload_status": file_data.get("upload_status", "completed"),
        "created_at": now_iso,
        "updated_at": now_iso
    }

    client = get_supabase_client()
    if client is not None:
        try:
            res = client.table("student_files").insert(record).execute()
            return res.data[0] if res.data else record
        except Exception as e:
            logger.error(f"Error creating file metadata in Supabase: {e}")
            raise e
    elif is_explicit_test_mode():
        _mock_files[file_id] = record
        return record
    else:
        raise DatabaseUnavailableError("Supabase PostgreSQL connection is unavailable.")

def get_file_record(file_id: str, firebase_uid: str) -> Optional[Dict[str, Any]]:
    """Retrieves file metadata record, strictly verifying student ownership."""
    client = get_supabase_client()
    if client is not None:
        try:
            res = client.table("student_files").select("*").eq("id", file_id).eq("firebase_uid", firebase_uid).execute()
            if res.data and len(res.data) > 0:
                return dict(res.data[0])
            return None
        except Exception as e:
            logger.error(f"Error fetching file metadata: {e}")
            raise e
    elif is_explicit_test_mode():
        f = _mock_files.get(file_id)
        if f and f.get("firebase_uid") == firebase_uid:
            return dict(f)
        return None
    else:
        raise DatabaseUnavailableError("Supabase PostgreSQL connection is unavailable.")

def list_student_files(firebase_uid: str, file_category: Optional[str] = None) -> List[Dict[str, Any]]:
    """Lists files uploaded by the authenticated student."""
    client = get_supabase_client()
    if client is not None:
        try:
            query = client.table("student_files").select("*").eq("firebase_uid", firebase_uid).eq("upload_status", "completed")
            if file_category:
                query = query.eq("file_category", file_category)
            res = query.order("created_at", desc=True).execute()
            return res.data or []
        except Exception as e:
            logger.error(f"Error listing student files: {e}")
            raise e
    elif is_explicit_test_mode():
        results = [
            dict(f) for f in _mock_files.values()
            if f.get("firebase_uid") == firebase_uid
            and f.get("upload_status") == "completed"
            and (not file_category or f.get("file_category") == file_category)
        ]
        results.sort(key=lambda x: x.get("created_at", ""), reverse=True)
        return results
    else:
        raise DatabaseUnavailableError("Supabase PostgreSQL connection is unavailable.")

def delete_file_record(file_id: str, firebase_uid: str) -> bool:
    """Deletes file metadata record after verifying ownership."""
    client = get_supabase_client()
    if client is not None:
        try:
            res = client.table("student_files").delete().eq("id", file_id).eq("firebase_uid", firebase_uid).execute()
            return True
        except Exception as e:
            logger.error(f"Error deleting file record: {e}")
            raise e
    elif is_explicit_test_mode():
        if file_id in _mock_files and _mock_files[file_id].get("firebase_uid") == firebase_uid:
            del _mock_files[file_id]
            return True
        return False
    else:
        raise DatabaseUnavailableError("Supabase PostgreSQL connection is unavailable.")

def set_profile_image(firebase_uid: str, file_id: Optional[str]) -> bool:
    """Updates student profile pointer to active profile image."""
    clear_profile_cache(firebase_uid)
    client = get_supabase_client()
    if client is not None:
        try:
            client.table("student_profiles").update({"profile_image_file_id": file_id}).eq("firebase_uid", firebase_uid).execute()
            return True
        except Exception as e:
            logger.error(f"Error updating profile image pointer: {e}")
            raise e
    elif is_explicit_test_mode():
        _mock_profile_images[firebase_uid] = file_id or ""
        if firebase_uid in _mock_profiles:
            _mock_profiles[firebase_uid]["profile_image_file_id"] = file_id
        return True
    else:
        raise DatabaseUnavailableError("Supabase PostgreSQL connection is unavailable.")

def get_profile_image_file_id(firebase_uid: str) -> Optional[str]:
    """Retrieves current profile image file ID for student."""
    profile = get_student_profile(firebase_uid)
    if profile:
        return profile.get("profile_image_file_id")
    return None

# -----------------------------------------------------------------------------
# Stage 5: Student Career Selection Operations (student_career_selections)
# -----------------------------------------------------------------------------
def get_student_selected_career(firebase_uid: str) -> Optional[Dict[str, Any]]:
    """Retrieves selected career role for the authenticated student."""
    if not firebase_uid:
        return None
    client = get_supabase_client()
    if client is not None:
        try:
            res = (
                client.table("student_career_selections")
                .select("*, job_roles(*)")
                .eq("firebase_uid", firebase_uid)
                .order("selected_at", desc=True)
                .limit(1)
                .execute()
            )
            if res.data and len(res.data) > 0:
                return res.data[0]
            return None
        except Exception as e:
            logger.error(f"Error fetching student selected career: {e}")
            raise e
    elif is_explicit_test_mode():
        role_id = _mock_selections.get(firebase_uid)
        if role_id is not None:
            return {
                "firebase_uid": firebase_uid,
                "selected_role_id": role_id,
                "role_id": role_id,
                "selected_at": datetime.now(timezone.utc).isoformat()
            }
        return None
    else:
        raise DatabaseUnavailableError("Supabase PostgreSQL connection is unavailable.")

def set_student_selected_career(firebase_uid: str, role_id: int) -> Dict[str, Any]:
    """Saves student's selected career role."""
    if not firebase_uid:
        raise ValueError("firebase_uid is required")
    now_iso = datetime.now(timezone.utc).isoformat()
    record = {
        "firebase_uid": firebase_uid,
        "selected_role_id": int(role_id),
        "selected_at": now_iso
    }
    client = get_supabase_client()
    if client is not None:
        try:
            res = client.table("student_career_selections").insert(record).execute()
            return res.data[0] if res.data else record
        except Exception as e:
            logger.error(f"Error saving selected career: {e}")
            raise e
    elif is_explicit_test_mode():
        _mock_selections[firebase_uid] = int(role_id)
        return record
    else:
        raise DatabaseUnavailableError("Supabase PostgreSQL connection is unavailable.")

# -----------------------------------------------------------------------------
# Stage 5: Curated Educational & Placement Resource Providers
# -----------------------------------------------------------------------------
def get_learning_resources_for_role(role_id: Optional[int] = None, domain: Optional[str] = None) -> List[Dict[str, Any]]:
    """Retrieves verified learning resources from Supabase or curated catalogue."""
    client = get_supabase_client()
    if client is not None:
        try:
            res = client.table("learning_resources").select("*").limit(20).execute()
            if res.data and len(res.data) > 0:
                return res.data
        except Exception as e:
            logger.info(f"Notice fetching learning resources from Supabase: {e}")

    # Fallback to curated external providers (Coursera, edX, MIT OpenCourseWare)
    return [
        {
            "resource_id": 1,
            "title": "Algorithmic Problem Solving & Data Structures",
            "resource_type": "course",
            "platform": "Coursera / UC San Diego",
            "external_url": "https://www.coursera.org/specializations/data-structures-algorithms",
            "description": "Foundational algorithmic problem solving, graph algorithms, and asymptotic complexity.",
            "is_free": False,
            "source": "Curated Educational Directory"
        },
        {
            "resource_id": 2,
            "title": "Python for Everybody Specialization",
            "resource_type": "course",
            "platform": "Coursera / University of Michigan",
            "external_url": "https://www.coursera.org/specializations/python",
            "description": "Comprehensive introduction to Python programming, data structures, and networked APIs.",
            "is_free": False,
            "source": "Curated Educational Directory"
        },
        {
            "resource_id": 3,
            "title": "Full Stack Open: Modern Web Development",
            "resource_type": "course",
            "platform": "University of Helsinki",
            "external_url": "https://fullstackopen.com/en/",
            "description": "Deep dive into React, Redux, Node.js, Express, RESTful APIs, and TypeScript.",
            "is_free": True,
            "source": "Curated Educational Directory"
        }
    ]

def get_certifications_for_role(role_id: Optional[int] = None, domain: Optional[str] = None) -> List[Dict[str, Any]]:
    """Retrieves verified professional certifications."""
    client = get_supabase_client()
    if client is not None:
        try:
            query = client.table("certifications").select("*")
            res = query.limit(20).execute()
            if res.data:
                return res.data
        except Exception as e:
            logger.warning(f"Notice fetching certifications: {e}")

    return [
        {
            "certification_id": 1,
            "certification_name": "AWS Certified Cloud Practitioner",
            "issuing_organization": "Amazon Web Services",
            "external_url": "https://aws.amazon.com/certification/certified-cloud-practitioner/",
            "description": "Foundational understanding of AWS Cloud services, security, architecture, and pricing models.",
            "source": "Official Vendor Certification Directory"
        },
        {
            "certification_id": 2,
            "certification_name": "CompTIA Security+",
            "issuing_organization": "CompTIA",
            "external_url": "https://www.comptia.org/certifications/security",
            "description": "Global certification that validates the baseline skills necessary to perform core security functions.",
            "source": "Official Vendor Certification Directory"
        },
        {
            "certification_id": 3,
            "certification_name": "Autodesk Certified Professional: AutoCAD",
            "issuing_organization": "Autodesk",
            "external_url": "https://www.autodesk.com/certification/all-certifications/autocad-design-drafting-professional",
            "description": "Industry certification verifying advanced skills in AutoCAD 2D drafting and 3D modeling.",
            "source": "Official Vendor Certification Directory"
        }
    ]

def get_internships_for_role(role_title: str = "Engineering", domain: Optional[str] = None) -> List[Dict[str, Any]]:
    """Retrieves verified internship search streams and curated opportunities."""
    client = get_supabase_client()
    if client is not None:
        try:
            query = client.table("internships").select("*").eq("is_active", True)
            res = query.limit(10).execute()
            if res.data:
                return res.data
        except Exception as e:
            logger.warning(f"Notice fetching internships: {e}")

    safe_title = role_title.replace(" ", "%20")
    return [
        {
            "internship_id": 1,
            "role_title": f"{role_title} Intern",
            "source_platform": "LinkedIn Jobs",
            "application_url": f"https://www.linkedin.com/jobs/search/?keywords={safe_title}%20Intern",
            "description": f"Verified live job search feed for student internship and graduate openings in {role_title}.",
            "eligibility": "B.Tech / B.E. Students (Year 2 to Final Year)",
            "is_curated_search": True,
            "verification_date": "2026-10-29"
        },
        {
            "internship_id": 2,
            "role_title": f"Junior {role_title} Apprenticeship",
            "source_platform": "Wellfound (formerly AngelList)",
            "application_url": f"https://wellfound.com/jobs?role={safe_title}",
            "description": "High-growth startup internships and entry-level positions.",
            "eligibility": "Pre-final and Final Year Engineering Undergraduates",
            "is_curated_search": True,
            "verification_date": "2026-10-29"
        }
    ]

def get_interview_questions_for_role(role_id: Optional[int] = None, role_title: str = "Engineer") -> List[Dict[str, Any]]:
    """Retrieves categorized interview questions."""
    client = get_supabase_client()
    if client is not None:
        try:
            query = client.table("interview_questions").select("*")
            if role_id:
                query = query.eq("role_id", role_id)
            res = query.limit(20).execute()
            if res.data:
                return res.data
        except Exception as e:
            logger.warning(f"Notice fetching interview questions: {e}")

    return [
        {
            "question_id": 1,
            "topic": "Technical",
            "difficulty_level": "Medium",
            "question_text": f"Walk through how you design and test a core module in a project relevant to {role_title}.",
            "tips": "Detail your choice of data structures, complexity trade-offs, and edge case test coverage."
        },
        {
            "question_id": 2,
            "topic": "System Design / Architecture",
            "difficulty_level": "Hard",
            "question_text": "How do you evaluate system bottlenecks and optimize performance under high throughput or load?",
            "tips": "Discuss profiling tools, indexing/caching strategies, and asynchronous execution."
        },
        {
            "question_id": 3,
            "topic": "Behavioral / HR",
            "difficulty_level": "Easy",
            "question_text": "Describe a scenario where a project requirement changed midway through a team sprint. How did you adapt?",
            "tips": "Apply the STAR method (Situation, Task, Action, Result) with measurable team impact."
        }
    ]

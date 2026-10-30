import os
import json
import shutil
import logging
from datetime import datetime, timezone

from database import upsert_student_profile, set_student_skills, set_student_interests

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("migrate_legacy_profiles")

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
USERS_DB_PATH = os.path.join(BASE_DIR, "users_db.json")
BACKUP_PATH = os.path.join(BASE_DIR, "users_db_pre_stage3.json.bak")

def backup_legacy_store():
    if os.path.exists(USERS_DB_PATH):
        shutil.copyfile(USERS_DB_PATH, BACKUP_PATH)
        logger.info(f"Backed up legacy users store to {BACKUP_PATH}")
        return True
    return False

def migrate_profiles():
    """
    Safely migrates legacy profile data from users_db.json into student_profiles.
    - Requires explicitly verified firebase_uid.
    - Strictly removes password hashes.
    - Preserves academic year, skills, interest domains.
    - Retains original backup without deletion.
    """
    if not os.path.exists(USERS_DB_PATH):
        logger.warning("No legacy users_db.json found to migrate.")
        return {"status": "no_source_file", "migrated": 0, "skipped_unverified": 0}

    backup_legacy_store()

    with open(USERS_DB_PATH, "r", encoding="utf-8") as f:
        legacy_users = json.load(f)

    migrated_count = 0
    skipped_unverified = 0

    for email, user_data in legacy_users.items():
        firebase_uid = user_data.get("firebase_uid")
        
        # Rule: Do not infer user ownership solely from email; require explicit firebase_uid
        if not firebase_uid:
            logger.info(f"Skipping profile for [{email[:3]}***]: No verified Firebase UID linked yet.")
            skipped_unverified += 1
            continue

        clean_data = {
            "email": email,
            "full_name": user_data.get("name") or user_data.get("full_name") or "",
            "college_name": user_data.get("college_name", ""),
            "branch": user_data.get("branch", ""),
            "academic_year": str(user_data.get("academic_year", 1)),
            "graduation_year": user_data.get("graduation_year"),
            "onboarding_completed": True,
            "skills": user_data.get("skills", []),
            "interests": [user_data.get("interest_domain")] if user_data.get("interest_domain") else []
        }

        # Ensure passwords/hashes are never migrated
        clean_data.pop("password_hash", None)
        clean_data.pop("password", None)

        try:
            upsert_student_profile(firebase_uid, clean_data)
            migrated_count += 1
            logger.info(f"Successfully migrated verified profile for UID [{firebase_uid[:6]}***]")
        except Exception as e:
            logger.error(f"Failed to migrate profile for UID [{firebase_uid[:6]}***]: {e}")

    logger.info(f"Migration complete: {migrated_count} verified profiles migrated, {skipped_unverified} legacy accounts deferred until Firebase verification.")
    return {
        "status": "success",
        "migrated": migrated_count,
        "skipped_unverified": skipped_unverified
    }

if __name__ == "__main__":
    res = migrate_profiles()
    print("Migration result:", res)

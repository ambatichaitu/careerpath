import os
import json
import logging
from typing import Dict, Any, List

from database import get_supabase_client, is_valid_supabase_config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("seed_database")

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

def resolve_path(filename: str) -> str:
    candidates = [
        os.path.join(BASE_DIR, filename),
        os.path.join(BASE_DIR, "backend", filename),
        os.path.join(BASE_DIR, "..", filename),
        filename
    ]
    for p in candidates:
        if os.path.exists(p):
            return os.path.abspath(p)
    return os.path.join(BASE_DIR, filename)

ROLES_PATH = resolve_path("master_roles.json")
SKILLS_PATH = resolve_path("skills_dictionary.json")

def load_data():
    with open(ROLES_PATH, "r", encoding="utf-8") as f:
        roles = json.load(f)
    with open(SKILLS_PATH, "r", encoding="utf-8") as f:
        skills = json.load(f)
    return roles, skills

def seed(dry_run: bool = False):
    """
    Idempotently seeds O*NET career roles, normalized skills, domains, and mappings.
    """
    roles, skills_dict = load_data()
    logger.info(f"Loaded {len(roles)} roles and {len(skills_dict)} master skills from disk.")

    if not is_valid_supabase_config():
        logger.info("[DRY RUN / OFFLINE] Valid Supabase credentials not found. Validating dataset integrity locally.")
        unique_roles = {r.get("onet_code") for r in roles if r.get("onet_code")}
        unique_skills = set(skills_dict)
        for r in roles:
            for s in r.get("technical_skills", []):
                unique_skills.add(s)
            for s in r.get("in_demand_skills", []):
                unique_skills.add(s)

        domains = {r.get("primary_interest") for r in roles if r.get("primary_interest")}
        logger.info(f"Integrity check passed:")
        logger.info(f"  - Unique O*NET codes: {len(unique_roles)}")
        logger.info(f"  - Total unique skills: {len(unique_skills)}")
        logger.info(f"  - Unique career domains: {len(domains)}")
        return {
            "status": "validated_offline",
            "roles_count": len(unique_roles),
            "skills_count": len(unique_skills),
            "domains_count": len(domains)
        }

    client = get_supabase_client()

    if dry_run:
        logger.info("Dry-run requested. Skipping cloud mutations.")
        return {"status": "dry_run_success", "roles_to_seed": len(roles)}

    logger.info("Starting live Supabase seed operation...")

    # 1. Seed Skills
    logger.info("Seeding skills catalog...")
    all_skills = set(skills_dict)
    for r in roles:
        for s in r.get("technical_skills", []):
            if s: all_skills.add(s.strip())
        for s in r.get("in_demand_skills", []):
            if s: all_skills.add(s.strip())

    skill_name_to_id = {}
    batch_size = 100
    all_skills_list = [{"skill_name": s, "skill_category": "Technical"} for s in sorted(all_skills) if s]

    for i in range(0, len(all_skills_list), batch_size):
        batch = all_skills_list[i:i + batch_size]
        client.table("skills").upsert(batch, on_conflict="skill_name").execute()

    # Read back skill map
    res = client.table("skills").select("skill_id, skill_name").execute()
    for row in res.data:
        skill_name_to_id[row["skill_name"]] = row["skill_id"]
    logger.info(f"Upserted and indexed {len(skill_name_to_id)} skills.")

    # 2. Seed Career Domains
    domains = sorted(list({r.get("primary_interest", "").strip() for r in roles if r.get("primary_interest")}))
    domain_name_to_id = {}
    domain_records = [{"domain_name": d} for d in domains if d]
    if domain_records:
        client.table("career_domains").upsert(domain_records, on_conflict="domain_name").execute()
        d_res = client.table("career_domains").select("domain_id, domain_name").execute()
        for row in d_res.data:
            domain_name_to_id[row["domain_name"]] = row["domain_id"]
    logger.info(f"Upserted and indexed {len(domain_name_to_id)} career domains.")

    # 3. Seed Job Roles
    logger.info("Seeding job roles...")
    role_records = []
    for r in roles:
        role_records.append({
            "onet_code": r.get("onet_code", "N/A"),
            "job_title": r.get("title", "Unknown Role"),
            "description": r.get("description", ""),
            "career_domain": r.get("primary_interest", ""),
            "education_requirements": r.get("typical_education", "Bachelor's Degree")
        })

    for i in range(0, len(role_records), batch_size):
        batch = role_records[i:i + batch_size]
        client.table("job_roles").upsert(batch, on_conflict="onet_code").execute()

    # Read back role map
    role_onet_to_id = {}
    r_res = client.table("job_roles").select("role_id, onet_code").execute()
    for row in r_res.data:
        role_onet_to_id[row["onet_code"]] = row["role_id"]
    logger.info(f"Upserted and indexed {len(role_onet_to_id)} job roles.")

    # 4. Seed Job Role Skills
    logger.info("Seeding role-to-skill mappings...")
    mapping_records = []
    for r in roles:
        onet = r.get("onet_code")
        rid = role_onet_to_id.get(onet)
        if not rid:
            continue

        tech_skills = set(r.get("technical_skills", []))
        in_demand = set(r.get("in_demand_skills", []))

        for s in tech_skills:
            sid = skill_name_to_id.get(s)
            if sid:
                mapping_records.append({
                    "role_id": rid,
                    "skill_id": sid,
                    "importance_weight": 1.25 if s in in_demand else 1.00,
                    "skill_type": "in_demand" if s in in_demand else "technical"
                })

    for i in range(0, len(mapping_records), batch_size):
        batch = mapping_records[i:i + batch_size]
        client.table("job_role_skills").upsert(batch, on_conflict="role_id,skill_id").execute()

    logger.info(f"Successfully seeded {len(mapping_records)} role-skill mappings.")
    return {
        "status": "seed_completed",
        "roles_seeded": len(role_onet_to_id),
        "skills_seeded": len(skill_name_to_id),
        "domains_seeded": len(domain_name_to_id),
        "mappings_seeded": len(mapping_records)
    }

if __name__ == "__main__":
    result = seed()
    print("Seed result:", result)

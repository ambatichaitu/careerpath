"""
CareerPath Recommendation & Skill Gap Analysis Engine (Stage 5)
Provides deterministic, explainable career role matching, skill gap classification,
RIASEC and domain filtering, and year-aware learning roadmaps based on O*NET datasets.
"""

import re
from typing import List, Dict, Any, Tuple, Optional

# Standard skill alias normalization dictionary
SKILL_ALIASES: Dict[str, str] = {
    "python3": "python",
    "py": "python",
    "js": "javascript",
    "ts": "typescript",
    "node": "node.js",
    "nodejs": "node.js",
    "reactjs": "react",
    "react.js": "react",
    "postgres": "postgresql",
    "pgsql": "postgresql",
    "cplusplus": "c++",
    "cpp": "c++",
    "c#": "c sharp",
    "csharp": "c sharp",
    "k8s": "kubernetes",
    "golang": "go",
    "autocad": "autocad",
    "auto cad": "autocad",
    "solidworks": "solidworks",
    "solid works": "solidworks",
    "aws": "amazon web services",
    "gcp": "google cloud platform",
}

def normalize_skill(name: str) -> str:
    """Normalizes skill string for consistent matching and deduplication."""
    if not name:
        return ""
    clean = name.strip().lower()
    clean = re.sub(r"\s+", " ", clean)
    return SKILL_ALIASES.get(clean, clean)

def is_skill_match(student_skill: str, role_skill: str) -> bool:
    """
    Checks if a student's confirmed skill matches a required role skill.
    Supports exact match, canonical aliases, and word-boundary inclusion
    (e.g., 'AutoCAD' matches 'Autodesk AutoCAD', 'SQL' matches 'Microsoft SQL Server')
    without triggering single-letter false positives ('c' matching 'AutoCAD').
    """
    s_norm = normalize_skill(student_skill)
    r_norm = normalize_skill(role_skill)

    if not s_norm or not r_norm:
        return False

    if s_norm == r_norm:
        return True

    # Avoid false positives for very short skill strings (e.g., 'c', 'r')
    if len(s_norm) <= 1:
        return False

    # Standalone word-boundary match (e.g. 'sql' in 'microsoft sql server', 'react' in 'react native')
    # but prevent 'java' matching 'javascript'
    pattern = r"(?<![a-z0-9])" + re.escape(s_norm) + r"(?![a-z0-9])"
    if re.search(pattern, r_norm):
        return True

    return False

def build_roadmap(title: str, missing_skills: List[str], year: int) -> List[str]:
    """Builds year-aware structured learning roadmap based on missing skills and academic year."""
    top_missing = ", ".join(missing_skills[:3]) if missing_skills else "advanced system design & architecture"
    if year <= 1:
        return [
            "Year 1 Fundamentals: Build core algorithmic problem-solving and programming basics.",
            f"Intro to Tooling: Begin getting familiar with {top_missing}.",
            "Join engineering clubs, participate in beginner hackathons, and set up a clean GitHub profile."
        ]
    elif year == 2:
        return [
            f"Year 2 Core Tooling: Build 2-3 production-grade portfolio projects using {top_missing}.",
            "Data Structures & Object-Oriented Design: Solve weekly coding challenges and push to GitHub.",
            "Complete guided certifications and prepare your resume for junior-year internship hunting."
        ]
    elif year == 3:
        return [
            f"Year 3 Skill Gap Closure: Earn recognized industry credentials in {top_missing}.",
            f"Capstone Execution: Develop an end-to-end applied engineering project tailored to {title}.",
            "Aggressively apply for summer internships once your Career Profile Match crosses 50%."
        ]
    else:
        return [
            f"Final Year Placement Prep: Master technical interview rounds focusing on {top_missing}.",
            "System Design & Past Candidate Questions: Daily problem solving and mock peer interviews.",
            "Resume ATS Optimization: Align your bullet points with top in-demand role keywords."
        ]

def prioritize_skills_to_learn(missing_skills: List[str], in_demand_skills: List[str]) -> List[str]:
    """Prioritizes missing skills: in-demand role skills first, followed by general technical skills."""
    in_demand_set = {normalize_skill(s) for s in in_demand_skills if s}
    high_priority = []
    normal_priority = []

    for s in missing_skills:
        if normalize_skill(s) in in_demand_set:
            high_priority.append(s)
        else:
            normal_priority.append(s)

    return high_priority + normal_priority

class RecommendationEngine:
    @staticmethod
    def match_role(
        role: Dict[str, Any],
        student_skills: List[str],
        academic_year: int = 1,
        role_index: Optional[int] = None
    ) -> Dict[str, Any]:
        """
        Evaluates a single career role against a student's profile.
        Guarantees deterministic, bounded (0-100), and explainable match results.
        """
        req_skills = role.get("technical_skills", []) or []
        in_demand_skills = role.get("in_demand_skills", []) or []
        essential_skills = role.get("essential_skills", []) or []
        
        # Deduplicate student skills using normalization
        unique_student_skills: List[str] = []
        seen_student_norms = set()
        for s in student_skills:
            if not s:
                continue
            norm = normalize_skill(s)
            if norm and norm not in seen_student_norms:
                seen_student_norms.add(norm)
                unique_student_skills.append(s.strip())

        matched_skills: List[str] = []
        missing_skills: List[str] = []

        total_weight = 0.0
        matched_weight = 0.0

        in_demand_norms = {normalize_skill(s) for s in in_demand_skills if s}

        for r_skill in req_skills:
            if not r_skill:
                continue
            r_norm = normalize_skill(r_skill)
            # In-demand skills carry higher weighting (1.5x)
            weight = 1.5 if r_norm in in_demand_norms else 1.0
            total_weight += weight

            # Check if student possesses this skill
            is_matched = any(is_skill_match(st_skill, r_skill) for st_skill in unique_student_skills)
            if is_matched:
                matched_skills.append(r_skill)
                matched_weight += weight
            else:
                missing_skills.append(r_skill)

        # Calculate bounded percentage score
        if total_weight > 0.0:
            raw_score = (matched_weight / total_weight) * 100.0
            readiness_score = int(round(min(100.0, max(0.0, raw_score))))
        else:
            readiness_score = 0

        # Prioritize learning order
        recommended_next = prioritize_skills_to_learn(missing_skills, in_demand_skills)

        # Generate clear, explainable match explanation
        title = role.get("title", "Role")
        if readiness_score == 0:
            if not unique_student_skills:
                explanation = f"Career Profile Match: 0%. No student skills recorded yet. Complete foundational courses to start preparing for {title}."
            else:
                explanation = f"Career Profile Match: 0%. None of your {len(unique_student_skills)} current skills directly overlap with {title}. Consider starting with foundational skills."
        elif readiness_score >= 70:
            explanation = f"Career Profile Match: {readiness_score}%. Strong alignment! You match {len(matched_skills)} of {len(req_skills)} required technical skills."
        elif readiness_score >= 40:
            top_gap = recommended_next[0] if recommended_next else "core tools"
            explanation = f"Career Profile Match: {readiness_score}%. Moderate match with {len(matched_skills)} skills matched. Bridging '{top_gap}' will significantly boost your readiness."
        else:
            top_gap = recommended_next[0] if recommended_next else "fundamental skills"
            explanation = f"Career Profile Match: {readiness_score}%. Early-stage match ({len(matched_skills)} of {len(req_skills)} skills). Focus on building '{top_gap}' first."

        role_id = role.get("role_id") or (role_index if role_index is not None else 1)
        onet_code = role.get("onet_code", "N/A")

        # Dynamic roadmap based on missing skills and academic year
        roadmap = build_roadmap(title, recommended_next, academic_year)

        # Curated external courses references
        courses_and_certs = [
            {
                "skill": skill,
                "course_title": f"Master {skill} for {title}",
                "platform": "Coursera / edX / Official Docs",
                "certification": f"Professional {skill} Credential",
                "search_url": f"https://www.coursera.org/search?query={skill.replace(' ', '%20')}"
            }
            for skill in recommended_next[:6]
        ]

        # Sourced internship references
        internships = [
            {
                "role": f"{title} Intern",
                "type": "Summer / Graduate Internship",
                "apply_url": f"https://www.linkedin.com/jobs/search/?keywords={title.replace(' ', '%20')}%20Intern",
                "source": "LinkedIn Jobs & Official Portals",
                "eligibility": f"Engineering Students (Year {academic_year}+)"
            }
        ]

        # Interview preparation questions
        top_in_demand = in_demand_skills[:3] or req_skills[:3]
        interview_questions = [
            f"How have you applied {skill} in a practical project or coursework problem?"
            for skill in top_in_demand
        ] + [
            "Explain how you prioritize system requirements when collaborating with team members.",
            "Walk us through an engineering trade-off you had to make in your recent academic project."
        ]

        return {
            "role_id": role_id,
            "onet_code": onet_code,
            "title": title,
            "description": role.get("description", ""),
            "domain": role.get("primary_interest", ""),
            "typical_education": role.get("typical_education", "Bachelor's Degree"),
            "readiness_score": readiness_score,
            "match_score": readiness_score,
            "matched_skills": matched_skills,
            "missing_skills": missing_skills,
            "essential_skills": essential_skills,
            "in_demand_skills": in_demand_skills,
            "foundational_skills": essential_skills,
            "recommended_next_skills": recommended_next[:5],
            "explanation": explanation,
            "roadmap": roadmap,
            "courses_and_certs": courses_and_certs,
            "internships": internships,
            "interview_questions": interview_questions
        }

    @classmethod
    def rank_roles(
        cls,
        roles: List[Dict[str, Any]],
        student_skills: List[str],
        interest_domain: Optional[str] = None,
        search_query: Optional[str] = None,
        academic_year: int = 1,
        limit: int = 30,
        offset: int = 0
    ) -> Tuple[List[Dict[str, Any]], int]:
        """
        Filters and deterministically ranks career roles based on student profile.
        Returns (ranked_roles_slice, total_matching_count).
        """
        search_clean = (search_query or "").strip().lower()
        interest_clean = (interest_domain or "").strip().lower()

        evaluated = []
        for idx, role in enumerate(roles):
            role_title = role.get("title", "")
            role_desc = role.get("description", "")
            role_interest = role.get("primary_interest", "")
            role_tech = role.get("technical_skills", [])

            # Filter by interest domain if specified
            if interest_clean and interest_clean != "all":
                domain_match = (
                    interest_clean in role_interest.lower()
                    or interest_clean in role_title.lower()
                    or interest_clean in role_desc.lower()
                )
                if not domain_match:
                    continue

            # Filter by search query if specified
            if search_clean:
                search_match = (
                    search_clean in role_title.lower()
                    or search_clean in role_desc.lower()
                    or any(search_clean in s.lower() for s in role_tech)
                )
                if not search_match:
                    continue

            match_data = cls.match_role(
                role=role,
                student_skills=student_skills,
                academic_year=academic_year,
                role_index=idx + 1
            )
            evaluated.append(match_data)

        # Deterministic ranking:
        # 1. Primary: readiness_score (descending)
        # 2. Secondary: number of matched skills (descending)
        # 3. Tertiary: role title (alphabetical ascending)
        evaluated.sort(
            key=lambda r: (-r["readiness_score"], -len(r["matched_skills"]), r["title"])
        )

        total_count = len(evaluated)
        paged = evaluated[offset:offset + limit]
        return paged, total_count

# CareerPath – Project Overview (Document A)

## 1. Project Title
**CareerPath: Personalized Career Analysis, Recommendation, and Skill Gap Intelligence System for Engineering Students**

## 2. Abstract
Engineering undergraduate education frequently suffers from a significant disconnect between standard university curricula and real-world industrial job requirements. Students frequently lack visibility into what specific skills industry roles require, how their current academic backgrounds align with target professions, and where to obtain targeted training.

**CareerPath** is a mobile and web intelligence system engineered using Flutter, Python FastAPI, Firebase Authentication, Supabase PostgreSQL, and Supabase Storage. It analyzes engineering students' academic years, skillsets, interests, and uploaded PDF resumes against a standardized catalog of 901 career roles derived from the United States Department of Labor's O*NET database. CareerPath computes deterministic match percentages, identifies missing technical competencies, curates learning resources, surfaces internship search hubs, provides interview preparation questions, and allows students to commit to a persistent Target Career Goal.

---

## 3. Problem Statement
1. **Curriculum Disconnect:** Academic coursework often lags industry adoption of specialized frameworks, cloud technologies, and modern development workflows.
2. **Ambiguous Career Paths:** Students lack explainable, data-backed guidance on what roles fit their profile and why.
3. **Skill Blindspots:** Without automated skill-gap analysis, students do not know which specific missing skills carry high market demand.
4. **Scattered Resources:** Curated certifications, internship listings, and technical interview preparation are fragmented across multiple portals.

---

## 4. Objectives
- Provide a secure, mobile-first career discovery application for engineering undergraduates.
- Integrate industry-standard Firebase Authentication with strict email verification and session management.
- Implement a pure-function, deterministic career recommendation algorithm with bounded scores [0, 100].
- Support automated PDF resume parsing and technical skill extraction using PyMuPDF.
- Maintain persistent student profiles, selected career targets, and private storage in Supabase PostgreSQL and Supabase Storage.
- Enforce strict role-based access control, cross-student data isolation, and cryptographic file authorization.

---

## 5. Main Features
- **Student Authentication & Gatekeeping:** Firebase Authentication, email verification cooldown timers, password reset modal.
- **Student Profile Onboarding:** 3-step wizard capturing academic year (Years 1–4), engineering domain, and technical skills.
- **Resume Parsing & Skill Extraction:** Secure upload of PDF resumes, text extraction, automated dictionary cross-referencing, and student confirmation.
- **Role Explorer & Recommendation Dashboard:** Dynamic search, match percentage filtering, domain tracks, and KPI status cards.
- **4-Tab Role Deep Dive:**
  1. *Skills & Gap Analysis:* Acquired vs missing skills with priority badges.
  2. *Courses & Certifications:* Curated Coursera, edX, Udemy, AWS, and Google credentials.
  3. *Internship Search:* Aggregated listings from LinkedIn, Indeed, Glassdoor, and Internshala.
  4. *Interview Preparation:* Technical and behavioral questions with structured answer guidelines.
- **Target Career Goal:** One-click persistence of student's target career path, pinned to their dashboard.
- **AI Career Guidance Chatbot:** Tailored career and academic advice contextualized to the student's academic year.

---

## 6. Scope & Academic Limitations
- **Scope:** Tailored specifically for undergraduate engineering students across Computer Science, Electrical, Mechanical, Civil, and allied disciplines.
- **Recommendation Nature:** Career match percentages are heuristic similarity metrics based on skill overlap and domain alignment; they do not predict or guarantee employment.
- **Resource Linking:** Course and certification listings reference external industry platforms via deep links; CareerPath does not host proprietary course content.

# CareerPath – Application Modules & Functionality (Document E)

## 1. Authentication & Session Module
- **Provider:** Firebase Authentication (Project ID: `careerpath-26fa0`).
- **Functionality:**
  - Student registration with email validation and minimum 6-character password enforcement.
  - Automatic dispatch of email verification links.
  - Real-time `authStateChanges` stream governing navigation state machine in `AuthGate`.
  - Password reset link dialog with email pattern verification.
  - Session security: Token refresh and cryptographic JWT extraction on every API call.

---

## 2. Student Profile Onboarding Module
- **Screen:** `OnboardingWizardScreen` (`lib/screens/onboarding_wizard_screen.dart`).
- **3-Step Flow:**
  - *Step 1: Academic Background:* Full name, institution, and Academic Year (Year 1 to Year 4).
  - *Step 2: Domain & Skills:* Career domain selection (Software Engineering, Data Science, Mechanical, Electronics, Civil, Management) and multi-select FilterChips populated from the 408-skill catalog.
  - *Step 3: Resume Upload:* PDF picker with live upload progress indicator, automated skill extraction display, and student review before saving.
- **Persistence:** Submits structured JSON to `PUT /api/v1/profile` upon completion.

---

## 3. Resume Extraction Module
- **Engine:** PyMuPDF (`fitz`) in `storage_service.py` and `main.py`.
- **Validation Pipeline:**
  1. *Size Limit:* Rejects resumes exceeding 5 MB with HTTP 413.
  2. *Format Validation:* Magic byte inspection ensures valid `%PDF` header.
  3. *Structural Validation:* PyMuPDF checks page limits (maximum 10 pages) and valid font/text structures.
  4. *Skill Extraction:* Tokenizes extracted text, applies case-insensitive word-boundary matching against `skills_dictionary.json`, and returns verified matching competencies.
  5. *Storage:* Uploads encrypted PDF to private `resumes` bucket with student-isolated path.

---

## 4. Career Matching & Skill Gap Analysis Module
- **Engine:** `RecommendationEngine` (`recommendation_engine.py`).
- **Functionality:**
  - Evaluates 901 O*NET career roles against student's acquired skills.
  - Computes weighted match score [0, 100] incorporating 1.25x - 1.5x weights for industry in-demand skills.
  - Segregates competencies into:
    - *Matched Skills:* Acquired skills required by the role (highlighted in green).
    - *Missing Skills:* Gaps to be acquired, prioritized by market demand.
  - Generates structured, explainable match summaries (e.g., "Matched 6 of 8 required skills (2 high-demand skills acquired)").

---

## 5. Learning Resources & Placement Module
- **Screen:** `RoleDetailScreen` (`lib/screens/role_detail_screen.dart`).
- **4 Tab Panels:**
  1. *Tab 1: Skills & Gap Analysis:* Visual progress bars, skill chips, prioritized next steps.
  2. *Tab 2: Courses & Certifications:* Curated courses from Coursera, edX, Udemy, and industry certifications from AWS, Microsoft, Google.
  3. *Tab 3: Internships:* Direct links to relevant internship opportunities and application portals.
  4. *Tab 4: Interview Preparation:* Frequently asked technical and behavioral questions with comprehensive model answers.
- **Deep Linking:** Uses Flutter `url_launcher` with Android `<queries>` intent filters for external links.

---

## 6. Target Career Goal Selection Module
- **Functionality:**
  - Allows students to commit to a specific career role with a single tap on "Set as Target Career".
  - Persists target choice to `student_career_selections` table via `PUT /api/v1/profile/selected-career`.
  - Displays persistent banner card at the top of the student's dashboard, keeping career objectives front and center.

---

## 7. AI Career Guidance Chatbot Module
- **Interface:** Sliding modal bottom sheet accessible from the dashboard FAB.
- **Functionality:**
  - Context-aware conversational guidance tailored to student's academic year (Years 1–4).
  - Provides domain advice, semester roadmap suggestions, and quick-reply action chips.

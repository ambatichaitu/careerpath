# CareerPath – Academic Demonstration Script (Document J)

**Duration:** 5–7 Minutes  
**Target Audience:** Academic Evaluators, Professors, and Project Reviewers  
**Demonstration Platforms:** Google Chrome & Android Emulator  

---

## Scene 1: Introduction & Motivation (Minute 0:00 – 1:00)
- **Speaker:** "Good morning/afternoon, evaluators. Today I am presenting **CareerPath**, an AI-powered career recommendation and skill-gap intelligence platform engineered for engineering undergraduates."
- **Screen:** Show Slide / Web Landing Screen.
- **Key Talking Points:**
  - Engineering students often struggle to understand how university courses map to modern industry roles.
  - CareerPath bridges this gap by cross-referencing student profiles and resumes against 901 standardized O*NET industry roles and 408 technical skills.
  - The system is built with Flutter, FastAPI, Firebase Authentication, and Supabase PostgreSQL.

---

## Scene 2: Authentication & Security Architecture (Minute 1:00 – 2:00)
- **Action:** Open CareerPath on Google Chrome or the Android Emulator. Show the `LoginScreen`.
- **Key Talking Points:**
  - "Authentication is strictly decoupled using Firebase Authentication with cryptographic JWT tokens."
  - Highlight the "Forgot Password" self-service dialog.
  - Show the 6-state `AuthGate` that enforces email verification and guides first-time students into onboarding.
  - Point out that passwords and secret database keys are never stored in plain text or client code.

---

## Scene 3: Onboarding & Resume Skill Extraction (Minute 2:00 – 3:30)
- **Action:** Walk through the 3-Step `OnboardingWizardScreen`.
  - *Step 1:* Enter academic background (e.g., Computer Science, Year 3).
  - *Step 2:* Select domain interest ("Data Science" or "Software") and select skill chips (e.g., Python, SQL, Git).
  - *Step 3:* Demonstrate PDF resume upload. Show PyMuPDF scanning the PDF in memory, extracting verified technical keywords, and presenting them for student confirmation.
- **Key Talking Points:**
  - "The resume pipeline validates magic bytes, enforces a 5 MB limit, and stores files into private buckets where access requires 60-second signed URLs."

---

## Scene 4: Dashboard & Role Recommendations (Minute 3:30 – 5:00)
- **Action:** Submit onboarding to land on the `DashboardScreen`.
- **Key Talking Points:**
  - "Here is the Student Explorer Dashboard. The FastAPI backend has executed our deterministic recommendation engine across 901 O*NET roles in under 45 milliseconds."
  - Point out the match percentage progress bars (e.g., 85% match for 'Data Engineers', 78% for 'Software Developers').
  - Demonstrate search filtering and RIASEC domain category chips.

---

## Scene 5: Role Details, Skill Gap Analysis & Target Career (Minute 5:00 – 6:30)
- **Action:** Click into a top-matched career role (e.g., "Data Scientists / Engineers").
- **Key Talking Points:**
  - *Tab 1 (Skills & Gap):* "CareerPath does not just give a number; it explains the score. Green chips represent verified skills the student possesses; orange chips represent missing skills prioritized by industry demand."
  - *Tab 2 (Courses & Certifications):* "Direct outbound links to Coursera, edX, AWS, and Google Cloud credentials."
  - *Tab 3 (Internships):* "Curated internship listings and application platforms."
  - *Tab 4 (Interview Questions):* "Technical interview prep questions with model answers."
  - *Action:* Tap **"Set as Target Career"**. Show the persistent banner update on the dashboard.

---

## Scene 6: AI Career Chatbot & Conclusion (Minute 6:30 – 7:00)
- **Action:** Open the Career Guidance Chatbot from the floating action button.
- **Prompt:** "What certifications should I pursue before Year 4?"
- **Speaker:** "The assistant generates semester-tailored advice taking into account the student's current year and target career."
- **Closing:** "CareerPath provides an end-to-end, secure, and explainable career intelligence roadmap for engineering students. Thank you, and I welcome your questions."

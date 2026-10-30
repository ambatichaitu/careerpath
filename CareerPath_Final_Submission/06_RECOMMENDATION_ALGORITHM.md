# CareerPath – Recommendation Algorithm Specification (Document F)

## 1. Overview
The CareerPath recommendation engine implements a pure-function, deterministic scoring and ranking algorithm designed to provide transparent, explainable career guidance to engineering students.

Unlike black-box neural networks, the algorithm is explainable, verifiable, strictly bounded between 0 and 100, and fully reproducible given identical inputs.

---

## 2. Mathematical Formulation

For a given career role $R$ and a student profile $S$:
Let:
- $T_R$ be the set of standard technical skills required by role $R$.
- $D_R$ be the set of high-demand skills required by role $R$, where $D_R \subseteq T_R$.
- $K_S$ be the set of normalized skills possessed by student $S$.

Each skill in $T_R$ is assigned an importance weight $w_i$:
$$w_i = \begin{cases} 1.25 & \text{if } s_i \in D_R \\ 1.00 & \text{if } s_i \in T_R \setminus D_R \end{cases}$$

The total available weighted score for the role is:
$$W_{\text{total}} = \sum_{s_i \in T_R} w_i$$

The student's earned weighted score is:
$$W_{\text{earned}} = \sum_{s_i \in (T_R \cap K_S)} w_i$$

### Raw Skill Match Percentage:
$$P_{\text{skill}} = \begin{cases} \left( \frac{W_{\text{earned}}}{W_{\text{total}}} \right) \times 100 & \text{if } W_{\text{total}} > 0 \\ 0 & \text{otherwise} \end{cases}$$

### Domain Interest Multiplier:
If the student specifies an interest domain (e.g., Software, Data, Mechanical) matching role $R$'s primary domain:
$$M_{\text{domain}} = \begin{cases} 1.10 & \text{if role domain matches student interest} \\ 1.00 & \text{otherwise} \end{cases}$$

### Final Composite Match Score:
$$\text{Score}(R, S) = \min(100.0, \text{round}(P_{\text{skill}} \times M_{\text{domain}}, 1))$$

---

## 3. Algorithmic Guardrails
1. **Division-by-Zero Defense:** If a role defines zero required skills ($W_{\text{total}} = 0$), the score defaults safely to $0.0\%$.
2. **Deterministic Bounded Output:** Final scores are strictly clamped to $[0.0, 100.0]$.
3. **Skill Normalization:** Before evaluation, all skills undergo trimming, lowercase conversion, and hyphen/symbol neutralization so that `"Node.js"`, `"nodejs"`, and `"Node-JS"` resolve identically.
4. **Duplicate Deduplication:** Duplicate entries in student or role skill lists are deduplicated into unique sets to prevent score inflation.

---

## 4. Priority Skill Gap Calculation
When a student matches a subset of a role's requirements, missing skills $T_R \setminus K_S$ are partitioned and ranked:
1. *Priority 1 (High Demand):* Missing skills that belong to $D_R$ (high market demand).
2. *Priority 2 (Standard Technical):* Remaining missing technical competencies.

This ensures that the student is first directed to learn the highest-leverage skills needed to bridge the qualification gap.

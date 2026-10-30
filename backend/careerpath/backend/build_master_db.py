import pandas as pd
import json

print("Loading O*NET CSV datasets...")
occ = pd.read_csv('occupation_data.csv')
sw = pd.read_csv('software_skills.csv')
ess = pd.read_csv('essential_skills.csv')
cit = pd.read_csv('career_interest_types.csv')
edu = pd.read_csv('education.csv')
te = pd.read_csv('training_and_experience.csv')

EDU_CATEGORY_MAP = {
    1.0: "Less than High School", 2.0: "High School Diploma",
    3.0: "Post-Secondary Certificate", 4.0: "Some College",
    5.0: "Associate's Degree", 6.0: "Bachelor's Degree",
    7.0: "Post-Baccalaureate Certificate", 8.0: "Master's Degree",
    9.0: "Post-Master's Certificate", 10.0: "First Professional Degree",
    11.0: "Doctoral Degree", 12.0: "Post-Doctoral Training"
}

GENERIC_TOOLS = {
    'Microsoft Word', 'Microsoft Office software', 'Microsoft Outlook',
    'Microsoft PowerPoint', 'Web browser software', 'Email software'
}

common_codes = (
    set(occ['O*NET-SOC Code']) & set(sw['O*NET-SOC Code']) &
    set(ess['O*NET-SOC Code']) & set(cit['O*NET-SOC Code']) &
    set(edu['O*NET-SOC Code']) & set(te['O*NET-SOC Code'])
)

master_roles = []
all_unique_skills = set()

for code in sorted(common_codes):
    role_row = occ[occ['O*NET-SOC Code'] == code].iloc[0]
    
    role_sw = sw[(sw['O*NET-SOC Code'] == code) & (~sw['Workplace Example'].isin(GENERIC_TOOLS))]
    in_demand = role_sw[role_sw['In Demand'] == 'Y']['Workplace Example'].unique().tolist()
    hot_tech = role_sw[role_sw['Hot Technology'] == 'Y']['Workplace Example'].unique().tolist()
    
    tech_skills = list(dict.fromkeys(in_demand + hot_tech))
    if not tech_skills:
        tech_skills = role_sw['Workplace Example'].unique().tolist()[:10]
    
    tech_skills = tech_skills[:15]
    all_unique_skills.update(tech_skills)
    
    role_ess = ess[(ess['O*NET-SOC Code'] == code) & (ess['Scale Name'] == 'Importance') & (ess['Data Value'] >= 3.5)]
    essential_list = role_ess.sort_values('Data Value', ascending=False)['Element Name'].tolist()
    
    role_cit = cit[(cit['O*NET-SOC Code'] == code) & (cit['Scale ID'] == 'OI')]
    interests = dict(zip(role_cit['Element Name'], role_cit['Data Value']))
    top_interest = max(interests, key=interests.get) if interests else "Investigative"
    
    role_edu = edu[(edu['O*NET-SOC Code'] == code) & (edu['Scale ID'] == 'RL')]
    top_edu_cat = role_edu.sort_values('Data Value', ascending=False).iloc[0]['Category'] if not role_edu.empty else 6.0

    master_roles.append({
        "onet_code": code,
        "title": role_row['Title'],
        "description": role_row['Description'],
        "primary_interest": top_interest,
        "riasec_scores": interests,
        "in_demand_skills": in_demand[:8],
        "technical_skills": tech_skills,
        "essential_skills": essential_list[:6],
        "typical_education": EDU_CATEGORY_MAP.get(top_edu_cat, "Bachelor's Degree")
    })

with open('master_roles.json', 'w', encoding='utf-8') as f:
    json.dump(master_roles, f, indent=2)

with open('skills_dictionary.json', 'w', encoding='utf-8') as f:
    json.dump(sorted(list(all_unique_skills)), f, indent=2)

print(f"Success! Saved {len(master_roles)} roles and {len(all_unique_skills)} unique technical skills.")
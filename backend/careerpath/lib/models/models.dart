class UserProfile {
  final String email;
  final String name;
  final int academicYear;
  final String interestDomain;
  final List<String> skills;
  final String collegeName;
  final String branch;
  final int? graduationYear;
  final bool onboardingCompleted;

  UserProfile({
    required this.email,
    required this.name,
    required this.academicYear,
    required this.interestDomain,
    required this.skills,
    this.collegeName = '',
    this.branch = '',
    this.graduationYear,
    this.onboardingCompleted = false,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    int parsedYear = 1;
    final rawYear = json['academic_year'];
    if (rawYear is int) {
      parsedYear = rawYear;
    } else if (rawYear is String) {
      parsedYear = int.tryParse(rawYear) ?? 1;
    }

    List<String> parsedSkills = [];
    if (json['student_skills'] is List) {
      parsedSkills = (json['student_skills'] as List).map((e) => e.toString()).toList();
    } else if (json['skills'] is List) {
      parsedSkills = (json['skills'] as List).map((e) => e.toString()).toList();
    }

    String domain = 'Software';
    if (json['interests'] is List && (json['interests'] as List).isNotEmpty) {
      domain = (json['interests'] as List).first.toString();
    } else if (json['interest_domain'] != null) {
      domain = json['interest_domain'].toString();
    }

    return UserProfile(
      email: json['email'] ?? '',
      name: json['full_name'] ?? json['name'] ?? 'Student',
      academicYear: parsedYear,
      interestDomain: domain,
      skills: parsedSkills,
      collegeName: json['college_name'] ?? '',
      branch: json['branch'] ?? '',
      graduationYear: json['graduation_year'] as int?,
      onboardingCompleted: json['onboarding_completed'] ?? (parsedSkills.isNotEmpty),
    );
  }

  Map<String, dynamic> toJson() => {
    'email': email,
    'full_name': name,
    'name': name,
    'academic_year': academicYear,
    'interest_domain': interestDomain,
    'skills': skills,
    'student_skills': skills,
    'college_name': collegeName,
    'branch': branch,
    if (graduationYear != null) 'graduation_year': graduationYear,
    'onboarding_completed': onboardingCompleted,
  };

  UserProfile copyWith({
    String? email,
    String? name,
    int? academicYear,
    String? interestDomain,
    List<String>? skills,
    String? collegeName,
    String? branch,
    int? graduationYear,
    bool? onboardingCompleted,
  }) {
    return UserProfile(
      email: email ?? this.email,
      name: name ?? this.name,
      academicYear: academicYear ?? this.academicYear,
      interestDomain: interestDomain ?? this.interestDomain,
      skills: skills ?? this.skills,
      collegeName: collegeName ?? this.collegeName,
      branch: branch ?? this.branch,
      graduationYear: graduationYear ?? this.graduationYear,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    );
  }
}

class JobRole {
  final int? roleId;
  final String onetCode;
  final String title;
  final String description;
  final String typicalEducation;
  final int readinessScore;
  final List<String> matchedSkills;
  final List<String> missingSkills;
  final List<String> essentialSkills;
  final List<String> inDemandSkills;
  final List<String> recommendedNextSkills;
  final String? domain;
  final String? explanation;
  final List<String> roadmap;
  final List<CourseItem> courses;
  final List<InternshipItem> internships;
  final List<String> interviewQuestions;

  List<String> get technicalSkills => [...matchedSkills, ...missingSkills];

  JobRole({
    this.roleId,
    required this.onetCode,
    required this.title,
    required this.description,
    required this.typicalEducation,
    required this.readinessScore,
    required this.matchedSkills,
    required this.missingSkills,
    required this.essentialSkills,
    required this.inDemandSkills,
    this.recommendedNextSkills = const [],
    this.domain,
    this.explanation,
    required this.roadmap,
    required this.courses,
    required this.internships,
    required this.interviewQuestions,
  });

  factory JobRole.fromJson(Map<String, dynamic> json) {
    int parsedScore = 0;
    if (json['readiness_score'] != null) {
      parsedScore = json['readiness_score'] is int
          ? json['readiness_score']
          : int.tryParse(json['readiness_score'].toString()) ?? 0;
    } else if (json['match_score'] != null) {
      parsedScore = json['match_score'] is int
          ? json['match_score']
          : int.tryParse(json['match_score'].toString()) ?? 0;
    }

    int? parsedRoleId;
    if (json['role_id'] != null) {
      parsedRoleId = json['role_id'] is int
          ? json['role_id']
          : int.tryParse(json['role_id'].toString());
    }

    return JobRole(
      roleId: parsedRoleId,
      onetCode: json['onet_code'] ?? 'N/A',
      title: json['title'] ?? 'Role Title',
      description: json['description'] ?? '',
      domain: json['domain'] ?? json['career_domain'] ?? '',
      typicalEducation: json['typical_education'] ?? json['education_requirements'] ?? "Bachelor's Degree",
      readinessScore: parsedScore,
      matchedSkills: (json['matched_skills'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      missingSkills: (json['missing_skills'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      essentialSkills: (json['essential_skills'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      inDemandSkills: (json['in_demand_skills'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      recommendedNextSkills: (json['recommended_next_skills'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      explanation: json['explanation'] as String?,
      roadmap: (json['roadmap'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      courses: (json['courses_and_certs'] as List<dynamic>?)?.map((e) => CourseItem.fromJson(e)).toList() ??
               (json['learning_resources'] as List<dynamic>?)?.map((e) => CourseItem.fromJson(e)).toList() ?? [],
      internships: (json['internships'] as List<dynamic>?)?.map((e) => InternshipItem.fromJson(e)).toList() ?? [],
      interviewQuestions: (json['interview_questions'] as List<dynamic>?)?.map((e) => e is Map ? (e['question_text'] ?? e.toString()).toString() : e.toString()).toList() ?? [],
    );
  }
}

class CourseItem {
  final String skill;
  final String courseTitle;
  final String platform;
  final String certification;
  final String searchUrl;

  CourseItem({
    required this.skill,
    required this.courseTitle,
    required this.platform,
    required this.certification,
    required this.searchUrl,
  });

  factory CourseItem.fromJson(Map<String, dynamic> json) {
    return CourseItem(
      skill: json['skill'] ?? '',
      courseTitle: json['course_title'] ?? json['title'] ?? '',
      platform: json['platform'] ?? 'Coursera / edX',
      certification: json['certification'] ?? json['certification_name'] ?? '',
      searchUrl: json['search_url'] ?? json['external_url'] ?? '',
    );
  }
}

class InternshipItem {
  final String role;
  final String type;
  final String applyUrl;
  final String? source;
  final String? eligibility;

  InternshipItem({
    required this.role,
    required this.type,
    required this.applyUrl,
    this.source,
    this.eligibility,
  });

  factory InternshipItem.fromJson(Map<String, dynamic> json) {
    return InternshipItem(
      role: json['role'] ?? json['role_title'] ?? '',
      type: json['type'] ?? json['description'] ?? '',
      applyUrl: json['apply_url'] ?? json['application_url'] ?? '',
      source: json['source_platform'] ?? json['source'],
      eligibility: json['eligibility'],
    );
  }
}

class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final List<dynamic>? suggestedRoles;
  final List<String>? quickReplies;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.suggestedRoles,
    this.quickReplies,
  });
}

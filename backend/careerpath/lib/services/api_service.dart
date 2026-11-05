import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/app_config.dart';
import '../models/models.dart';
import 'auth_service.dart';

class UserNotFoundException implements Exception {
  final String email;
  UserNotFoundException(this.email);
  @override
  String toString() => 'User with email $email not found.';
}

class InvalidPasswordException implements Exception {
  @override
  String toString() => 'Incorrect password entered.';
}

class UnauthorizedException implements Exception {
  final String message;
  UnauthorizedException([this.message = 'Authentication session expired. Please sign in again.']);
  @override
  String toString() => message;
}

class ForbiddenException implements Exception {
  final String message;
  ForbiddenException([this.message = 'You do not have permission to perform this action.']);
  @override
  String toString() => message;
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, [this.statusCode]);
  @override
  String toString() => message;
}

/// Central API Service for communicating with the FastAPI backend.
/// Automatically injects verified Firebase Bearer tokens into protected requests.
class ApiService {
  static final AuthService _authService = AuthService();

  /// Resolves the platform-aware backend base URL from AppConfig
  static String get baseUrl => AppConfig.backendBaseUrl;

  // Safe In-Memory Session Caches (strictly scoped to verified Firebase UID)
  static UserProfile? _cachedProfile;
  static String? _cachedProfileUid;
  static List<JobRole>? _cachedRoles;
  static String? _cachedRolesUid;
  static JobRole? _cachedSelectedCareer;
  static String? _cachedSelectedCareerUid;
  static String? _cachedProfileImageUrl;
  static String? _cachedProfileImageUid;

  /// Exposes cached selected career for fast initial UI mount
  static JobRole? get cachedSelectedCareer {
    final uid = _authService.currentUser?.uid;
    if (uid != null && _cachedSelectedCareerUid == uid) {
      return _cachedSelectedCareer;
    }
    return null;
  }

  /// Completely clears in-memory session caches on logout or account change.
  static void clearSessionCache() {
    _cachedProfile = null;
    _cachedProfileUid = null;
    _cachedRoles = null;
    _cachedRolesUid = null;
    _cachedSelectedCareer = null;
    _cachedSelectedCareerUid = null;
    _cachedProfileImageUrl = null;
    _cachedProfileImageUid = null;
  }

  /// Helper to generate authenticated HTTP headers with fresh Firebase ID token.
  static Future<Map<String, String>> _authHeaders({String? contentType = 'application/json'}) async {
    final headers = <String, String>{};
    if (contentType != null) {
      headers['Content-Type'] = contentType;
    }

    try {
      final token = await _authService.getIdToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    } catch (_) {
      // In test/mock environment, token may be null
    }

    return headers;
  }

  /// Evaluates HTTP response status and handles standard auth/error conditions.
  static void _checkResponseErrors(http.Response response, String fallbackMessage) {
    if (response.statusCode == 401) {
      throw UnauthorizedException();
    } else if (response.statusCode == 403) {
      throw ForbiddenException();
    } else if (response.statusCode >= 400) {
      try {
        final err = jsonDecode(response.body);
        throw ApiException(err['detail'] ?? fallbackMessage, response.statusCode);
      } catch (e) {
        if (e is ApiException) rethrow;
        throw ApiException('$fallbackMessage (HTTP ${response.statusCode})', response.statusCode);
      }
    }
  }

  // --------------------------------------------------------------------------
  // Stage 3: Supabase PostgreSQL Profile Endpoints
  // --------------------------------------------------------------------------

  /// Retrieves the authenticated student's profile linked to their verified Firebase UID.
  /// Returns null if the student has not completed onboarding.
  static Future<UserProfile?> getProfile({bool forceRefresh = false}) async {
    final currentUid = _authService.currentUser?.uid;
    // Serve immediately from safe in-memory session cache if valid for current student
    if (!forceRefresh && _cachedProfile != null && _cachedProfileUid == currentUid) {
      return _cachedProfile;
    }

    try {
      final headers = await _authHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/profile'),
        headers: headers,
      );

      if (response.statusCode == 404) {
        return null;
      }

      _checkResponseErrors(response, 'Failed to fetch student profile.');
      final data = jsonDecode(response.body);
      final profile = UserProfile.fromJson(data);
      if (currentUid != null) {
        _cachedProfile = profile;
        _cachedProfileUid = currentUid;
      }
      return profile;
    } catch (e) {
      if (e is UnauthorizedException || e is ForbiddenException) rethrow;
      if (e is ApiException && e.statusCode == 404) return null;
      throw ApiException('Network error fetching profile: $e');
    }
  }

  /// Checks onboarding completion state for routing decisions.
  static Future<Map<String, dynamic>> getOnboardingStatus() async {
    try {
      final headers = await _authHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/profile/onboarding-status'),
        headers: headers,
      );

      _checkResponseErrors(response, 'Failed to fetch onboarding status.');
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      if (e is UnauthorizedException || e is ForbiddenException || e is ApiException) rethrow;
      throw ApiException('Error checking onboarding status: $e');
    }
  }

  /// Upserts the student profile in Supabase PostgreSQL strictly associated with verified UID.
  static Future<UserProfile> saveStudentProfile(UserProfile profile) async {
    try {
      final headers = await _authHeaders();
      final response = await http.put(
        Uri.parse('$baseUrl/api/v1/profile'),
        headers: headers,
        body: jsonEncode({
          'full_name': profile.name,
          'college_name': profile.collegeName,
          'branch': profile.branch,
          'academic_year': profile.academicYear.toString(),
          if (profile.graduationYear != null) 'graduation_year': profile.graduationYear,
          'onboarding_completed': true,
          'student_skills': profile.skills,
          'interests': [profile.interestDomain],
        }),
      );

      _checkResponseErrors(response, 'Failed to save student profile in database.');
      final data = jsonDecode(response.body);
      final profileData = data['profile'] as Map<String, dynamic>? ?? {};
      final savedProfile = UserProfile.fromJson(profileData);
      
      // Update in-memory profile cache and invalidate recommendations cache so fresh recommendations are generated
      final currentUid = _authService.currentUser?.uid;
      if (currentUid != null) {
        _cachedProfile = savedProfile;
        _cachedProfileUid = currentUid;
        _cachedRoles = null;
        _cachedRolesUid = null;
      }
      return savedProfile;
    } catch (e) {
      if (e is UnauthorizedException || e is ForbiddenException || e is ApiException) rethrow;
      throw ApiException('Network error saving profile: $e');
    }
  }

  /// Updates confirmed student skills in normalized tables.
  static Future<void> saveStudentSkills(List<String> skills, {String source = 'manual'}) async {
    try {
      final headers = await _authHeaders();
      final response = await http.put(
        Uri.parse('$baseUrl/api/v1/profile/skills'),
        headers: headers,
        body: jsonEncode({
          'skills': skills,
          'confirmation_source': source,
        }),
      );
      _checkResponseErrors(response, 'Failed to update skills.');
      _cachedRoles = null;
      _cachedRolesUid = null;
      if (_cachedProfile != null) {
        _cachedProfile = _cachedProfile!.copyWith(skills: skills);
      }
    } catch (e) {
      if (e is UnauthorizedException || e is ForbiddenException || e is ApiException) rethrow;
      throw ApiException('Error updating skills: $e');
    }
  }

  /// Updates career domain interests.
  static Future<void> saveStudentInterests(List<String> interests) async {
    try {
      final headers = await _authHeaders();
      final response = await http.put(
        Uri.parse('$baseUrl/api/v1/profile/interests'),
        headers: headers,
        body: jsonEncode({'interests': interests}),
      );
      _checkResponseErrors(response, 'Failed to update career interests.');
      _cachedRoles = null;
      _cachedRolesUid = null;
      if (_cachedProfile != null && interests.isNotEmpty) {
        _cachedProfile = _cachedProfile!.copyWith(interestDomain: interests.first);
      }
    } catch (e) {
      if (e is UnauthorizedException || e is ForbiddenException || e is ApiException) rethrow;
      throw ApiException('Error updating interests: $e');
    }
  }

  // 1. Update Profile (Protected Endpoint - Backwards Compatibility)
  static Future<void> updateProfile(UserProfile profile) async {
    try {
      // First try the new stage 3 Supabase endpoint
      await saveStudentProfile(profile);
    } catch (_) {
      // Fallback to legacy endpoint if stage 3 endpoint unavailable
      final headers = await _authHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/update-profile'),
        headers: headers,
        body: jsonEncode({
          'email': profile.email,
          'academic_year': profile.academicYear,
          'interest_domain': profile.interestDomain,
          'skills': profile.skills,
        }),
      );
      _checkResponseErrors(response, 'Failed to update student profile.');
    }
  }

  // 2. Recommend Roles (Protected Endpoint)
  static Future<List<JobRole>> recommendRoles(UserProfile profile, {bool forceRefresh = false}) async {
    final currentUid = _authService.currentUser?.uid;
    if (!forceRefresh && _cachedRoles != null && _cachedRolesUid == currentUid && _cachedRoles!.isNotEmpty) {
      return _cachedRoles!;
    }

    try {
      // First attempt the Stage 5 authenticated recommendations endpoint
      try {
        final recData = await getRecommendations(domain: profile.interestDomain);
        final recRoles = recData['roles'] as List<JobRole>?;
        if (recRoles != null && recRoles.isNotEmpty) {
          if (currentUid != null) {
            _cachedRoles = recRoles;
            _cachedRolesUid = currentUid;
            final target = recData['selected_career'] as JobRole?;
            if (target != null) {
              _cachedSelectedCareer = target;
              _cachedSelectedCareerUid = currentUid;
            }
          }
          return recRoles;
        }
      } catch (_) {
        // Fallback to legacy endpoint if recommendations endpoint has an issue
      }

      final headers = await _authHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/recommend-roles'),
        headers: headers,
        body: jsonEncode({
          'name': profile.name,
          'academic_year': profile.academicYear,
          'interest_domain': profile.interestDomain,
          'student_skills': profile.skills,
        }),
      );

      _checkResponseErrors(response, 'Failed to fetch career recommendations.');

      final data = jsonDecode(response.body);
      final list = (data['roles'] as List<dynamic>?) ?? [];
      final roles = list.map((e) => JobRole.fromJson(e)).toList();
      if (currentUid != null) {
        _cachedRoles = roles;
        _cachedRolesUid = currentUid;
      }
      return roles;
    } catch (e) {
      if (e is UnauthorizedException || e is ForbiddenException || e is ApiException) rethrow;
      throw ApiException('Error loading career roles: $e');
    }
  }

  // 3. Parse Resume PDF (Protected Endpoint)
  static Future<List<String>> parseResumePdf(List<int> bytes, String filename) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/parse-resume'));
      final token = await _authService.getIdToken();
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      _checkResponseErrors(response, 'Could not parse resume document.');

      final data = jsonDecode(response.body);
      return (data['extracted_skills'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    } catch (e) {
      if (e is UnauthorizedException || e is ForbiddenException || e is ApiException) rethrow;
      throw ApiException('Resume extraction error: $e');
    }
  }

  // 4. Interactive AI Career Guidance Chatbot (Protected Endpoint)
  static Future<Map<String, dynamic>> careerChat({
    required String message,
    required UserProfile profile,
    List<Map<String, String>> history = const [],
  }) async {
    try {
      final headers = await _authHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/career-chat'),
        headers: headers,
        body: jsonEncode({
          'message': message,
          'academic_year': profile.academicYear,
          'interest_domain': profile.interestDomain,
          'student_skills': profile.skills,
          'conversation_history': history,
        }),
      );

      _checkResponseErrors(response, 'AI Career Advisor was unable to respond.');
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      if (e is UnauthorizedException || e is ForbiddenException || e is ApiException) rethrow;
      throw ApiException('Network error communicating with CareerPath AI: $e');
    }
  }

  // --------------------------------------------------------------------------
  // Stage 4: Secure Supabase Storage Endpoints (Resumes & Profile Images)
  // --------------------------------------------------------------------------

  /// Uploads PDF resume to private Supabase Storage, saves metadata, and extracts skills.
  static Future<Map<String, dynamic>> uploadResume(List<int> bytes, String filename) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/v1/resumes'));
      final token = await _authService.getIdToken();
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      _checkResponseErrors(response, 'Failed to upload and analyze resume.');
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      if (e is UnauthorizedException || e is ForbiddenException || e is ApiException) rethrow;
      throw ApiException('Resume upload error: $e');
    }
  }

  /// Lists private resumes uploaded by the student.
  static Future<List<Map<String, dynamic>>> listResumes() async {
    try {
      final headers = await _authHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/resumes'),
        headers: headers,
      );

      _checkResponseErrors(response, 'Failed to fetch uploaded resumes.');
      final data = jsonDecode(response.body);
      final list = (data['resumes'] as List<dynamic>?) ?? [];
      return list.map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      if (e is UnauthorizedException || e is ForbiddenException || e is ApiException) rethrow;
      throw ApiException('Error loading resumes: $e');
    }
  }

  /// Generates a short-lived download URL (60s) for an authorized resume.
  static Future<String> getResumeDownloadUrl(String resumeId) async {
    try {
      final headers = await _authHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/resumes/$resumeId/download'),
        headers: headers,
      );

      _checkResponseErrors(response, 'Failed to generate resume download link.');
      final data = jsonDecode(response.body);
      return data['download_url'] as String;
    } catch (e) {
      if (e is UnauthorizedException || e is ForbiddenException || e is ApiException) rethrow;
      throw ApiException('Error fetching download link: $e');
    }
  }

  /// Deletes a resume document from storage and metadata.
  static Future<void> deleteResume(String resumeId) async {
    try {
      final headers = await _authHeaders();
      final response = await http.delete(
        Uri.parse('$baseUrl/api/v1/resumes/$resumeId'),
        headers: headers,
      );

      _checkResponseErrors(response, 'Failed to delete resume.');
    } catch (e) {
      if (e is UnauthorizedException || e is ForbiddenException || e is ApiException) rethrow;
      throw ApiException('Error deleting resume: $e');
    }
  }

  /// Uploads PNG/JPEG profile picture to private Supabase Storage.
  static Future<Map<String, dynamic>> uploadProfileImage(List<int> bytes, String filename) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/v1/profile-image'));
      final token = await _authService.getIdToken();
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      _checkResponseErrors(response, 'Failed to upload profile picture.');
      _cachedProfileImageUrl = null;
      _cachedProfileImageUid = null;
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      if (e is UnauthorizedException || e is ForbiddenException || e is ApiException) rethrow;
      throw ApiException('Image upload error: $e');
    }
  }

  /// Retrieves short-lived signed URL for student's profile picture, or null if none set.
  static Future<String?> getProfileImageUrl({bool forceRefresh = false}) async {
    final currentUid = _authService.currentUser?.uid;
    if (!forceRefresh && _cachedProfileImageUrl != null && _cachedProfileImageUid == currentUid) {
      return _cachedProfileImageUrl;
    }

    try {
      final headers = await _authHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/profile-image'),
        headers: headers,
      );

      if (response.statusCode == 404) return null;
      _checkResponseErrors(response, 'Failed to load profile picture.');
      final data = jsonDecode(response.body);
      final url = data['image_url'] as String?;
      if (currentUid != null) {
        _cachedProfileImageUrl = url;
        _cachedProfileImageUid = currentUid;
      }
      return url;
    } catch (e) {
      if (e is UnauthorizedException || e is ForbiddenException) rethrow;
      if (e is ApiException && e.statusCode == 404) return null;
      throw ApiException('Error loading profile picture: $e');
    }
  }

  /// Removes profile picture from storage and metadata.
  static Future<void> deleteProfileImage() async {
    try {
      final headers = await _authHeaders();
      final response = await http.delete(
        Uri.parse('$baseUrl/api/v1/profile-image'),
        headers: headers,
      );

      _checkResponseErrors(response, 'Failed to remove profile picture.');
      _cachedProfileImageUrl = null;
      _cachedProfileImageUid = null;
    } catch (e) {
      if (e is UnauthorizedException || e is ForbiddenException || e is ApiException) rethrow;
      throw ApiException('Error removing profile picture: $e');
    }
  }

  // --------------------------------------------------------------------------
  // Stage 5: Career Recommendations, Gap Analysis & Career Selection
  // --------------------------------------------------------------------------

  /// Retrieves personalized recommendations based on authenticated student's profile & skills.
  static Future<Map<String, dynamic>> getRecommendations({
    String? domain,
    String? search,
    int limit = 30,
    int offset = 0,
  }) async {
    try {
      final headers = await _authHeaders();
      final queryParams = <String, String>{
        'limit': limit.toString(),
        'offset': offset.toString(),
      };
      if (domain != null && domain.isNotEmpty && domain.toLowerCase() != 'all') {
        queryParams['domain'] = domain;
      }
      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }

      final uri = Uri.parse('$baseUrl/api/v1/recommendations').replace(queryParameters: queryParams);
      final response = await http.get(uri, headers: headers);

      _checkResponseErrors(response, 'Failed to fetch recommendations.');
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final rawRoles = (data['roles'] as List<dynamic>?) ?? [];
      final roles = rawRoles.map((e) => JobRole.fromJson(e as Map<String, dynamic>)).toList();

      JobRole? selected;
      if (data['selected_career'] != null && data['selected_career'] is Map<String, dynamic>) {
        selected = JobRole.fromJson(data['selected_career'] as Map<String, dynamic>);
      }

      return {
        'roles': roles,
        'total_matching': data['total_matching'] ?? roles.length,
        'selected_career': selected,
      };
    } catch (e) {
      if (e is UnauthorizedException || e is ForbiddenException || e is ApiException) rethrow;
      throw ApiException('Error loading career recommendations: $e');
    }
  }

  /// Saves the authenticated student's selected target career role.
  static Future<Map<String, dynamic>> setSelectedCareer(dynamic roleIdOrOnet) async {
    try {
      final headers = await _authHeaders();
      final Map<String, dynamic> body = {};
      if (roleIdOrOnet is int) {
        body['role_id'] = roleIdOrOnet;
      } else {
        body['onet_code'] = roleIdOrOnet.toString();
      }

      final response = await http.put(
        Uri.parse('$baseUrl/api/v1/profile/selected-career'),
        headers: headers,
        body: jsonEncode(body),
      );

      _checkResponseErrors(response, 'Failed to save target career selection.');
      final res = jsonDecode(response.body) as Map<String, dynamic>;
      final currentUid = _authService.currentUser?.uid;
      if (currentUid != null && res['selected_career'] != null && res['selected_career'] is Map<String, dynamic>) {
        _cachedSelectedCareer = JobRole.fromJson(res['selected_career'] as Map<String, dynamic>);
        _cachedSelectedCareerUid = currentUid;
      }
      return res;
    } catch (e) {
      if (e is UnauthorizedException || e is ForbiddenException || e is ApiException) rethrow;
      throw ApiException('Error selecting career path: $e');
    }
  }

  /// Retrieves the authenticated student's selected target career role.
  static Future<Map<String, dynamic>?> getSelectedCareer() async {
    try {
      final headers = await _authHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/profile/selected-career'),
        headers: headers,
      );

      _checkResponseErrors(response, 'Failed to fetch selected career.');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['selected_career'] as Map<String, dynamic>?;
    } catch (e) {
      if (e is UnauthorizedException || e is ForbiddenException || e is ApiException) rethrow;
      throw ApiException('Error fetching selected career: $e');
    }
  }

  /// Retrieves detailed skill gap analysis for a specific career role.
  static Future<Map<String, dynamic>> getSkillGapAnalysis(String roleId) async {
    try {
      final headers = await _authHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/job-roles/$roleId/skills'),
        headers: headers,
      );

      _checkResponseErrors(response, 'Failed to load skill gap analysis.');
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      if (e is UnauthorizedException || e is ForbiddenException || e is ApiException) rethrow;
      throw ApiException('Error loading skill gap: $e');
    }
  }

  /// Retrieves learning resources and certifications for a role.
  static Future<Map<String, dynamic>> getRoleResources(String roleId) async {
    try {
      final headers = await _authHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/job-roles/$roleId/resources'),
        headers: headers,
      );

      _checkResponseErrors(response, 'Failed to load resources.');
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      if (e is UnauthorizedException || e is ForbiddenException || e is ApiException) rethrow;
      throw ApiException('Error loading resources: $e');
    }
  }

  /// Retrieves internship search streams and opportunities for a role.
  static Future<List<InternshipItem>> getRoleInternships(String roleId) async {
    try {
      final headers = await _authHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/job-roles/$roleId/internships'),
        headers: headers,
      );

      _checkResponseErrors(response, 'Failed to load internships.');
      final data = jsonDecode(response.body);
      final list = (data['internships'] as List<dynamic>?) ?? [];
      return list.map((e) => InternshipItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      if (e is UnauthorizedException || e is ForbiddenException || e is ApiException) rethrow;
      throw ApiException('Error loading internships: $e');
    }
  }

  /// Retrieves categorized interview questions for a role.
  static Future<List<String>> getRoleInterviewQuestions(String roleId) async {
    try {
      final headers = await _authHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/job-roles/$roleId/interview-questions'),
        headers: headers,
      );

      _checkResponseErrors(response, 'Failed to load interview questions.');
      final data = jsonDecode(response.body);
      final list = (data['interview_questions'] as List<dynamic>?) ?? [];
      return list.map((e) => e is Map ? (e['question_text'] ?? e.toString()).toString() : e.toString()).toList();
    } catch (e) {
      if (e is UnauthorizedException || e is ForbiddenException || e is ApiException) rethrow;
      throw ApiException('Error loading interview questions: $e');
    }
  }
}

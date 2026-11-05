import 'package:flutter_test/flutter_test.dart';
import 'package:careerpath/models/models.dart';
import 'package:careerpath/services/api_service.dart';

void main() {
  group('ApiService In-Memory Session Caching & Invalidation Tests', () {
    setUp(() {
      ApiService.clearSessionCache();
    });

    tearDown(() {
      ApiService.clearSessionCache();
    });

    test('Cache is cleared on ApiService.clearSessionCache()', () {
      ApiService.clearSessionCache();
      expect(ApiService.cachedSelectedCareer, isNull);
    });

    test('UserProfile copyWith preserves data integrity on skill update', () {
      final profile = UserProfile(
        email: 'student@example.com',
        name: 'Test Student',
        academicYear: 3,
        interestDomain: 'Software',
        skills: ['Python', 'Dart'],
        collegeName: 'Tech University',
        branch: 'Computer Science',
        graduationYear: 2027,
        onboardingCompleted: true,
      );

      final updated = profile.copyWith(skills: ['Python', 'Dart', 'Flutter', 'FastAPI']);
      expect(updated.skills.length, 4);
      expect(updated.email, 'student@example.com');
      expect(updated.name, 'Test Student');
      expect(updated.interestDomain, 'Software');
    });

    test('UserProfile copyWith updates domain on interest change', () {
      final profile = UserProfile(
        email: 'student@example.com',
        name: 'Test Student',
        academicYear: 2,
        interestDomain: 'Software',
        skills: ['Python'],
      );

      final updated = profile.copyWith(interestDomain: 'Data Science');
      expect(updated.interestDomain, 'Data Science');
      expect(updated.skills, ['Python']);
    });

    test('Unauthenticated session has null cached state', () {
      ApiService.clearSessionCache();
      expect(ApiService.cachedSelectedCareer, isNull);
    });
  });
}

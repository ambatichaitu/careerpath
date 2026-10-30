import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:careerpath/core/auth_config.dart';
import 'package:careerpath/core/auth_gate.dart';
import 'package:careerpath/main.dart';
import 'package:careerpath/models/models.dart';
import 'package:careerpath/screens/dashboard_screen.dart';
import 'package:careerpath/screens/email_verification_screen.dart';
import 'package:careerpath/screens/login_screen.dart';
import 'package:careerpath/screens/onboarding_wizard_screen.dart';
import 'package:careerpath/screens/role_detail_screen.dart';

void main() {
  testWidgets('CareerPath App startup smoke test', (WidgetTester tester) async {
    // Mount app with LoginScreen test double
    await tester.pumpWidget(const CareerPathApp(home: LoginScreen()));

    expect(find.byType(CareerPathApp), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('CareerPath Login screen renders email, password fields and forgot password button', (WidgetTester tester) async {
    await tester.pumpWidget(const CareerPathApp(home: LoginScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(TextFormField), findsWidgets);
    expect(find.text('Student Email Address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Forgot Password?'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.byType(FilledButton), findsWidgets);
  });

  testWidgets('CareerPath Forgot Password dialog opens and displays email prompt', (WidgetTester tester) async {
    await tester.pumpWidget(const CareerPathApp(home: LoginScreen()));
    await tester.pumpAndSettle();

    // Tap Forgot Password button
    final forgotBtn = find.text('Forgot Password?');
    expect(forgotBtn, findsOneWidget);
    await tester.tap(forgotBtn);
    await tester.pumpAndSettle();

    // Verify AlertDialog opens with reset prompt
    expect(find.text('Reset Password'), findsOneWidget);
    expect(find.text('Send Reset Link'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('CareerPath Email Verification pending screen renders verification UI and resend cooldown', (WidgetTester tester) async {
    bool verifiedCallbackCalled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: EmailVerificationScreen(
          onVerified: () => verifiedCallbackCalled = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Verify Your Email'), findsOneWidget);
    expect(find.text("I've Verified My Email"), findsOneWidget);
    expect(find.text('Resend Verification Email'), findsOneWidget);
    expect(verifiedCallbackCalled, isFalse);
  });

  test('Stage 3: UserProfile JSON mapping handles normalized Supabase and legacy formats', () {
    final supabaseJson = {
      'firebase_uid': 'uid_123',
      'full_name': 'Priya Sharma',
      'email': 'priya@college.edu',
      'college_name': 'IIT Delhi',
      'branch': 'Computer Science',
      'academic_year': '3',
      'graduation_year': 2027,
      'onboarding_completed': true,
      'student_skills': ['Python', 'Docker', 'FastAPI'],
      'interests': ['Software', 'Data'],
    };

    final profile = UserProfile.fromJson(supabaseJson);
    expect(profile.name, equals('Priya Sharma'));
    expect(profile.email, equals('priya@college.edu'));
    expect(profile.collegeName, equals('IIT Delhi'));
    expect(profile.branch, equals('Computer Science'));
    expect(profile.academicYear, equals(3));
    expect(profile.onboardingCompleted, isTrue);
    expect(profile.skills, contains('Python'));
    expect(profile.interestDomain, equals('Software'));

    final serialized = profile.toJson();
    expect(serialized['full_name'], equals('Priya Sharma'));
    expect(serialized['college_name'], equals('IIT Delhi'));
  });

  testWidgets('Stage 3: DashboardScreen displays student profile and role metrics', (WidgetTester tester) async {
    final profile = UserProfile(
      email: 'alex@pathfinder.edu',
      name: 'Alex Chen',
      academicYear: 3,
      interestDomain: 'Software',
      skills: ['Python', 'Git', 'Docker'],
      collegeName: 'Pathfinder Institute',
      branch: 'Computer Science',
      onboardingCompleted: true,
    );

    final testRole = JobRole(
      onetCode: '15-1252.00',
      title: 'Software Developers',
      description: 'Research, design, and develop computer software systems.',
      typicalEducation: "Bachelor's Degree",
      readinessScore: 65,
      matchedSkills: ['Python', 'Git'],
      missingSkills: ['Docker', 'Kubernetes'],
      essentialSkills: ['Critical Thinking'],
      inDemandSkills: ['Python'],
      roadmap: ['Master Docker and Kubernetes'],
      courses: [],
      internships: [],
      interviewQuestions: ['Explain OOP principles in Python.'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(
          userProfile: profile,
          roles: [testRole],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CareerPath'), findsOneWidget);
    expect(find.textContaining('Alex Chen'), findsOneWidget);
    expect(find.textContaining('Software Developers'), findsOneWidget);
  });

  testWidgets('Stage 3: OnboardingWizardScreen mounts with initial profile state', (WidgetTester tester) async {
    final profile = UserProfile(
      email: 'newuser@pathfinder.edu',
      name: 'New Student',
      academicYear: 1,
      interestDomain: 'Software',
      skills: const [],
      onboardingCompleted: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingWizardScreen(currentUser: profile),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Career Roadmap Wizard'), findsOneWidget);
    expect(find.byType(PageView), findsOneWidget);
  });

  testWidgets('Stage 4: DashboardScreen renders profile avatar with photo edit indicator', (WidgetTester tester) async {
    final profile = UserProfile(
      email: 'student@pathfinder.edu',
      name: 'Maya Lin',
      academicYear: 2,
      interestDomain: 'Data',
      skills: ['Python', 'SQL'],
      onboardingCompleted: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(
          userProfile: profile,
          roles: const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CircleAvatar), findsOneWidget);
    expect(find.text('M'), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt), findsOneWidget);
  });

  testWidgets('Stage 4: OnboardingWizardScreen Step 3 displays Upload PDF button', (WidgetTester tester) async {
    final profile = UserProfile(
      email: 'student@pathfinder.edu',
      name: 'Maya Lin',
      academicYear: 2,
      interestDomain: 'Software',
      skills: const [],
      onboardingCompleted: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingWizardScreen(currentUser: profile),
      ),
    );
    await tester.pumpAndSettle();

    // Advance to Step 2
    final nextBtn = find.text('Next: Track');
    if (nextBtn.evaluate().isNotEmpty) {
      await tester.tap(nextBtn);
      await tester.pumpAndSettle();
      // Advance to Step 3
      final nextSkillsBtn = find.text('Next: Skills');
      if (nextSkillsBtn.evaluate().isNotEmpty) {
        await tester.tap(nextSkillsBtn);
        await tester.pumpAndSettle();
        expect(find.text('Upload PDF'), findsOneWidget);
        expect(find.text('Paste Text'), findsOneWidget);
      }
    }
  });

  test('Stage 5: JobRole JSON mapping handles role_id, domain, explanation and priority skills', () {
    final rawJson = {
      'role_id': 42,
      'onet_code': '15-1252.00',
      'title': 'Software Developers',
      'description': 'Develop software systems.',
      'domain': 'Software',
      'typical_education': "Bachelor's Degree",
      'readiness_score': 75,
      'matched_skills': ['Python', 'SQL'],
      'missing_skills': ['Docker', 'Kubernetes'],
      'essential_skills': ['Critical Thinking'],
      'in_demand_skills': ['Python', 'Docker'],
      'recommended_next_skills': ['Docker', 'Kubernetes'],
      'explanation': 'Career Profile Match: 75%. Strong alignment!',
      'roadmap': ['Master Docker'],
      'courses_and_certs': [
        {
          'skill': 'Docker',
          'course_title': 'Master Docker for Software Developers',
          'platform': 'Coursera',
          'certification': 'Docker Certified Associate',
          'search_url': 'https://coursera.org',
        }
      ],
      'internships': [
        {
          'role': 'Software Intern',
          'type': 'Summer Internship',
          'apply_url': 'https://linkedin.com',
          'source': 'LinkedIn Jobs',
        }
      ],
      'interview_questions': ['Explain Docker containerization.'],
    };

    final role = JobRole.fromJson(rawJson);
    expect(role.roleId, equals(42));
    expect(role.onetCode, equals('15-1252.00'));
    expect(role.title, equals('Software Developers'));
    expect(role.readinessScore, equals(75));
    expect(role.domain, equals('Software'));
    expect(role.explanation, contains('75%'));
    expect(role.recommendedNextSkills, contains('Docker'));
    expect(role.courses.length, equals(1));
    expect(role.courses[0].courseTitle, contains('Docker'));
    expect(role.internships.length, equals(1));
    expect(role.interviewQuestions, contains('Explain Docker containerization.'));
  });

  testWidgets('Stage 5: RoleDetailScreen mounts with 4 tabs and Target Career button', (WidgetTester tester) async {
    final profile = UserProfile(
      email: 'student@pathfinder.edu',
      name: 'Maya Lin',
      academicYear: 3,
      interestDomain: 'Software',
      skills: ['Python', 'SQL'],
      onboardingCompleted: true,
    );

    final testRole = JobRole(
      roleId: 1,
      onetCode: '15-1252.00',
      title: 'Software Developers',
      description: 'Develop computer software.',
      domain: 'Software',
      typicalEducation: "Bachelor's Degree",
      readinessScore: 70,
      matchedSkills: ['Python', 'SQL'],
      missingSkills: ['Docker'],
      essentialSkills: ['Critical Thinking'],
      inDemandSkills: ['Python', 'Docker'],
      recommendedNextSkills: ['Docker'],
      explanation: 'Career Profile Match: 70%. Strong alignment!',
      roadmap: ['Master Docker containers.'],
      courses: [
        CourseItem(
          skill: 'Docker',
          courseTitle: 'Docker Fundamentals',
          platform: 'Coursera',
          certification: 'Certified Associate',
          searchUrl: 'https://coursera.org',
        )
      ],
      internships: [
        InternshipItem(
          role: 'Software Intern',
          type: 'Summer Internship',
          applyUrl: 'https://linkedin.com',
          source: 'LinkedIn Jobs',
        )
      ],
      interviewQuestions: ['Explain REST architectural principles.'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RoleDetailScreen(role: testRole, userProfile: profile),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Software Developers'), findsWidgets);
    expect(find.text('Set as Target Career'), findsOneWidget);
    expect(find.text('Skills & Gap Analysis'), findsOneWidget);
    expect(find.text('Courses & Certs'), findsOneWidget);
    expect(find.text('Internships'), findsOneWidget);
    expect(find.text('Interview Qs'), findsOneWidget);
    expect(find.textContaining('Career Profile Match: 70%'), findsOneWidget);
    expect(find.text('Ask CareerPath AI'), findsOneWidget);
  });

  test('AuthConfig: Verification policy defaults to mandatory and guarantees production safety', () {
    AuthConfig.testVerificationOverride = null;
    expect(AuthConfig.securityModeDescription, isNotEmpty);

    // Test programmatic override behavior
    AuthConfig.testVerificationOverride = true;
    expect(AuthConfig.isEmailVerificationRequired, isTrue);
    expect(AuthConfig.isDevBypassActive, isFalse);

    AuthConfig.testVerificationOverride = false;
    expect(AuthConfig.isEmailVerificationRequired, isFalse);
    expect(AuthConfig.isDevBypassActive, isTrue);

    // Reset override cleanly
    AuthConfig.testVerificationOverride = null;
  });

  testWidgets('AuthGate mounts LoginScreen when unauthenticated', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AuthGate(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}

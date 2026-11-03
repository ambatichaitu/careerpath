import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../screens/dashboard_screen.dart';
import '../screens/email_verification_screen.dart';
import '../screens/login_screen.dart';
import '../screens/onboarding_wizard_screen.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'auth_config.dart';

/// Central Authentication Gate for CareerPath (Stage 3).
/// Listens to Firebase Auth state stream and routes accordingly:
/// - State A: Initializing -> Spinner
/// - State B: Unauthenticated -> LoginScreen
/// - State C: Authenticated but email not yet verified -> EmailVerificationScreen
/// - State D: Authenticated & verified:
///     - No profile / incomplete profile -> OnboardingWizardScreen
///     - Completed profile in Supabase -> DashboardScreen
///     - Backend unavailable -> Retry Screen with retry / sign-out
class AuthGate extends StatefulWidget {
  final AuthService? authService;

  const AuthGate({super.key, this.authService});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AuthService _authService;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authService.authStateChanges,
      builder: (context, snapshot) {
        // State A: Authentication initializing
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppTheme.primaryIndigo),
            ),
          );
        }

        final user = snapshot.data;

        // State B: No authenticated user
        if (user == null) {
          return const LoginScreen();
        }

        final activeUser = _authService.currentUser ?? user;

        // State C: Authenticated but email not yet verified.
        // Strictly mandatory: unverified accounts are blocked at EmailVerificationScreen
        // and cannot access onboarding, dashboard, or career recommendations.
        // Google Sign-In users are automatically verified by Google's OAuth identity.
        if (!activeUser.emailVerified && AuthConfig.isEmailVerificationRequired) {
          return EmailVerificationScreen(
            onVerified: () => setState(() {}),
          );
        }

        // State D: Authenticated & verified student session loader
        return _StudentSessionLoader(
          key: ValueKey(activeUser.uid),
          user: activeUser,
          authService: _authService,
        );
      },
    );
  }
}

class _SessionPayload {
  final UserProfile profile;
  final List<JobRole> roles;
  final bool needsOnboarding;

  _SessionPayload({
    required this.profile,
    required this.roles,
    required this.needsOnboarding,
  });
}

class _StudentSessionLoader extends StatefulWidget {
  final User user;
  final AuthService authService;

  const _StudentSessionLoader({
    super.key,
    required this.user,
    required this.authService,
  });

  @override
  State<_StudentSessionLoader> createState() => _StudentSessionLoaderState();
}

class _StudentSessionLoaderState extends State<_StudentSessionLoader> {
  late Future<_SessionPayload> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = _fetchSession();
    });
  }

  Future<_SessionPayload> _fetchSession() async {
    final user = widget.user;
    try {
      final profile = await ApiService.getProfile();
      if (profile == null || !profile.onboardingCompleted) {
        final fallback = profile ??
            UserProfile(
              email: user.email ?? '',
              name: user.displayName?.isNotEmpty == true
                  ? user.displayName!
                  : 'Student',
              academicYear: 1,
              interestDomain: 'Software',
              skills: const [],
              onboardingCompleted: false,
            );
        return _SessionPayload(
          profile: fallback,
          roles: const [],
          needsOnboarding: true,
        );
      }

      final roles = await ApiService.recommendRoles(profile);
      return _SessionPayload(
        profile: profile,
        roles: roles,
        needsOnboarding: false,
      );
    } catch (e) {
      // Re-throw so FutureBuilder catches backend error and shows Retry Screen
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_SessionPayload>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppTheme.primaryIndigo),
                  SizedBox(height: 16),
                  Text(
                    'Loading CareerPath profile...',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cloud_off_rounded,
                        size: 56, color: AppTheme.accentRose),
                    const SizedBox(height: 16),
                    Text(
                      'Connection Notice',
                      style: AppTheme.fontHeading(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Unable to communicate with the backend database. Please ensure the server is active.',
                      textAlign: TextAlign.center,
                      style: AppTheme.fontBody(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry Connection'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => widget.authService.signOut(),
                      child: const Text('Sign Out'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final payload = snapshot.data!;
        if (payload.needsOnboarding) {
          return OnboardingWizardScreen(currentUser: payload.profile);
        } else {
          return DashboardScreen(
            userProfile: payload.profile,
            roles: payload.roles,
          );
        }
      },
    );
  }
}

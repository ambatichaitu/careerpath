import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../core/auth_config.dart';

/// Reusable Firebase Authentication Service for CareerPath.
/// Provides centralized user lifecycle management, session streams, and ID token retrieval.
class AuthService {
  final FirebaseAuth? _customAuth;

  /// Allows injecting a mock FirebaseAuth instance for unit testing.
  AuthService({FirebaseAuth? auth}) : _customAuth = auth;

  FirebaseAuth get _auth {
    if (_customAuth != null) return _customAuth;
    return FirebaseAuth.instance;
  }

  /// Current authenticated Firebase user.
  User? get currentUser {
    try {
      return _auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  /// Stream of authentication state changes.
  Stream<User?> get authStateChanges {
    try {
      return _auth.authStateChanges();
    } catch (_) {
      return const Stream.empty();
    }
  }

  /// Whether current user's email is verified.
  bool get isEmailVerified => currentUser?.emailVerified ?? false;

  /// Register a new student with email and password.
  /// Automatically dispatches an email verification link upon successful creation.
  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );

      // Automatically dispatch verification email
      try {
        await credential.user?.sendEmailVerification();
      } catch (e) {
        debugPrint('Notice during registration email verification dispatch: $e');
        if (AuthConfig.isEmailVerificationRequired) {
          rethrow;
        }
      }
      return credential;
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseAuthError(e);
    } catch (e) {
      throw Exception('Registration failed: ${e.toString()}');
    }
  }

  /// Sign in an existing student with email and password.
  Future<UserCredential> loginWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      return credential;
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseAuthError(e);
    } catch (e) {
      throw Exception('Login failed: ${e.toString()}');
    }
  }

  /// Sign in using Google Sign-In via Firebase Authentication.
  /// Works across Flutter Web (popup) and Android/Desktop (provider redirect).
  /// Google-authenticated accounts are pre-verified by Google (emailVerified: true).
  Future<UserCredential> signInWithGoogle() async {
    try {
      final googleProvider = GoogleAuthProvider();
      googleProvider.addScope('email');
      googleProvider.addScope('profile');

      if (kIsWeb) {
        return await _auth.signInWithPopup(googleProvider);
      } else {
        return await _auth.signInWithProvider(googleProvider);
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'account-exists-with-different-credential') {
        throw Exception(
          'An account already exists with this email address under a password. '
          'Please sign in with your email and password.',
        );
      }
      throw _mapFirebaseAuthError(e);
    } catch (e) {
      throw Exception('Google sign-in failed: ${e.toString()}');
    }
  }

  /// Safely links an existing authenticated account with Google credentials.
  /// Preserves the student's existing Firebase UID and associated Supabase records.
  Future<UserCredential> linkWithGoogle() async {
    final user = currentUser;
    if (user == null) throw Exception('No authenticated user found to link.');

    try {
      final googleProvider = GoogleAuthProvider();
      if (kIsWeb) {
        return await user.linkWithPopup(googleProvider);
      } else {
        return await user.linkWithProvider(googleProvider);
      }
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseAuthError(e);
    }
  }

  /// Send verification email to current student using normal Firebase verification flow.
  Future<void> sendVerificationEmail() async {
    final initialUser = currentUser;
    if (initialUser == null) {
      throw Exception('No authenticated student session found. Please sign in first.');
    }

    try {
      // Refresh user metadata to verify session freshness
      await initialUser.reload();
    } catch (e) {
      debugPrint('Notice during user reload before verification send: $e');
    }

    final activeUser = currentUser ?? initialUser;
    if (activeUser.emailVerified) {
      throw Exception('This account is already verified.');
    }

    try {
      await activeUser.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseAuthError(e);
    } catch (e) {
      throw Exception('Failed to send verification email: ${e.toString()}');
    }
  }

  /// Apply an out-of-band action code (e.g. from an email verification link).
  Future<void> applyActionCode(String code) async {
    try {
      await _auth.applyActionCode(code.trim());
      await reloadCurrentUser();
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseAuthError(e);
    }
  }

  /// Verify email using an out-of-band code or pasted verification link.
  /// Handles full URLs, query parameter extraction, and entity-decoded ampersands.
  Future<bool> verifyEmailWithCode(String codeOrUrl) async {
    String code = codeOrUrl.trim();
    // Normalize any HTML entity-encoded ampersands
    code = code.replaceAll('&amp;', '&');

    if (code.contains('oobCode=')) {
      final uri = Uri.tryParse(code);
      if (uri != null && uri.queryParameters.containsKey('oobCode')) {
        code = uri.queryParameters['oobCode']!;
      } else {
        // Fallback regex extraction if full URI parsing fails due to URL wrapping
        final match = RegExp(r'oobCode=([^&]+)').firstMatch(code);
        if (match != null) {
          code = match.group(1)!;
        }
      }
    }

    await applyActionCode(code);
    final user = await reloadCurrentUser();
    return user?.emailVerified ?? false;
  }

  /// Reload current user profile to fetch fresh email verification and claims.
  Future<User?> reloadCurrentUser() async {
    final user = currentUser;
    if (user != null) {
      await user.reload();
      return currentUser;
    }
    return null;
  }

  /// Send password reset link directly to student's email inbox.
  Future<void> sendPasswordResetEmail({required String email}) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseAuthError(e);
    }
  }

  /// Re-authenticate user before executing sensitive actions like password change.
  Future<void> reauthenticateUser({
    required String email,
    required String password,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('No authenticated user found.');

    try {
      final cred = EmailAuthProvider.credential(
        email: email.trim().toLowerCase(),
        password: password,
      );
      await user.reauthenticateWithCredential(cred);
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseAuthError(e);
    }
  }

  /// Update password for the currently authenticated user.
  Future<void> updatePassword({required String newPassword}) async {
    final user = currentUser;
    if (user == null) throw Exception('No authenticated user found.');

    try {
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseAuthError(e);
    }
  }

  /// Retrieve the current Firebase ID Token (JWT) for FastAPI backend authorization.
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    final user = currentUser;
    if (user == null) return null;
    return await user.getIdToken(forceRefresh);
  }

  /// Sign out the current user and clear local session state.
  Future<void> logout() async {
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('Logout notice: $e');
    }
  }

  /// Alias for logout() conforming to standard naming.
  Future<void> signOut() => logout();

  /// Maps technical Firebase error codes to student-friendly messages.
  String _mapFirebaseAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found with this email. Please register first.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password. Please verify your credentials.';
      case 'email-already-in-use':
        return 'An account already exists with this email. Please log in.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password is too weak. Please use at least 6 characters.';
      case 'user-disabled':
        return 'This account has been temporarily disabled. Contact support.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'Network connection error. Please verify your internet connection.';
      case 'requires-recent-login':
        return 'For security, please re-login before updating your password.';
      case 'api-key-not-valid':
      case 'invalid-api-key':
        return 'Firebase configuration error: The API key is invalid. Please link your project with flutterfire configure.';
      case 'app-not-authorized':
        return 'Firebase configuration error: This app is not authorized to use Firebase Authentication.';
      default:
        return e.message ?? 'Authentication error occurred (${e.code}).';
    }
  }
}

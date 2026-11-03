import 'package:flutter/foundation.dart';

/// Centralized authentication and environment configuration for CareerPath.
///
/// Controls environment-specific security policies.
class AuthConfig {
  /// Internal test override to allow widget and unit tests to verify
  /// verification policy enforcement deterministically.
  @visibleForTesting
  static bool? testVerificationOverride;

  /// Compile-time configuration for mandatory email verification.
  /// Mandatory (`true`) by default for production security.
  static const bool _requireEmailVerification = bool.fromEnvironment(
    'REQUIRE_EMAIL_VERIFICATION',
    defaultValue: true,
  );

  /// Whether email verification is mandatory for the current session.
  ///
  /// POLICY:
  /// - Mandatory (`true`) in production and release builds.
  /// - Unverified email/password users are prevented from accessing onboarding,
  ///   dashboard, career recommendations, or other protected features.
  /// - Google Sign-In users whose Firebase identity is verified proceed normally.
  static bool get isEmailVerificationRequired {
    if (testVerificationOverride != null) {
      return testVerificationOverride!;
    }
    return _requireEmailVerification;
  }

  /// Whether test bypass is active (used by automated tests only).
  static bool get isDevBypassActive => !isEmailVerificationRequired;

  /// Human-readable descriptor of the current security mode for logs.
  static String get securityModeDescription {
    if (isEmailVerificationRequired) {
      return 'ENFORCED (Email verification strictly mandatory)';
    }
    return 'TEST_OVERRIDE (Email verification bypassed for testing)';
  }
}

import 'package:flutter/foundation.dart';

/// Centralized authentication and environment configuration for CareerPath.
///
/// Controls environment-specific security policies.
class AuthConfig {
  /// Internal test override to allow widget and unit tests to verify both
  /// enforced and optional verification modes deterministically.
  @visibleForTesting
  static bool? testVerificationOverride;

  /// Compile-time configuration for mandatory email verification.
  /// Defaults to `true` for standard production safety.
  ///
  /// Can be explicitly set to `false` for academic demonstrations or institutional
  /// testing where college mail servers delay/filter verification emails:
  /// `--dart-define=REQUIRE_EMAIL_VERIFICATION=false`
  static const bool _requireEmailVerification = bool.fromEnvironment(
    'REQUIRE_EMAIL_VERIFICATION',
    defaultValue: true,
  );

  /// Whether email verification is mandatory for the current session.
  ///
  /// POLICY:
  /// - Defaults to `true` (mandatory email verification).
  /// - Can be explicitly configured to `false` at build time via:
  ///   `--dart-define=REQUIRE_EMAIL_VERIFICATION=false`
  static bool get isEmailVerificationRequired {
    if (testVerificationOverride != null) {
      return testVerificationOverride!;
    }
    return _requireEmailVerification;
  }

  /// Whether optional email verification mode is active.
  static bool get isDevBypassActive => !isEmailVerificationRequired;

  /// Human-readable descriptor of the current security mode for logs.
  static String get securityModeDescription {
    if (isEmailVerificationRequired) {
      return 'ENFORCED (Email verification strictly mandatory)';
    }
    return 'OPTIONAL (Configured via REQUIRE_EMAIL_VERIFICATION=false; authentic Firebase Auth token required)';
  }
}

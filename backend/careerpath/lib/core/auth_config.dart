import 'package:flutter/foundation.dart';

/// Centralized authentication and environment configuration for CareerPath.
///
/// Controls environment-specific security policies.
class AuthConfig {
  /// Internal test override to allow widget and unit tests to verify both
  /// enforced and development bypass modes deterministically.
  @visibleForTesting
  static bool? testVerificationOverride;

  /// Compile-time development bypass flags passed via:
  /// `--dart-define=BYPASS_EMAIL_VERIFICATION_DEV=true` or
  /// `--dart-define=ALLOW_UNVERIFIED_EMAIL_DEV=true`
  ///
  /// Defaults to `false` (disabled).
  static const bool _devBypassFlag = bool.fromEnvironment(
        'BYPASS_EMAIL_VERIFICATION_DEV',
        defaultValue: false,
      ) ||
      bool.fromEnvironment(
        'ALLOW_UNVERIFIED_EMAIL_DEV',
        defaultValue: false,
      );

  /// Whether email verification is mandatory for the current session.
  ///
  /// CRITICAL SECURITY GUARANTEES:
  /// 1. In Release builds (`kReleaseMode == true`):
  ///    ALWAYS returns `true`. It is architecturally and mathematically
  ///    impossible to activate the bypass in production or release binaries.
  /// 2. In Development / Debug / Profile builds:
  ///    Defaults to `true` (verification mandatory).
  ///    Returns `false` ONLY IF explicitly enabled via the compile-time flag.
  static bool get isEmailVerificationRequired {
    if (testVerificationOverride != null) {
      return testVerificationOverride!;
    }

    // Release build guarantee: strictly enforced regardless of flags
    if (kReleaseMode) {
      return true;
    }

    // In development builds: bypass active only when explicitly passed
    return !_devBypassFlag;
  }

  /// Whether the development-only unverified email mode is active.
  static bool get isDevBypassActive => !isEmailVerificationRequired;

  /// Human-readable descriptor of the current security mode for logs.
  static String get securityModeDescription {
    if (kReleaseMode) {
      return 'PRODUCTION (Mandatory email verification strictly enforced)';
    }
    if (_devBypassFlag) {
      return 'DEVELOPMENT (Bypass active via --dart-define=BYPASS_EMAIL_VERIFICATION_DEV=true)';
    }
    return 'DEVELOPMENT (Email verification mandatory by default; flag not set)';
  }
}

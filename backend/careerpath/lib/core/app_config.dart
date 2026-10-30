import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Central application configuration for CareerPath.
/// Provides platform-aware, physical-device-compatible, and build-configurable environment constants.
class AppConfig {
  static const String appName = 'CareerPath';
  static const String appVersion = '1.0.0';

  // Support build-time overrides:
  // e.g. flutter run --dart-define=BACKEND_URL=https://api.careerpath.example.com
  static const String _envBackendUrl = String.fromEnvironment('BACKEND_URL');

  // Candidate URLs for local and physical device development:
  // - 127.0.0.1:8000: ADB reverse on physical phone, web, or desktop
  // - 192.168.1.5:8000: Local Wi-Fi LAN IP (for physical phone over Wi-Fi)
  // - 10.0.2.2:8000: Android Emulator virtual loopback
  static const String defaultLocalUrl = 'http://127.0.0.1:8000';
  static const String defaultLanUrl = 'http://192.168.1.5:8000';
  static const String defaultEmulatorUrl = 'http://10.0.2.2:8000';

  static String _cachedBaseUrl = '';

  /// Resolves the appropriate backend base URL synchronously:
  /// Prioritizes cached probed URL, then build-time override, then default local URL.
  static String get backendBaseUrl {
    if (_cachedBaseUrl.isNotEmpty) {
      return _cachedBaseUrl;
    }
    if (_envBackendUrl.isNotEmpty) {
      return _envBackendUrl;
    }
    if (kIsWeb) {
      return defaultLocalUrl;
    }
    // Default to 127.0.0.1:8000, which works seamlessly with ADB reverse on physical phones
    return defaultLocalUrl;
  }

  /// Sets or overrides the active base URL
  static void setBackendBaseUrl(String url) {
    _cachedBaseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// Dynamically probes available candidate endpoints and caches the responsive URL.
  /// Guarantees that physical devices (Samsung S24 Ultra) and emulators connect reliably.
  static Future<String> resolveBackendBaseUrl() async {
    if (_cachedBaseUrl.isNotEmpty) {
      return _cachedBaseUrl;
    }

    if (_envBackendUrl.isNotEmpty) {
      _cachedBaseUrl = _envBackendUrl.endsWith('/')
          ? _envBackendUrl.substring(0, _envBackendUrl.length - 1)
          : _envBackendUrl;
      return _cachedBaseUrl;
    }

    if (kIsWeb) {
      _cachedBaseUrl = defaultLocalUrl;
      return _cachedBaseUrl;
    }

    // Candidate endpoints to probe in order of priority:
    final candidates = [
      defaultLocalUrl,     // 127.0.0.1:8000 (ADB reverse on physical phone / desktop)
      defaultLanUrl,       // 192.168.1.5:8000 (Local Wi-Fi LAN connection from physical phone)
      defaultEmulatorUrl,  // 10.0.2.2:8000 (Android Emulator virtual loopback fallback)
    ];

    for (final url in candidates) {
      try {
        final uri = Uri.parse('$url/');
        final res = await http.get(uri).timeout(const Duration(milliseconds: 650));
        if (res.statusCode == 200) {
          _cachedBaseUrl = url;
          debugPrint('[AppConfig] Connected to responsive backend at: $url');
          return _cachedBaseUrl;
        }
      } catch (_) {
        // Candidate not responsive, try next
      }
    }

    // Default fallback to 127.0.0.1:8000 for physical phone with reverse port forwarding
    _cachedBaseUrl = defaultLocalUrl;
    return _cachedBaseUrl;
  }
}

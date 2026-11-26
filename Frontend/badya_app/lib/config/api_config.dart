import 'dart:io';
import 'package:flutter/foundation.dart';

class ApiConfig {
  // ─── AI Backend Server ─────────────────────────────────────────────

  static const String hostIp = String.fromEnvironment(
    'API_HOST_IP',
    defaultValue: 'localhost',
  );

  static const String apiPort = String.fromEnvironment(
    'API_PORT',
    defaultValue: '8000',
  );

  static const String googleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue: 'YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com',
  );

  /// Cloud Run / production URL for the AI backend (agents, imports, recommendations)
  static const String productionBaseUrl = String.fromEnvironment(
    'PRODUCTION_BASE_URL',
    defaultValue: 'https://api.yourdomain.com',
  );

  /// Get the appropriate AI backend base URL based on platform and environment.
  /// In release mode, always points to the Cloud Run backend.
  /// In debug mode, resolves to the local dev server.
  static String getBaseUrl() =>
      _resolveUrl(hostIp: hostIp, apiPort: apiPort, productionUrl: productionBaseUrl);

  // ─── Recommendation / Import Service (same backend) ────────────────
  // Recommendation, import, and transcript routes are served by the same
  // Cloud Run service as the AI agents. These getters are kept as
  // readability aliases over getBaseUrl().

  /// Base URL for recommendation & import endpoints — same service as getBaseUrl().
  static String getRecommendationsBaseUrl() => getBaseUrl();

  /// Recommendations API endpoint.
  static String get recommendationsUrl =>
      '${getRecommendationsBaseUrl()}/recommendations/';

  /// Import API endpoint.
  static String get contentServiceImportUrl =>
      '${getRecommendationsBaseUrl()}/import';

  /// Import endpoints tried in order.
  /// Debug builds also fall back to the physical-device LAN server;
  /// release builds use the single production URL.
  static List<String> get contentServiceImportUrls => kDebugMode
      ? [
          '${getRecommendationsBaseUrl()}/import',
          'http://$hostIp:$apiPort/import',
        ]
      : ['${getRecommendationsBaseUrl()}/import'];

  // ─── Private Helpers ──────────────────────────────────────────────

  /// Resolve a server URL based on platform and build mode.
  ///
  /// In release mode → returns [productionUrl].
  /// In debug mode → resolves to localhost or device IP using [hostIp]/[apiPort].
  static String _resolveUrl({
    required String hostIp,
    required String apiPort,
    required String productionUrl,
  }) {
    if (!kDebugMode) return productionUrl;

    if (kIsWeb) return 'http://localhost:$apiPort';

    final isMobile = Platform.isAndroid || Platform.isIOS;
    final isLanIp = hostIp.startsWith('192.') || hostIp.startsWith('172.') || hostIp.startsWith('10.');

    if (isMobile && isLanIp) {
      if (Platform.isAndroid && hostIp == '10.0.2.2') {
        return 'http://10.0.2.2:$apiPort';
      }
      return 'http://$hostIp:$apiPort';
    }

    if (Platform.isAndroid) {
      return 'http://10.0.2.2:$apiPort';
    }

    return 'http://localhost:$apiPort';
  }
}

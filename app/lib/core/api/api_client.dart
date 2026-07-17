import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/settings.dart';

/// Dio client pointed at the MangaVault server (`/api/v1`), with the bearer
/// token from settings. Repositories (M2+) depend on this provider.
final apiClientProvider = Provider<Dio>((ref) {
  final settings = ref.watch(serverSettingsProvider).value ?? const ServerSettings();
  final dio = Dio(
    BaseOptions(
      baseUrl: settings.isConfigured ? '${settings.baseUrl}/api/v1' : '',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        if (settings.apiToken.isNotEmpty)
          'Authorization': 'Bearer ${settings.apiToken}',
      },
    ),
  );
  return dio;
});

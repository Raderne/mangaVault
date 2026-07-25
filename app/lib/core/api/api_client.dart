import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';

/// Dio client pointed at the MangaVault server (`/api/v1`), configured at build
/// time from [AppConfig]. Repositories (M2+) depend on this provider.
final apiClientProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      baseUrl: '${AppConfig.baseUrl}/api/v1',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        if (AppConfig.apiToken.isNotEmpty)
          'Authorization': 'Bearer ${AppConfig.apiToken}',
      },
    ),
  );
});

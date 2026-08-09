import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/server_config.dart';
import '../config/server_config_controller.dart';

/// Dio client pointed at the user's own Manga Vault server (`/api/v1`).
///
/// Watches [serverConfigProvider], so connecting to a server — or switching to
/// a different one — rebuilds the client and every repository that depends on
/// it. Before setup completes the base URL is empty; the router guarantees no
/// screen that uses this provider is reachable in that state.
final apiClientProvider = Provider<Dio>((ref) {
  final config = ref.watch(serverConfigProvider);
  return buildApiClient(config);
});

/// Exposed separately so the connection check can build a client for a config
/// the user has typed but not yet saved.
Dio buildApiClient(ServerConfig config) {
  return Dio(
    BaseOptions(
      baseUrl: config.isConfigured ? config.apiBase : '',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        if (config.apiToken.isNotEmpty)
          'Authorization': 'Bearer ${config.apiToken}',
      },
    ),
  );
}

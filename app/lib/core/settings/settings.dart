import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Connection settings for the MangaVault server.
class ServerSettings {
  const ServerSettings({this.baseUrl = '', this.apiToken = ''});

  final String baseUrl;
  final String apiToken;

  bool get isConfigured => baseUrl.isNotEmpty;

  ServerSettings copyWith({String? baseUrl, String? apiToken}) => ServerSettings(
        baseUrl: baseUrl ?? this.baseUrl,
        apiToken: apiToken ?? this.apiToken,
      );
}

// TODO(m2): move apiToken to flutter_secure_storage before real deployments.
class ServerSettingsNotifier extends AsyncNotifier<ServerSettings> {
  static const _kBaseUrl = 'server_base_url';
  static const _kApiToken = 'server_api_token';

  final _prefs = SharedPreferencesAsync();

  @override
  Future<ServerSettings> build() async {
    return ServerSettings(
      baseUrl: await _prefs.getString(_kBaseUrl) ?? '',
      apiToken: await _prefs.getString(_kApiToken) ?? '',
    );
  }

  Future<void> save({required String baseUrl, required String apiToken}) async {
    final normalized = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    await _prefs.setString(_kBaseUrl, normalized);
    await _prefs.setString(_kApiToken, apiToken.trim());
    state = AsyncData(ServerSettings(baseUrl: normalized, apiToken: apiToken.trim()));
  }
}

final serverSettingsProvider =
    AsyncNotifierProvider<ServerSettingsNotifier, ServerSettings>(
  ServerSettingsNotifier.new,
);

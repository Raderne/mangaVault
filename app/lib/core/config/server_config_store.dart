import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'server_config.dart';

/// Persists the user's server address and token across launches.
abstract interface class ServerConfigStore {
  /// The saved config, or null when the app has never been set up.
  Future<ServerConfig?> read();

  Future<void> write(ServerConfig config);

  Future<void> clear();
}

/// [ServerConfigStore] over the platform keystore.
///
/// The token is a bearer credential for the user's whole archive, so it is not
/// kept in `shared_preferences` (a world-readable XML file on a rooted device).
/// On Android `flutter_secure_storage` backs onto EncryptedSharedPreferences
/// with a Keystore-held key.
class SecureServerConfigStore implements ServerConfigStore {
  const SecureServerConfigStore([
    this._storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
  ]);

  static const _urlKey = 'server_base_url';
  static const _tokenKey = 'server_api_token';

  final FlutterSecureStorage _storage;

  @override
  Future<ServerConfig?> read() async {
    try {
      final url = await _storage.read(key: _urlKey);
      final token = await _storage.read(key: _tokenKey);
      if (url == null || token == null || url.isEmpty || token.isEmpty) {
        return null;
      }
      return ServerConfig(baseUrl: url, apiToken: token);
    } on Object {
      // A keystore that cannot be read (corrupted after a restore-from-backup,
      // which is a known Android failure mode) must not brick the app. Treat it
      // as "not set up" and let the user enter the details again.
      return null;
    }
  }

  @override
  Future<void> write(ServerConfig config) async {
    await _storage.write(key: _urlKey, value: config.baseUrl);
    await _storage.write(key: _tokenKey, value: config.apiToken);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _urlKey);
    await _storage.delete(key: _tokenKey);
  }
}

/// In-memory store, for tests and for a platform without secure storage.
class InMemoryServerConfigStore implements ServerConfigStore {
  InMemoryServerConfigStore([this._config]);

  ServerConfig? _config;

  @override
  Future<ServerConfig?> read() async => _config;

  @override
  Future<void> write(ServerConfig config) async => _config = config;

  @override
  Future<void> clear() async => _config = null;
}

final serverConfigStoreProvider = Provider<ServerConfigStore>(
  (ref) => const SecureServerConfigStore(),
);

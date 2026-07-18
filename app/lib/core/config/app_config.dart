/// Compile-time server configuration for the MangaVault backend (`server/`).
///
/// Values come from `--dart-define` (typically via a git-ignored config file:
/// `flutter run --dart-define-from-file=config/dev.json`). The defaults target
/// the dev server on this machine's LAN, so a physical device on the same
/// Wi-Fi connects out of the box.
///
/// There is deliberately no in-app connection settings screen — the server is
/// the single source of truth and is baked in at build time.
class AppConfig {
  /// Base origin of the backend, without the `/api/v1` prefix.
  /// Android emulator would use `http://10.0.2.2:3000`; a physical device on
  /// the LAN uses the host's LAN IP.
  static const String baseUrl = String.fromEnvironment(
    'SERVER_URL',
    defaultValue: 'http://192.168.1.12:3000',
  );

  /// Bearer token matching the server's `API_TOKEN`. Supply via dart-define;
  /// never commit the real value.
  static const String apiToken = String.fromEnvironment('API_TOKEN');

  const AppConfig._();
}

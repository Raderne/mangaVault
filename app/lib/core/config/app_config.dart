/// Build-time configuration.
///
/// **The server URL and API token are no longer here.** Manga Vault ships as a
/// public APK and every user runs their own server, so baking in an address and
/// a bearer token would hand one person's archive to everyone who downloaded
/// the app. They are entered once in the setup screen and kept in the device
/// keystore — see `core/config/server_config.dart`.
///
/// What remains is genuinely build-time: which GitHub repo to look for updates
/// in, and dev conveniences that are absent from a release build.
class AppConfig {
  /// GitHub repository the in-app updater reads releases from.
  ///
  /// Safe defaults to ship: the repo is public and the Releases API needs no
  /// credential. Still `dart-define`-able so a fork can publish its own builds
  /// without editing source.
  static const String updateRepoOwner = String.fromEnvironment(
    'UPDATE_REPO_OWNER',
    defaultValue: 'Raderne',
  );
  static const String updateRepoName = String.fromEnvironment(
    'UPDATE_REPO_NAME',
    defaultValue: 'mangaVault',
  );

  /// Set to `false` in a build that should never offer to update itself.
  static const bool updatesEnabled = bool.fromEnvironment(
    'UPDATES_ENABLED',
    defaultValue: true,
  );

  static String get releasesPageUrl =>
      'https://github.com/$updateRepoOwner/$updateRepoName/releases';

  /// Dev convenience only: **prefills** the setup screen's fields so
  /// `flutter run --dart-define-from-file=config/dev.json` is one tap from
  /// connected, instead of retyping a LAN address and a long token on every
  /// fresh install.
  ///
  /// These are *not* config. Nothing reads them after the setup screen, and a
  /// release build passes no defines, so they are empty in a published APK.
  /// Never reintroduce them as a fallback for [ServerConfig] — that would put
  /// the token back in the binary, which is the whole thing this avoids.
  static const String devSeedServerUrl = String.fromEnvironment('SERVER_URL');
  static const String devSeedApiToken = String.fromEnvironment('API_TOKEN');

  const AppConfig._();
}

/// The address and credential of the user's own Manga Vault server.
///
/// **This is runtime state, not a build-time constant.** Manga Vault is
/// distributed as a public APK, and every user runs their own server — so the
/// URL and token cannot be baked in. An APK carrying them would hand its
/// server to everyone who downloaded it.
///
/// Stored on-device via [ServerConfigStore]; nothing here is ever sent
/// anywhere except to the server it describes.
class ServerConfig {
  const ServerConfig({required this.baseUrl, required this.apiToken});

  static const empty = ServerConfig(baseUrl: '', apiToken: '');

  /// Normalized origin with no trailing slash and no `/api/v1` suffix,
  /// e.g. `http://192.168.1.20:3000`. Always produced by [normalizeServerUrl].
  final String baseUrl;

  /// Bearer token matching the server's `API_TOKEN` env var.
  final String apiToken;

  /// Whether the app has enough to talk to a server at all. The router refuses
  /// to show anything but the setup screen until this is true.
  bool get isConfigured => baseUrl.isNotEmpty && apiToken.isNotEmpty;

  /// Root every API call hangs off.
  String get apiBase => '$baseUrl/api/v1';

  /// `192.168.1.20:3000` — host and port only, for display. Never includes the
  /// token.
  String get displayHost {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || uri.host.isEmpty) return baseUrl;
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }

  ServerConfig copyWith({String? baseUrl, String? apiToken}) => ServerConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        apiToken: apiToken ?? this.apiToken,
      );

  @override
  bool operator ==(Object other) =>
      other is ServerConfig &&
      other.baseUrl == baseUrl &&
      other.apiToken == apiToken;

  @override
  int get hashCode => Object.hash(baseUrl, apiToken);

  /// Deliberately omits the token — this type ends up in error logs.
  @override
  String toString() => 'ServerConfig($baseUrl)';
}

/// Why a typed-in address could not be used.
enum ServerUrlError {
  empty('Enter your server address.'),
  malformed('That doesn\'t look like a web address.'),
  badScheme('Only http:// and https:// addresses work.'),
  noHost('Add the server\'s address, e.g. 192.168.1.20:3000.');

  const ServerUrlError(this.message);

  final String message;
}

/// Turns what someone actually types into a usable origin.
///
/// People paste all of these, and every one of them should work:
/// `192.168.1.20:3000`, `http://vault.example.com/`, `vault.example.com/api/v1`.
/// Being strict here would mean rejecting a correct server over a trailing
/// slash, so the parsing is generous and only the genuinely unusable is
/// refused.
({String? url, ServerUrlError? error}) normalizeServerUrl(String input) {
  var text = input.trim();
  if (text.isEmpty) return (url: null, error: ServerUrlError.empty);

  // A bare host or host:port has no scheme; Uri.parse would read `host:3000`
  // as scheme `host`, so decide before parsing.
  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(text)) {
    text = 'http://$text';
  }

  final uri = Uri.tryParse(text);
  if (uri == null) return (url: null, error: ServerUrlError.malformed);
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return (url: null, error: ServerUrlError.badScheme);
  }
  if (uri.host.isEmpty) return (url: null, error: ServerUrlError.noHost);

  // Strip the API prefix if it was pasted in — the app appends it itself, and
  // `…/api/v1/api/v1/library` is a confusing 404 to debug.
  var path = uri.path;
  path = path.replaceFirst(RegExp(r'/api/v1/?$'), '');
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }

  final normalized = Uri(
    scheme: uri.scheme,
    host: uri.host.toLowerCase(),
    port: uri.hasPort ? uri.port : null,
    path: path,
  );
  return (url: normalized.toString(), error: null);
}

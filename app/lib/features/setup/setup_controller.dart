import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/config/server_config.dart';
import '../../core/config/server_config_controller.dart';
import '../../data/connection/connection_check.dart';

/// Where the setup form is in the connect attempt.
enum SetupPhase { editing, testing, connected }

/// Form + verification state of the server setup screen.
class SetupState {
  const SetupState({
    this.url = '',
    this.token = '',
    this.phase = SetupPhase.editing,
    this.urlError,
    this.tokenError,
    this.generalError,
  });

  final String url;
  final String token;
  final SetupPhase phase;

  /// Errors are attached to the field that owns them — a bad token must not
  /// put a message under the address box, which is how people end up
  /// "fixing" a URL that was already right.
  final String? urlError;
  final String? tokenError;

  /// Something wrong with neither field individually (server present but not
  /// a vault, unexpected status).
  final String? generalError;

  bool get isTesting => phase == SetupPhase.testing;
  bool get isConnected => phase == SetupPhase.connected;

  /// Whether the Connect button does anything. Both fields must have content;
  /// their *validity* is the check's job, not the button's.
  bool get canSubmit =>
      !isTesting && url.trim().isNotEmpty && token.trim().isNotEmpty;

  bool get hasError =>
      urlError != null || tokenError != null || generalError != null;

  SetupState copyWith({
    String? url,
    String? token,
    SetupPhase? phase,
    String? urlError,
    String? tokenError,
    String? generalError,
  }) =>
      SetupState(
        url: url ?? this.url,
        token: token ?? this.token,
        phase: phase ?? this.phase,
        urlError: urlError,
        tokenError: tokenError,
        generalError: generalError,
      );
}

/// Drives the first-run server setup: normalize, probe, persist.
///
/// Nothing is saved until the server has actually answered and accepted the
/// token. Storing an unverified address would drop the user into an app whose
/// every screen fails, with no obvious way back to the form.
class SetupController extends Notifier<SetupState> {
  @override
  SetupState build() {
    final existing = ref.read(serverConfigProvider);
    // Reconfiguring an existing connection starts from what's already set;
    // a first run may be prefilled by a dev `--dart-define` (never present in
    // a release build — see AppConfig.devSeedServerUrl).
    return SetupState(
      url: existing.baseUrl.isNotEmpty
          ? existing.baseUrl
          : AppConfig.devSeedServerUrl,
      token: existing.apiToken.isNotEmpty
          ? existing.apiToken
          : AppConfig.devSeedApiToken,
    );
  }

  void setUrl(String value) =>
      state = state.copyWith(url: value, token: state.token);

  void setToken(String value) =>
      state = state.copyWith(url: state.url, token: value);

  /// Verify the typed details and, if they work, connect the app to them.
  /// Returns true when the app is now configured.
  Future<bool> submit() async {
    if (!state.canSubmit) return false;

    final normalized = normalizeServerUrl(state.url);
    if (normalized.url == null) {
      state = state.copyWith(
        url: state.url,
        token: state.token,
        phase: SetupPhase.editing,
        urlError: normalized.error!.message,
      );
      return false;
    }

    final candidate = ServerConfig(
      baseUrl: normalized.url!,
      apiToken: state.token.trim(),
    );

    state = state.copyWith(
      url: candidate.baseUrl,
      token: state.token,
      phase: SetupPhase.testing,
    );

    final result = await ref.read(connectionCheckerProvider).check(candidate);

    switch (result) {
      case ConnectionOk():
        await ref.read(serverConfigProvider.notifier).save(candidate);
        state = state.copyWith(
          url: candidate.baseUrl,
          token: state.token,
          phase: SetupPhase.connected,
        );
        return true;
      case ConnectionUnreachable(:final detail):
        _fail(candidate, urlError: detail);
      case ConnectionNotVault():
        _fail(
          candidate,
          generalError: 'Something is running at that address, but it is not '
              'a Manga Vault server.',
        );
      case ConnectionBadToken():
        _fail(
          candidate,
          tokenError: 'That token was rejected. It must match API_TOKEN in '
              "your server's .env.",
        );
      case ConnectionFailed(:final detail):
        _fail(candidate, generalError: detail);
    }
    return false;
  }

  /// Land back on an editable form carrying the error.
  ///
  /// Every failure goes through here specifically so the phase is reset:
  /// [SetupState.copyWith] preserves `phase`, so a branch that forgot to pass
  /// it left the screen spinning on "Contacting your server…" with the Connect
  /// button gone — no error visible and no way to retry.
  void _fail(
    ServerConfig candidate, {
    String? urlError,
    String? tokenError,
    String? generalError,
  }) {
    state = state.copyWith(
      url: candidate.baseUrl,
      token: state.token,
      phase: SetupPhase.editing,
      urlError: urlError,
      tokenError: tokenError,
      generalError: generalError,
    );
  }
}

final setupControllerProvider =
    NotifierProvider<SetupController, SetupState>(SetupController.new);

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/drive/drive_store.dart';

/// OAuth client id of the **web** application registered in Google Cloud,
/// passed as `serverClientId` — Android's Credential Manager requires one when
/// there is no `google-services.json`.
///
/// Unlike the API token this is compiled in on purpose: an OAuth client id is a
/// public identifier, not a secret, and Google expects it to ship inside apps.
/// Empty means this build has no Google project, and the Drive feature says so
/// instead of failing. Setup steps: `wiki-brain-vault/wiki/google-drive-backup.md`.
const kGoogleServerClientId = '';

/// Only files this app creates. Non-sensitive, so no Google verification or
/// security assessment — the full `drive` scope would need both.
const kDriveScopes = [drive.DriveApi.driveFileScope];

const _kEmail = 'google.email';

@immutable
class GoogleAccountState {
  const GoogleAccountState({
    this.available = true,
    this.email,
    this.busy = false,
    this.error,
  });

  /// False when this build has no Google client id configured.
  final bool available;

  /// The connected account, remembered across launches.
  final String? email;
  final bool busy;
  final String? error;

  bool get connected => email != null;
}

/// The Google account Drive uploads go to.
///
/// The account is *remembered*, not silently re-signed-in at launch: a
/// lightweight sign-in can surface a bottom sheet on Android, and nothing
/// should appear over the dashboard unasked. The real session is re-established
/// only when an upload actually needs it.
class GoogleAccountController extends Notifier<GoogleAccountState> {
  /// `GoogleSignIn.initialize` may only be called once per process.
  static Future<void>? _initialized;

  GoogleSignInAccount? _user;
  bool _touched = false;

  @override
  GoogleAccountState build() {
    if (kGoogleServerClientId.isEmpty) {
      return const GoogleAccountState(available: false);
    }
    Future<void>.microtask(_load);
    return const GoogleAccountState();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_touched) return;
      state = GoogleAccountState(email: prefs.getString(_kEmail));
    } catch (_) {
      // No storage — shows as not connected, which connecting fixes.
    }
  }

  Future<void> _ensureInitialized() => _initialized ??=
      GoogleSignIn.instance.initialize(serverClientId: kGoogleServerClientId);

  /// Sign in and grant Drive access. Must be called from a user action.
  Future<void> connect() async {
    if (!state.available || state.busy) return;
    _touched = true;
    state = GoogleAccountState(email: state.email, busy: true);
    try {
      await _ensureInitialized();
      final user =
          await GoogleSignIn.instance.authenticate(scopeHint: kDriveScopes);
      await user.authorizationClient.authorizeScopes(kDriveScopes);
      _setUser(user);
    } on GoogleSignInException catch (e) {
      state = GoogleAccountState(
        email: _user?.email,
        error: e.code == GoogleSignInExceptionCode.canceled
            ? null
            : 'Google sign-in failed (${e.code.name}).',
      );
    } catch (e) {
      state = GoogleAccountState(email: _user?.email, error: '$e');
    }
  }

  /// Sign out *and* revoke the Drive grant. Files already on Drive stay.
  Future<void> disconnect() async {
    _touched = true;
    try {
      await _ensureInitialized();
      await GoogleSignIn.instance.disconnect();
    } catch (_) {
      // Forget locally regardless; a stale grant is revocable from Google.
    }
    _user = null;
    state = const GoogleAccountState();
    _persist(null);
  }

  /// See [DriveOpener].
  Future<DriveStore?> openDrive({required bool interactive}) async {
    if (!state.available) return null;
    try {
      await _ensureInitialized();
      var user = _user ??
          await (GoogleSignIn.instance.attemptLightweightAuthentication() ??
              Future<GoogleSignInAccount?>.value());
      if (user == null && interactive) {
        await connect();
        user = _user;
      }
      if (user == null) return null;
      _setUser(user);

      final client = user.authorizationClient;
      final authorization = await client.authorizationForScopes(kDriveScopes) ??
          (interactive ? await client.authorizeScopes(kDriveScopes) : null);
      if (authorization == null) return null;

      final http = authorization.authClient(scopes: kDriveScopes);
      return GoogleDriveStore(drive.DriveApi(http), http.close);
    } on GoogleSignInException catch (e) {
      // Cancelled, or Google wants the user back in the loop. Either way there
      // is no Drive to hand out; an unattended caller reports "reconnect".
      if (!interactive || e.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      rethrow;
    }
  }

  void _setUser(GoogleSignInAccount user) {
    _touched = true;
    _user = user;
    state = GoogleAccountState(email: user.email);
    _persist(user.email);
  }

  Future<void> _persist(String? email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      email == null
          ? await prefs.remove(_kEmail)
          : await prefs.setString(_kEmail, email);
    } catch (_) {
      // Best-effort.
    }
  }
}

final googleAccountProvider =
    NotifierProvider<GoogleAccountController, GoogleAccountState>(
  GoogleAccountController.new,
);

/// The seam tests override — nothing else should call Google directly.
final driveOpenerProvider = Provider<DriveOpener>(
  (ref) => ref.read(googleAccountProvider.notifier).openDrive,
);

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/covers/cover_cache.dart';
import '../../data/local/app_database.dart';
import 'server_config.dart';
import 'server_config_store.dart';

/// The config loaded from disk before the first frame.
///
/// Overridden in `main()` with the real value. Reading secure storage is async,
/// but the router's redirect guard must decide *synchronously* whether the app
/// is set up — otherwise the first frame flashes the dashboard before bouncing
/// to setup. Loading once up front removes the race entirely.
final bootstrapServerConfigProvider = Provider<ServerConfig>(
  (ref) => ServerConfig.empty,
);

/// The server the app is currently pointed at.
class ServerConfigController extends Notifier<ServerConfig> {
  @override
  ServerConfig build() => ref.read(bootstrapServerConfigProvider);

  /// Persist a verified config and switch the app to it.
  ///
  /// Wipes the local mirror when the **server address** changes. A token
  /// rotation against the same server keeps the cache (the data is still
  /// valid); pointing at a different server must not leave the previous
  /// vault's titles on screen.
  Future<void> save(ServerConfig config) async {
    final movedServer =
        state.baseUrl.isNotEmpty && state.baseUrl != config.baseUrl;

    await ref.read(serverConfigStoreProvider).write(config);
    if (movedServer) await _wipeMirror();
    state = config;
  }

  /// Forget the server entirely and return the app to setup.
  ///
  /// The mirror always goes with it: it is a projection of a server the user
  /// has just disconnected from, and leaving it on disk would show a stale
  /// library to whoever sets the app up next.
  Future<void> clear() async {
    await ref.read(serverConfigStoreProvider).clear();
    await _wipeMirror();
    state = ServerConfig.empty;
  }

  Future<void> _wipeMirror() async {
    try {
      await ref.read(appDatabaseProvider).wipe();
    } on Object {
      // A cache we failed to clear is a stale cache, not a broken app — the
      // next sync's epoch check will force a full resync anyway.
    }
    // Cover art too: CoverCache is keyed by manga id, and two servers can mint
    // the same id, so a kept cache would paint one vault's art onto another's
    // titles.
    //
    // Deliberately **not** awaited. flutter_cache_manager's store waits on a
    // platform channel, so awaiting it hangs under test — the same trap that
    // made title deletion fire-and-forget its eviction. A cover that outlives
    // its vault by a few seconds is cosmetic; a disconnect that never returns
    // is not. Goes through a provider so tests can substitute a no-op; see
    // [coverCacheCleanerProvider].
    unawaited(ref.read(coverCacheCleanerProvider)());
  }
}

final serverConfigProvider =
    NotifierProvider<ServerConfigController, ServerConfig>(
  ServerConfigController.new,
);

/// Whether the app may show anything other than the setup screen.
final isConfiguredProvider = Provider<bool>(
  (ref) => ref.watch(serverConfigProvider).isConfigured,
);

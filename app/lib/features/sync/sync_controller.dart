import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/local/local_library_dao.dart';
import '../../data/sync/library_sync_service.dart';

/// UI-facing state of the library sync.
sealed class SyncState {
  const SyncState();
}

class SyncIdle extends SyncState {
  const SyncIdle();
}

class SyncRunning extends SyncState {
  const SyncRunning({required this.received, required this.total});

  final int received;
  final int total;

  double get fraction =>
      total <= 0 ? 0 : (received / total).clamp(0.0, 1.0).toDouble();
}

class SyncDone extends SyncState {
  const SyncDone({required this.received});

  final int received;
}

class SyncFailed extends SyncState {
  const SyncFailed(this.message);

  final String message;
}

/// Drives [LibrarySyncService] and exposes progress for the library banner.
///
/// Failures are non-fatal by design: the mirror keeps serving whatever it
/// already holds, and the banner is the only place the error surfaces.
class SyncController extends Notifier<SyncState> {
  bool _disposed = false;

  @override
  SyncState build() {
    ref.onDispose(() => _disposed = true);
    return const SyncIdle();
  }

  LibrarySyncService get _service => ref.read(librarySyncServiceProvider);

  /// Fill the mirror on first run. No-op once a cursor exists.
  ///
  /// Called from a post-frame callback, so it must never throw: a failure here
  /// belongs in the banner, not in an unhandled async error.
  Future<void> bootstrap() async {
    try {
      final existing = await ref.read(appDatabaseProvider).syncStateRow();
      if (existing?.cursor != null) return;
    } catch (e) {
      _set(SyncFailed(_message(e)));
      return;
    }
    await run();
  }

  /// Pull changes. [force] re-pulls the whole library from scratch.
  Future<void> run({bool force = false}) async {
    if (state is SyncRunning) return;
    _set(const SyncRunning(received: 0, total: 0));
    try {
      final received = await _service.sync(
        force: force,
        onProgress: (p) {
          _set(SyncRunning(received: p.received, total: p.total));
          // Each committed page makes more of the library readable, so let the
          // screens re-read as the sync streams in rather than at the end.
          if (!_disposed) ref.read(localRevisionProvider.notifier).bump();
        },
      );
      if (!_disposed) ref.read(localRevisionProvider.notifier).bump();
      _set(SyncDone(received: received));
    } catch (e) {
      _set(SyncFailed(_message(e)));
    }
  }

  void dismiss() => _set(const SyncIdle());

  void _set(SyncState next) {
    if (!_disposed) state = next;
  }

  static String _message(Object e) =>
      e.toString().replaceFirst('Exception: ', '');
}

final syncControllerProvider =
    NotifierProvider<SyncController, SyncState>(SyncController.new);

/// The on-device library reader.
final localLibraryDaoProvider = Provider<LocalLibraryDao>(
  (ref) => LocalLibraryDao(ref.watch(appDatabaseProvider)),
);

/// Ticks once per committed sync, and is the single signal every local-read
/// provider watches — so one bump refreshes the library, the dashboard and the
/// import history together.
///
/// An in-process counter rather than a stream over `sync_meta.local_revision`:
/// [LibrarySyncService] is the only writer to the mirror and it runs in this
/// isolate, so a database watch would buy nothing while dragging a live drift
/// subscription into every widget tree (including tests). The column still
/// exists and the DAO can watch it if a second writer ever appears.
class LocalRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

final localRevisionProvider =
    NotifierProvider<LocalRevision, int>(LocalRevision.new);

/// When the mirror was last refreshed from the server (null = never).
final lastSyncedAtProvider = FutureProvider<int?>((ref) async {
  ref.watch(localRevisionProvider);
  final row = await ref.watch(appDatabaseProvider).syncStateRow();
  return row?.lastSyncedAt;
});

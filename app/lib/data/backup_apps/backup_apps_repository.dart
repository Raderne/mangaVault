import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../features/sync/sync_controller.dart';
import '../library/library_repository.dart';
import 'backup_app_models.dart';

/// Talks to the server's `/backup-apps` registry.
///
/// Read live (not from the mirror) by the import picker: choosing an app is an
/// online action anyway — it is followed by staging and committing a backup —
/// and the picker must offer apps the vault has no titles from yet. The
/// *library filter* reads the mirror instead, so it works offline.
class BackupAppsRepository {
  BackupAppsRepository(this._dio);

  final Dio _dio;

  Future<List<BackupApp>> list() async {
    final res = await _dio.get<List<dynamic>>('/backup-apps');
    return (res.data ?? const [])
        .map((e) => BackupApp.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<BackupApp> create(String id, String displayName) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/backup-apps',
      data: {'id': id, 'displayName': displayName},
    );
    return BackupApp.fromJson(res.data!);
  }
}

final backupAppsRepositoryProvider = Provider<BackupAppsRepository>(
  (ref) => BackupAppsRepository(ref.watch(apiClientProvider)),
);

/// The registry, for the import picker. Refreshed by invalidating this provider
/// after adding an app.
final backupAppsProvider = FutureProvider<List<BackupApp>>(
  (ref) => ref.watch(backupAppsRepositoryProvider).list(),
);

/// App id → display name, read from the **mirror** rather than the network, so
/// every place that shows a backup's app ("Mihon", not "app.mihon") keeps
/// working offline. Re-read after each committed sync page.
final backupAppNamesProvider = FutureProvider<Map<String, String>>((ref) {
  ref.watch(localRevisionProvider);
  return ref.watch(libraryRepositoryProvider).backupAppNames();
});

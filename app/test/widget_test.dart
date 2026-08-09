import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/core/config/server_config.dart';
import 'package:mangavault/core/config/server_config_controller.dart';
import 'package:mangavault/core/config/server_config_store.dart';
import 'package:mangavault/data/local/app_database.dart';
import 'package:mangavault/main.dart';

const _configured = ServerConfig(
  baseUrl: 'http://127.0.0.1:3000',
  apiToken: 'test-token',
);

ProviderScope _app(AppDatabase db, ServerConfig config) => ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        bootstrapServerConfigProvider.overrideWithValue(config),
        serverConfigStoreProvider.overrideWithValue(
          InMemoryServerConfigStore(config.isConfigured ? config : null),
        ),
      ],
      child: const MangaVaultApp(),
    );

void main() {
  testWidgets('a configured app renders the dashboard shell', (tester) async {
    // Every screen reads the on-device mirror, so the shell needs a database.
    // An in-memory one keeps this a pure shell smoke test — no path_provider
    // channel, no server, and the library simply renders empty.
    final db = AppDatabase.memory();
    addTearDown(db.close);

    await tester.pumpWidget(_app(db, _configured));
    await tester.pumpAndSettle();

    expect(find.text('Manga Vault'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
  });

  testWidgets('an unconfigured app is held at setup', (tester) async {
    // The gate that keeps a freshly sideloaded APK from reaching any screen
    // that would fire an unauthenticated request at somebody's server.
    final db = AppDatabase.memory();
    addTearDown(db.close);

    await tester.pumpWidget(_app(db, ServerConfig.empty));
    await tester.pumpAndSettle();

    expect(find.text('Connect your\nvault'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    // No shell, so no way around it.
    expect(find.text('Dashboard'), findsNothing);
    expect(find.text('Library'), findsNothing);
  });
}

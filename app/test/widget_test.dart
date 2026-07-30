import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/data/local/app_database.dart';
import 'package:mangavault/main.dart';

void main() {
  testWidgets('app renders the dashboard', (tester) async {
    // Every screen now reads the on-device mirror, so the shell needs a
    // database. An in-memory one keeps this a pure shell smoke test — no
    // path_provider channel, no server, and the library simply renders empty.
    final db = AppDatabase.memory();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MangaVaultApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MangaVault'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
  });
}

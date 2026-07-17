import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/main.dart';

void main() {
  testWidgets('app renders the dashboard', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MangaVaultApp()));
    await tester.pumpAndSettle();

    expect(find.text('MangaVault'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
  });
}

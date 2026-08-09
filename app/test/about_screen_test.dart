import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/data/updates/apk_installer.dart';
import 'package:mangavault/data/updates/update_models.dart';
import 'package:mangavault/data/updates/update_repository.dart';
import 'package:mangavault/features/about/about_screen.dart';
import 'package:mangavault/features/updates/update_banner.dart';
import 'package:mangavault/features/updates/update_controller.dart';
import 'package:mangavault/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_controller_test.dart' show FakeInstaller, FakeUpdateRepository;

AppRelease _release(String version, String body) => AppRelease(
      version: AppVersion.tryParse(version)!,
      tag: 'v$version',
      title: 'Manga Vault $version',
      publishedAt: DateTime.now().subtract(const Duration(days: 3)),
      notes: parseReleaseNotes(body),
      htmlUrl: 'https://example.com/v$version',
      apkUrl: 'https://example.com/app.apk',
      apkBytes: 1024 * 1024,
    );

Widget _app(ProviderContainer container, Widget child) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildAppTheme(), home: child),
    );

ProviderContainer _container(FakeUpdateRepository repo, {String installed = '1.0.0'}) {
  final container = ProviderContainer(
    overrides: [
      updateRepositoryProvider.overrideWithValue(repo),
      apkInstallerProvider.overrideWithValue(FakeInstaller()),
      installedAppProvider.overrideWith(
        (ref) async => InstalledApp(
          version: AppVersion.tryParse(installed)!,
          buildNumber: '4',
          packageName: 'dev.mangavault.mangavault',
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// About stacks five bento cells and its `ListView` builds lazily, so the
/// default 800pt test surface leaves the changelog below the fold and
/// unbuilt. Give it room rather than scrolling in every test.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4200);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows the installed version and expands its changelog entry',
      (tester) async {
    useTallSurface(tester);
    final repo = FakeUpdateRepository(
      releases: [
        _release('1.1.0', '### Added\n- Newer thing\n'),
        _release('1.0.0', '### Added\n- Original thing\n'),
      ],
    );
    final container = _container(repo);

    await tester.pumpWidget(_app(container, const AboutScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Manga\nVault'), findsOneWidget);
    expect(find.text('v1.0.0 (build 4)'), findsOneWidget);

    // Both releases are listed…
    expect(find.text('Version 1.1.0'), findsWidgets);
    expect(find.text('Version 1.0.0'), findsOneWidget);
    expect(find.text('Installed'), findsOneWidget);

    // …but only the installed one is expanded, so "what am I running?" is
    // answered without a tap.
    expect(find.text('Original thing'), findsOneWidget);
  });

  testWidgets('a newer release surfaces as an available update',
      (tester) async {
    useTallSurface(tester);
    final repo = FakeUpdateRepository(
      latestRelease: _release('1.2.0', '### Fixed\n- A bug\n'),
      releases: [_release('1.2.0', '### Fixed\n- A bug\n')],
    );
    final container = _container(repo);

    await tester.pumpWidget(_app(container, const AboutScreen()));
    await tester.pumpAndSettle();

    expect(find.text('UPDATE AVAILABLE'), findsOneWidget);
    expect(find.text('FIXED'), findsWidgets);
    expect(find.text('Download update'), findsOneWidget);
    expect(find.text('Skip this version'), findsOneWidget);
  });

  testWidgets('a failed changelog fetch offers a retry, not a dead cell',
      (tester) async {
    useTallSurface(tester);
    final repo = FakeUpdateRepository(
      checkError: const UpdateException('GitHub is unreachable.'),
    );
    final container = _container(repo);

    await tester.pumpWidget(_app(container, const AboutScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Could not load the changelog.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  group('UpdateBanner', () {
    testWidgets('stays out of the way until there is an update',
        (tester) async {
      final container = _container(FakeUpdateRepository());
      await tester.pumpWidget(_app(container, const Scaffold(
        body: UpdateBanner(),
      )));
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byType(UpdateBanner)).height, 0);
    });

    testWidgets('announces the version and can be dismissed', (tester) async {
      final repo = FakeUpdateRepository(
        latestRelease: _release('1.3.0', '### Added\n- Thing\n'),
      );
      final container = _container(repo);
      await container.read(updateControllerProvider.notifier).check();

      await tester.pumpWidget(_app(container, const Scaffold(
        body: UpdateBanner(),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Version 1.3.0 is available'), findsOneWidget);

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();

      expect(find.text('Version 1.3.0 is available'), findsNothing);
      expect(tester.getSize(find.byType(UpdateBanner)).height, 0);
    });
  });
}

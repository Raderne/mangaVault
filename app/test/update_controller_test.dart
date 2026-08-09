import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/data/updates/apk_installer.dart';
import 'package:mangavault/data/updates/update_models.dart';
import 'package:mangavault/data/updates/update_repository.dart';
import 'package:mangavault/features/updates/update_card.dart';
import 'package:mangavault/features/updates/update_controller.dart';
import 'package:mangavault/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppRelease _release({
  String version = '1.1.0',
  String body = '### Added\n- A new thing\n',
  bool withApk = true,
  int bytes = 20 * 1024 * 1024,
}) =>
    AppRelease(
      version: AppVersion.tryParse(version)!,
      tag: 'v$version',
      title: 'Manga Vault $version',
      publishedAt: DateTime.now().subtract(const Duration(days: 2)),
      notes: parseReleaseNotes(body),
      htmlUrl: 'https://example.com/releases/v$version',
      apkUrl: withApk ? 'https://example.com/app.apk' : null,
      apkBytes: withApk ? bytes : 0,
    );

/// Scriptable stand-in for GitHub. Downloads emit whatever progress the test
/// asks for, then hand back a real temp file so `install()` finds one on disk.
class FakeUpdateRepository implements UpdateRepository {
  FakeUpdateRepository({
    this.latestRelease,
    this.releases = const [],
    this.checkError,
    this.downloadError,
    this.progress = const [(5, 10), (10, 10)],
  });

  AppRelease? latestRelease;
  List<AppRelease> releases;
  Object? checkError;
  Object? downloadError;
  List<(int, int)> progress;

  int latestCalls = 0;
  int clearCalls = 0;
  Completer<void>? downloadGate;

  @override
  Future<AppRelease?> latest() async {
    latestCalls++;
    if (checkError != null) throw checkError!;
    return latestRelease;
  }

  @override
  Future<List<AppRelease>> history({int limit = 10}) async {
    if (checkError != null) throw checkError!;
    return releases;
  }

  @override
  Future<File> downloadApk(
    AppRelease release, {
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    for (final (received, total) in progress) {
      onProgress(received, total);
    }
    if (downloadGate != null) await downloadGate!.future;
    if (cancelToken != null && cancelToken.isCancelled) {
      throw DioException.requestCancelled(
        requestOptions: RequestOptions(),
        reason: 'cancelled',
      );
    }
    if (downloadError != null) throw downloadError!;
    final file = File(
      '${Directory.systemTemp.createTempSync('mv-test').path}/app.apk',
    );
    file.writeAsBytesSync(const [1, 2, 3]);
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    return file;
  }

  @override
  Future<void> clearDownloads() async => clearCalls++;
}

class FakeInstaller implements ApkInstaller {
  FakeInstaller({this.permitted = true});

  bool permitted;
  int installCalls = 0;
  int settingsCalls = 0;

  @override
  bool get isSupported => true;

  @override
  Future<bool> canInstall() async => permitted;

  @override
  Future<bool> openInstallSettings() async {
    settingsCalls++;
    return true;
  }

  @override
  Future<InstallResult> install(File apk) async {
    installCalls++;
    if (!permitted) {
      return const InstallRejected(
        InstallFailure.notPermitted,
        'Manga Vault needs permission to install apps.',
      );
    }
    return const InstallStarted();
  }
}

ProviderContainer _container({
  required FakeUpdateRepository repo,
  FakeInstaller? installer,
  String installedVersion = '1.0.0',
}) {
  final container = ProviderContainer(
    overrides: [
      updateRepositoryProvider.overrideWithValue(repo),
      apkInstallerProvider.overrideWithValue(installer ?? FakeInstaller()),
      installedAppProvider.overrideWith(
        (ref) async => InstalledApp(
          version: AppVersion.tryParse(installedVersion)!,
          buildNumber: '1',
          packageName: 'dev.mangavault.mangavault',
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUp(() {
    // The controller persists its check throttle and skipped version in
    // shared_preferences. Without the in-memory mock, `getInstance()` waits on
    // a platform channel that a widget test's fake clock never services — the
    // whole suite hangs rather than failing.
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('check', () {
    test('a newer release becomes UpdateAvailable', () async {
      final repo = FakeUpdateRepository(latestRelease: _release());
      final container = _container(repo: repo);

      await container.read(updateControllerProvider.notifier).check();

      final state = container.read(updateControllerProvider);
      expect(state, isA<UpdateAvailable>());
      expect(state.release!.version.name, '1.1.0');
    });

    test('the same version is up to date, not an update', () async {
      final repo = FakeUpdateRepository(latestRelease: _release(version: '1.0.0'));
      final container = _container(repo: repo);

      await container.read(updateControllerProvider.notifier).check();

      expect(container.read(updateControllerProvider), isA<UpdateUpToDate>());
    });

    test('an older release never offers a downgrade', () async {
      final repo = FakeUpdateRepository(latestRelease: _release(version: '0.9.0'));
      final container = _container(repo: repo, installedVersion: '1.0.0');

      await container.read(updateControllerProvider.notifier).check();

      expect(container.read(updateControllerProvider), isA<UpdateUpToDate>());
    });

    test('a repo with no releases is up to date', () async {
      final container = _container(repo: FakeUpdateRepository());

      await container.read(updateControllerProvider.notifier).check();

      expect(container.read(updateControllerProvider), isA<UpdateUpToDate>());
    });

    test('an explicit check surfaces the failure', () async {
      final repo = FakeUpdateRepository(
        checkError: const UpdateException('offline', isOffline: true),
      );
      final container = _container(repo: repo);

      await container.read(updateControllerProvider.notifier).check();

      final state = container.read(updateControllerProvider);
      expect(state, isA<UpdateFailed>());
      expect((state as UpdateFailed).isOffline, isTrue);
      expect(state.message, 'offline');
    });

    test('a silent check leaves the previous state untouched', () async {
      final repo = FakeUpdateRepository(latestRelease: _release());
      final container = _container(repo: repo);
      final notifier = container.read(updateControllerProvider.notifier);

      await notifier.check();
      expect(container.read(updateControllerProvider), isA<UpdateAvailable>());

      repo.checkError = const UpdateException('offline', isOffline: true);
      await notifier.check(silent: true);

      expect(
        container.read(updateControllerProvider),
        isA<UpdateAvailable>(),
        reason: 'a background failure must not replace a known-good state',
      );
    });
  });

  group('download', () {
    test('reports progress and ends ready to install', () async {
      final repo = FakeUpdateRepository(
        latestRelease: _release(),
        progress: const [(1000, 4000), (4000, 4000)],
      );
      final container = _container(repo: repo);
      final notifier = container.read(updateControllerProvider.notifier);

      await notifier.check();

      final seen = <String>[];
      container.listen(updateControllerProvider, (_, next) {
        if (next is UpdateDownloading) {
          seen.add('${next.received}/${next.total}');
        }
      });

      await notifier.download();

      // The first frame carries the asset size from the release metadata, so
      // the bar has a real total before a single byte lands.
      expect(seen, ['0/20971520', '1000/4000', '4000/4000']);
      final state = container.read(updateControllerProvider);
      expect(state, isA<UpdateReady>());
      expect((state as UpdateReady).apk.existsSync(), isTrue);
    });

    test('an unknown content length yields a null fraction', () {
      final state = UpdateDownloading(_release(), 500, -1);
      expect(state.fraction, isNull);
      expect(UpdateDownloading(_release(), 500, 1000).fraction, 0.5);
    });

    test('cancelling returns to available, not to an error', () async {
      final repo = FakeUpdateRepository(latestRelease: _release());
      repo.downloadGate = Completer<void>();
      final container = _container(repo: repo);
      final notifier = container.read(updateControllerProvider.notifier);
      await notifier.check();

      final pending = notifier.download();
      await Future<void>.delayed(Duration.zero);
      notifier.cancelDownload();
      repo.downloadGate!.complete();
      await pending;

      expect(container.read(updateControllerProvider), isA<UpdateAvailable>());
    });

    test('a download failure keeps the release so it can be retried', () async {
      final repo = FakeUpdateRepository(
        latestRelease: _release(),
        downloadError: const UpdateException('disk full'),
      );
      final container = _container(repo: repo);
      final notifier = container.read(updateControllerProvider.notifier);
      await notifier.check();
      await notifier.download();

      final state = container.read(updateControllerProvider);
      expect(state, isA<UpdateFailed>());
      expect(state.release!.version.name, '1.1.0');
    });

    test('a release with no APK is announced but not downloadable', () async {
      final repo = FakeUpdateRepository(latestRelease: _release(withApk: false));
      final container = _container(repo: repo);
      final notifier = container.read(updateControllerProvider.notifier);
      await notifier.check();

      expect(container.read(updateControllerProvider), isA<UpdateAvailable>());
      await notifier.download();
      expect(container.read(updateControllerProvider), isA<UpdateFailed>());
    });
  });

  group('install', () {
    test('a refused grant asks for permission instead of failing', () async {
      final installer = FakeInstaller(permitted: false);
      final repo = FakeUpdateRepository(latestRelease: _release());
      final container = _container(repo: repo, installer: installer);
      final notifier = container.read(updateControllerProvider.notifier);

      await notifier.check();
      await notifier.download();
      await notifier.install();

      final state = container.read(updateControllerProvider);
      expect(state, isA<UpdateReady>());
      expect((state as UpdateReady).needsPermission, isTrue);

      // Granting it and coming back from Settings clears the warning.
      installer.permitted = true;
      await notifier.recheckPermission();
      expect(
        (container.read(updateControllerProvider) as UpdateReady)
            .needsPermission,
        isFalse,
      );
    });

    test('a granted install hands the APK over exactly once', () async {
      final installer = FakeInstaller();
      final repo = FakeUpdateRepository(latestRelease: _release());
      final container = _container(repo: repo, installer: installer);
      final notifier = container.read(updateControllerProvider.notifier);

      await notifier.check();
      await notifier.download();
      await notifier.install();

      expect(installer.installCalls, 1);
      expect(container.read(updateControllerProvider), isA<UpdateReady>());
    });

    test('discarding clears the download and rewinds to available', () async {
      final repo = FakeUpdateRepository(latestRelease: _release());
      final container = _container(repo: repo);
      final notifier = container.read(updateControllerProvider.notifier);

      await notifier.check();
      await notifier.download();
      await notifier.discardDownload();

      expect(repo.clearCalls, 1);
      expect(container.read(updateControllerProvider), isA<UpdateAvailable>());
    });
  });

  group('banner suppression', () {
    test('dismissing hides the banner but keeps the state', () async {
      final repo = FakeUpdateRepository(latestRelease: _release());
      final container = _container(repo: repo);
      final notifier = container.read(updateControllerProvider.notifier);
      await notifier.check();

      expect(notifier.shouldPromptBanner, isTrue);
      notifier.dismissBanner();
      expect(notifier.shouldPromptBanner, isFalse);
      expect(container.read(updateControllerProvider), isA<UpdateAvailable>());
    });

    test('skipping suppresses the banner but not the About screen', () async {
      final repo = FakeUpdateRepository(latestRelease: _release());
      final container = _container(repo: repo);
      final notifier = container.read(updateControllerProvider.notifier);
      await notifier.check();

      await notifier.skipCurrent();

      expect(notifier.shouldPromptBanner, isFalse);
      expect(notifier.isSkipped, isTrue);
      expect(
        container.read(updateControllerProvider),
        isA<UpdateAvailable>(),
        reason: 'the update is still real, it just stops nagging',
      );
    });
  });

  group('UpdateCard rendering', () {
    Future<void> pump(WidgetTester tester, ProviderContainer container) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const Scaffold(
              body: SingleChildScrollView(child: UpdateCard()),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('an available update shows its version and changelog',
        (tester) async {
      final repo = FakeUpdateRepository(latestRelease: _release());
      final container = _container(repo: repo);
      await container.read(updateControllerProvider.notifier).check();
      await pump(tester, container);

      expect(find.text('UPDATE AVAILABLE'), findsOneWidget);
      expect(find.text('Version 1.1.0'), findsOneWidget);
      expect(find.text('ADDED'), findsOneWidget);
      expect(find.text('A new thing'), findsOneWidget);
      expect(find.text('Download update'), findsOneWidget);
    });

    testWidgets('up to date says so and offers a re-check', (tester) async {
      final repo = FakeUpdateRepository(latestRelease: _release(version: '1.0.0'));
      final container = _container(repo: repo);
      await container.read(updateControllerProvider.notifier).check();
      await pump(tester, container);

      expect(find.text('UP TO DATE'), findsOneWidget);
      expect(find.text('Check again'), findsOneWidget);
      expect(find.text('Download update'), findsNothing);
    });

    testWidgets('offline is amber and retryable, not an error', (tester) async {
      final repo = FakeUpdateRepository(
        checkError: const UpdateException('No connection.', isOffline: true),
      );
      final container = _container(repo: repo);
      await container.read(updateControllerProvider.notifier).check();
      await pump(tester, container);

      expect(find.text('OFFLINE'), findsOneWidget);
      expect(find.text('No connection.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('the downloading cell does not resize as bytes arrive',
        (tester) async {
      // A cell that grows or shrinks mid-download would shove the page around
      // on every progress frame — see app/CLAUDE.md on fixed-height live cells.
      final repo = FakeUpdateRepository(latestRelease: _release());
      repo.downloadGate = Completer<void>();
      final container = _container(repo: repo);
      final notifier = container.read(updateControllerProvider.notifier);
      await notifier.check();

      final pending = notifier.download();
      await pump(tester, container);
      final firstHeight = tester.getSize(find.byType(UpdateCard)).height;

      // Byte labels of very different widths must not change the height.
      for (final step in [(1, 100000000), (99999999, 100000000)]) {
        notifier.state = UpdateDownloading(_release(), step.$1, step.$2);
        await tester.pump();
        expect(tester.getSize(find.byType(UpdateCard)).height, firstHeight);
      }

      repo.downloadGate!.complete();
      await pending;
    });
  });
}

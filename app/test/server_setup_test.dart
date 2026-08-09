import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/core/config/server_config.dart';
import 'package:mangavault/core/config/server_config_controller.dart';
import 'package:mangavault/core/config/server_config_store.dart';
import 'package:mangavault/data/connection/connection_check.dart';
import 'package:mangavault/data/covers/cover_cache.dart';
import 'package:mangavault/data/local/app_database.dart';
import 'package:mangavault/features/setup/setup_controller.dart';
import 'package:mangavault/features/setup/setup_screen.dart';
import 'package:mangavault/theme/app_theme.dart';

/// Serves canned responses per path, standing in for a Manga Vault server.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter({
    this.healthStatus = 200,
    this.healthBody = const {'status': 'ok', 'service': 'mangavault-server'},
    this.authStatus = 200,
    this.throwOn,
  });

  int healthStatus;
  Object? healthBody;
  int authStatus;

  /// Path substring that should raise a connection error instead of replying.
  String? throwOn;

  final requestedTokens = <String?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (throwOn != null && options.path.contains(throwOn!)) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'no route to host',
      );
    }
    if (options.path.contains('/health')) {
      // A non-map body stands in for "something else is listening here", so it
      // is served as HTML — exactly what a router admin page would return.
      final isJson = healthBody is Map;
      return ResponseBody.fromString(
        _encode(healthBody),
        healthStatus,
        headers: {
          Headers.contentTypeHeader: [
            isJson ? Headers.jsonContentType : 'text/html',
          ],
        },
      );
    }
    requestedTokens.add(options.headers['Authorization'] as String?);
    return ResponseBody.fromString(
      '[]',
      authStatus,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  String _encode(Object? body) => switch (body) {
        null => '',
        final String s => s,
        final Map<String, dynamic> m =>
          '{${m.entries.map((e) => '"${e.key}":"${e.value}"').join(',')}}',
        _ => '$body',
      };

  @override
  void close({bool force = false}) {}
}

ConnectionChecker _checker(FakeAdapter adapter) => ConnectionChecker(
      clientFactory: (options) => Dio(options)..httpClientAdapter = adapter,
    );

const _config = ServerConfig(
  baseUrl: 'http://192.168.1.20:3000',
  apiToken: 'right-token',
);

/// The setup form is taller than the default 600pt test surface, so the
/// Connect button lands off-screen and cannot be tapped. The real screen
/// scrolls; the test just needs room.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

void main() {
  group('normalizeServerUrl', () {
    test('adds http:// to a bare host or host:port', () {
      expect(normalizeServerUrl('192.168.1.20:3000').url,
          'http://192.168.1.20:3000');
      expect(normalizeServerUrl('vault.example.com').url,
          'http://vault.example.com');
    });

    test('keeps an explicit scheme and lowercases the host', () {
      expect(normalizeServerUrl('https://Vault.Example.com').url,
          'https://vault.example.com');
    });

    test('strips trailing slashes', () {
      expect(normalizeServerUrl('http://host:3000/').url, 'http://host:3000');
      expect(normalizeServerUrl('http://host:3000///').url, 'http://host:3000');
    });

    test('strips a pasted /api/v1 suffix', () {
      // People copy the URL out of a browser tab or a curl command; appending
      // our own prefix to it would produce /api/v1/api/v1/library.
      expect(normalizeServerUrl('http://host:3000/api/v1').url,
          'http://host:3000');
      expect(normalizeServerUrl('host:3000/api/v1/').url, 'http://host:3000');
    });

    test('keeps a real sub-path (a reverse proxy mount point)', () {
      expect(normalizeServerUrl('https://example.com/vault').url,
          'https://example.com/vault');
    });

    test('trims surrounding whitespace from a paste', () {
      expect(normalizeServerUrl('  http://host:3000  ').url,
          'http://host:3000');
    });

    test('rejects what it cannot use', () {
      expect(normalizeServerUrl('').error, ServerUrlError.empty);
      expect(normalizeServerUrl('   ').error, ServerUrlError.empty);
      expect(normalizeServerUrl('ftp://host').error, ServerUrlError.badScheme);
      expect(normalizeServerUrl('http://').error, ServerUrlError.noHost);
    });
  });

  group('ServerConfig', () {
    test('isConfigured needs both halves', () {
      expect(ServerConfig.empty.isConfigured, isFalse);
      expect(
        const ServerConfig(baseUrl: 'http://h:1', apiToken: '').isConfigured,
        isFalse,
      );
      expect(
        const ServerConfig(baseUrl: '', apiToken: 't').isConfigured,
        isFalse,
      );
      expect(_config.isConfigured, isTrue);
    });

    test('apiBase and displayHost are derived, not stored', () {
      expect(_config.apiBase, 'http://192.168.1.20:3000/api/v1');
      expect(_config.displayHost, '192.168.1.20:3000');
    });

    test('toString never leaks the token', () {
      expect(_config.toString(), isNot(contains('right-token')));
    });
  });

  group('ConnectionChecker', () {
    test('a healthy server with a good token is ok', () async {
      final adapter = FakeAdapter();
      final result = await _checker(adapter).check(_config);

      expect(result, isA<ConnectionOk>());
      expect(adapter.requestedTokens, ['Bearer right-token']);
    });

    test('an unreachable host is not reported as a bad token', () async {
      // The whole point of probing /health first: a wrong address must blame
      // the address field, not send someone hunting for a token that's fine.
      final result =
          await _checker(FakeAdapter(throwOn: '/health')).check(_config);

      expect(result, isA<ConnectionUnreachable>());
    });

    test('a reachable box that is not a vault says so', () async {
      final adapter = FakeAdapter(healthBody: '<html>router login</html>');
      final result = await _checker(adapter).check(_config);

      expect(result, isA<ConnectionNotVault>());
      expect(
        adapter.requestedTokens,
        isEmpty,
        reason: 'no point sending the token somewhere that is not our server',
      );
    });

    test('a 401 on the guarded probe is a bad token', () async {
      final result =
          await _checker(FakeAdapter(authStatus: 401)).check(_config);

      expect(result, isA<ConnectionBadToken>());
    });

    test('an unexpected status is reported verbatim, not guessed at',
        () async {
      final result =
          await _checker(FakeAdapter(authStatus: 502)).check(_config);

      expect(result, isA<ConnectionFailed>());
      expect((result as ConnectionFailed).detail, contains('502'));
    });

    test('an empty address never leaves the device', () async {
      final adapter = FakeAdapter();
      final result = await _checker(adapter).check(ServerConfig.empty);

      expect(result, isA<ConnectionUnreachable>());
      expect(adapter.requestedTokens, isEmpty);
    });
  });

  group('SetupController', () {
    ProviderContainer container(
      FakeAdapter adapter, {
      ServerConfig initial = ServerConfig.empty,
      AppDatabase? db,
      ServerConfigStore? store,
    }) {
      final c = ProviderContainer(
        overrides: [
          bootstrapServerConfigProvider.overrideWithValue(initial),
          serverConfigStoreProvider
              .overrideWithValue(store ?? InMemoryServerConfigStore()),
          connectionCheckerProvider.overrideWithValue(_checker(adapter)),
          if (db != null) appDatabaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('a verified server is saved and the app becomes configured',
        () async {
      final store = InMemoryServerConfigStore();
      final c = container(FakeAdapter(), store: store);
      final setup = c.read(setupControllerProvider.notifier);

      setup.setUrl('192.168.1.20:3000/api/v1/');
      setup.setToken('right-token');
      expect(await setup.submit(), isTrue);

      expect(c.read(isConfiguredProvider), isTrue);
      // Normalized on the way in, so the stored value is canonical.
      expect(c.read(serverConfigProvider).baseUrl, 'http://192.168.1.20:3000');
      expect((await store.read())!.apiToken, 'right-token');
    });

    test('a bad token blames the token field and saves nothing', () async {
      final store = InMemoryServerConfigStore();
      final c = container(FakeAdapter(authStatus: 401), store: store);
      final setup = c.read(setupControllerProvider.notifier);

      setup.setUrl('192.168.1.20:3000');
      setup.setToken('wrong');
      expect(await setup.submit(), isFalse);

      final state = c.read(setupControllerProvider);
      expect(state.tokenError, isNotNull);
      expect(state.urlError, isNull);
      expect(c.read(isConfiguredProvider), isFalse);
      // Back to an editable form, not stuck on the spinner — otherwise the
      // error is invisible and there is no way to try again.
      expect(state.phase, SetupPhase.editing);
      expect(state.canSubmit, isTrue);
      expect(await store.read(), isNull,
          reason: 'an unverified server must never be persisted');
    });

    test('an unreachable host blames the address field', () async {
      final c = container(FakeAdapter(throwOn: '/health'));
      final setup = c.read(setupControllerProvider.notifier);

      setup.setUrl('192.168.9.9:3000');
      setup.setToken('right-token');
      await setup.submit();

      final state = c.read(setupControllerProvider);
      expect(state.urlError, isNotNull);
      expect(state.tokenError, isNull);
    });

    test('a malformed address fails before any request', () async {
      final adapter = FakeAdapter();
      final c = container(adapter);
      final setup = c.read(setupControllerProvider.notifier);

      setup.setUrl('ftp://host');
      setup.setToken('right-token');
      expect(await setup.submit(), isFalse);

      expect(c.read(setupControllerProvider).urlError,
          ServerUrlError.badScheme.message);
      expect(adapter.requestedTokens, isEmpty);
    });

    test('submit is a no-op while a field is empty', () async {
      final c = container(FakeAdapter());
      final setup = c.read(setupControllerProvider.notifier);

      setup.setUrl('192.168.1.20:3000');
      expect(c.read(setupControllerProvider).canSubmit, isFalse);
      expect(await setup.submit(), isFalse);
    });

    test('reconfiguring starts from the current server', () {
      final c = container(FakeAdapter(), initial: _config);
      final state = c.read(setupControllerProvider);

      expect(state.url, _config.baseUrl);
      expect(state.token, _config.apiToken);
    });
  });

  group('switching servers', () {
    // Counts clears instead of touching the real flutter_cache_manager, which
    // raises an unhandled async MissingPluginException under flutter_test the
    // moment its Config is constructed.
    var coverClears = 0;
    // The group body runs once, so the counter must be reset per test or it
    // carries the previous test's clears in.
    setUp(() => coverClears = 0);

    /// Put one row in the mirror so a wipe is observable.
    Future<void> seed(AppDatabase db) async {
      await db.into(db.localManga).insert(
            LocalMangaCompanion.insert(
              id: 'title-1',
              rowVersion: '1',
              sourceId: '1',
              title: 'Seeded',
              titleLower: 'seeded',
            ),
          );
    }

    Future<int> titleCount(AppDatabase db) async =>
        (await db.select(db.localManga).get()).length;

    test('pointing at a different server clears the local mirror', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      await seed(db);

      final c = ProviderContainer(
        overrides: [
          bootstrapServerConfigProvider.overrideWithValue(_config),
          serverConfigStoreProvider
              .overrideWithValue(InMemoryServerConfigStore(_config)),
          appDatabaseProvider.overrideWithValue(db),
          coverCacheCleanerProvider
              .overrideWithValue(() async => coverClears++),
        ],
      );
      addTearDown(c.dispose);

      await c.read(serverConfigProvider.notifier).save(
            const ServerConfig(
              baseUrl: 'http://10.0.0.5:3000',
              apiToken: 'other-token',
            ),
          );

      expect(await titleCount(db), 0,
          reason: "one server's titles must never show under another's login");
      // Cover art is keyed by manga id, which two servers can both mint.
      expect(coverClears, 1);
    });

    test('rotating the token on the same server keeps the mirror', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      await seed(db);

      final c = ProviderContainer(
        overrides: [
          bootstrapServerConfigProvider.overrideWithValue(_config),
          serverConfigStoreProvider
              .overrideWithValue(InMemoryServerConfigStore(_config)),
          appDatabaseProvider.overrideWithValue(db),
          coverCacheCleanerProvider
              .overrideWithValue(() async => coverClears++),
        ],
      );
      addTearDown(c.dispose);

      await c
          .read(serverConfigProvider.notifier)
          .save(_config.copyWith(apiToken: 'rotated'));

      expect(await titleCount(db), 1,
          reason: 'the cached data is still valid for the same server');
      expect(coverClears, 0);
    });

    test('disconnecting forgets the server and wipes the mirror', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      await seed(db);
      final store = InMemoryServerConfigStore(_config);

      final c = ProviderContainer(
        overrides: [
          bootstrapServerConfigProvider.overrideWithValue(_config),
          serverConfigStoreProvider.overrideWithValue(store),
          appDatabaseProvider.overrideWithValue(db),
          coverCacheCleanerProvider
              .overrideWithValue(() async => coverClears++),
        ],
      );
      addTearDown(c.dispose);

      await c.read(serverConfigProvider.notifier).clear();

      expect(c.read(isConfiguredProvider), isFalse);
      expect(await store.read(), isNull);
      expect(await titleCount(db), 0);
    });
  });

  group('SetupScreen', () {
    testWidgets('reports a rejected token under the token field',
        (tester) async {
      useTallSurface(tester);
      final c = ProviderContainer(
        overrides: [
          bootstrapServerConfigProvider.overrideWithValue(ServerConfig.empty),
          serverConfigStoreProvider
              .overrideWithValue(InMemoryServerConfigStore()),
          connectionCheckerProvider
              .overrideWithValue(_checker(FakeAdapter(authStatus: 401))),
        ],
      );
      addTearDown(c.dispose);

      // Driven through the controller rather than by tapping Connect: the
      // in-flight state shows a CircularProgressIndicator, which animates
      // forever, so `pumpAndSettle` can never settle across the tap. What this
      // test is for is the wiring of a rejected token to the right field —
      // the tap path itself is covered by the controller tests above.
      // `runAsync`, because Dio's request completes on the real event loop and
      // a widget test's fake clock never services it.
      await tester.runAsync(() async {
        final setup = c.read(setupControllerProvider.notifier);
        setup.setUrl('192.168.1.20:3000');
        setup.setToken('nope');
        await setup.submit();
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(theme: buildAppTheme(), home: const SetupScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('token was rejected'), findsOneWidget);
      expect(c.read(isConfiguredProvider), isFalse);
    });

    testWidgets('the token field is obscured until revealed', (tester) async {
      useTallSurface(tester);
      final c = ProviderContainer(
        overrides: [
          bootstrapServerConfigProvider.overrideWithValue(ServerConfig.empty),
          serverConfigStoreProvider
              .overrideWithValue(InMemoryServerConfigStore()),
          connectionCheckerProvider.overrideWithValue(_checker(FakeAdapter())),
        ],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(theme: buildAppTheme(), home: const SetupScreen()),
        ),
      );

      TextField tokenField() =>
          tester.widget<TextField>(find.byType(TextField).last);

      expect(tokenField().obscureText, isTrue);
      await tester.tap(find.byTooltip('Show token'));
      await tester.pump();
      expect(tokenField().obscureText, isFalse);

      // The cells enter on a staggered delay; let those timers finish or the
      // binding reports them as leaked.
      await tester.pumpAndSettle();
    });
  });
}

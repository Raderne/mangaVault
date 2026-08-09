import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/server_config.dart';
import 'core/config/server_config_controller.dart';
import 'core/config/server_config_store.dart';
import 'features/updates/update_controller.dart';
import 'router.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Read the saved server config *before* the first frame. The router's
  // redirect guard has to decide synchronously whether the app is set up —
  // resolving it asynchronously would flash the dashboard for one frame before
  // bouncing to setup.
  const store = SecureServerConfigStore();
  final saved = await store.read() ?? ServerConfig.empty;

  // An explicit container so the launch-time update check can run from `main`
  // rather than from a widget's initState. Nothing in the tree should own it:
  // widget tests pump individual screens, and a check wired into the app shell
  // would fire a real GitHub request in every one of them.
  final container = ProviderContainer(
    overrides: [
      serverConfigStoreProvider.overrideWithValue(store),
      bootstrapServerConfigProvider.overrideWithValue(saved),
    ],
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MangaVaultApp(),
    ),
  );

  // After the first frame, so the check never delays the first paint. It is
  // throttled and fails silently — see UpdateController.autoCheck. It talks to
  // GitHub, not to the user's server, so it runs even before setup.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(container.read(updateControllerProvider.notifier).autoCheck());
  });
}

class MangaVaultApp extends ConsumerWidget {
  const MangaVaultApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Manga Vault',
      theme: buildAppTheme(),
      routerConfig: ref.watch(routerProvider),
      debugShowCheckedModeBanner: false,
    );
  }
}

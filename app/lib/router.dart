import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/config/server_config_controller.dart';
import 'features/about/about_screen.dart';
import 'features/backups/backups_screen.dart';
import 'features/backups/export/export_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/library/deleted_titles_screen.dart';
import 'features/library/library_screen.dart';
import 'features/setup/setup_screen.dart';
import 'features/title_details/title_details_screen.dart';
import 'widgets/entrance_fade.dart';
import 'widgets/app_shell.dart';

/// The app's router.
///
/// A provider rather than a top-level constant because it now depends on
/// runtime state: until the user has connected the app to their own server,
/// **every** route redirects to [kSetupRoute]. Guarding centrally here — rather
/// than checking in each screen — is what makes it impossible to reach a screen
/// that would fire an unauthenticated request.
final routerProvider = Provider<GoRouter>((ref) {
  // go_router re-evaluates `redirect` when this notifies, which is how
  // connecting or disconnecting moves the user without an explicit navigation.
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);
  ref.listen(isConfiguredProvider, (_, _) => refresh.value++);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final configured = ref.read(isConfiguredProvider);
      final atSetup = state.matchedLocation == kSetupRoute;
      if (!configured && !atSetup) return kSetupRoute;
      if (configured && atSetup) return '/';
      return null;
    },
    routes: [
      // Outside the shell: there is no library to browse yet, so the bottom
      // nav would be three dead ends.
      GoRoute(
        path: kSetupRoute,
        builder: (_, _) => const SetupScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const DashboardScreen(),
              routes: [
                // Nested under Dashboard: About is reached from its app bar, so
                // the tab stays selected and back lands on the dashboard.
                GoRoute(
                  path: 'about',
                  builder: (_, _) => const AboutScreen(),
                  routes: [
                    // Changing servers reuses the setup form. A separate route
                    // from `/setup`, which the redirect above bounces away from
                    // once configured.
                    GoRoute(
                      path: 'server',
                      builder: (_, _) =>
                          const SetupScreen(isReconfiguring: true),
                    ),
                  ],
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/library',
              builder: (_, _) => const LibraryScreen(),
              routes: [
                GoRoute(
                  path: 'deleted',
                  builder: (_, _) => const DeletedTitlesScreen(),
                ),
                GoRoute(
                  path: 'title/:id',
                  pageBuilder: (context, state) => CustomTransitionPage<void>(
                    key: state.pageKey,
                    child:
                        TitleDetailsScreen(titleId: state.pathParameters['id']!),
                    transitionDuration: const Duration(milliseconds: 260),
                    reverseTransitionDuration: const Duration(milliseconds: 220),
                    // A soft fade lets the shared-element cover Hero lead the
                    // eye, instead of the platform slide competing with it.
                    transitionsBuilder: (_, animation, _, child) =>
                        FadeTransition(
                      opacity: CurvedAnimation(
                          parent: animation, curve: kEntranceCurve),
                      child: child,
                    ),
                  ),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/backups',
              builder: (_, _) => const BackupsScreen(),
              routes: [
                // Nested, so the wizard keeps the Backups tab selected and a
                // back-swipe returns to the hub it was launched from.
                GoRoute(
                  path: 'export',
                  builder: (_, _) => const ExportScreen(),
                ),
              ],
            ),
          ]),
        ],
      ),
    ],
  );
});

/// Route of the change-server form, reached from About.
const String kChangeServerRoute = '/about/server';

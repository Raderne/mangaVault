import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'features/backups/backups_screen.dart';
import 'features/backups/export/export_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/library/deleted_titles_screen.dart';
import 'features/library/library_screen.dart';
import 'features/title_details/title_details_screen.dart';
import 'widgets/entrance_fade.dart';
import 'widgets/app_shell.dart';

final router = GoRouter(
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
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
                  child: TitleDetailsScreen(titleId: state.pathParameters['id']!),
                  transitionDuration: const Duration(milliseconds: 260),
                  reverseTransitionDuration: const Duration(milliseconds: 220),
                  // A soft fade lets the shared-element cover Hero lead the eye,
                  // instead of the platform slide competing with it.
                  transitionsBuilder: (_, animation, _, child) => FadeTransition(
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

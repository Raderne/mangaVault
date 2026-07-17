import 'package:go_router/go_router.dart';

import 'features/backups/backups_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/library/library_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/title_details/title_details_screen.dart';
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
                path: 'title/:id',
                builder: (context, state) =>
                    TitleDetailsScreen(titleId: state.pathParameters['id']!),
              ),
            ],
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/backups', builder: (_, _) => const BackupsScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
        ]),
      ],
    ),
  ],
);

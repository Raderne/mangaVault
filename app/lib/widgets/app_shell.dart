import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/library/library_filter_sheet.dart';

/// Scaffold with the glass bottom navigation bar hosting the three main tabs.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// Re-tapping the active tab normally just pops that branch back to its root.
  /// On Library, when we're *already* at the root, there's nothing to pop — so
  /// the gesture opens the filter & sort sheet instead. (The app bar's tune
  /// icon is the discoverable path to the same sheet.)
  void _onDestinationSelected(BuildContext context, int index) {
    final isReselect = index == navigationShell.currentIndex;
    final atLibraryRoot = GoRouter.of(context)
            .routeInformationProvider
            .value
            .uri
            .path ==
        '/library';

    navigationShell.goBranch(index, initialLocation: isReselect);

    if (isReselect && index == kLibraryBranchIndex && atLibraryRoot) {
      showLibraryFilterSheet(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: (index) =>
                _onDestinationSelected(context, index),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'Dashboard',
              ),
              NavigationDestination(
                icon: Icon(Icons.collections_bookmark_outlined),
                selectedIcon: Icon(Icons.collections_bookmark),
                label: 'Library',
              ),
              NavigationDestination(
                icon: Icon(Icons.cloud_upload_outlined),
                selectedIcon: Icon(Icons.cloud_upload),
                label: 'Backups',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/files/vault_file_system.dart';
import '../../theme/app_accents.dart';
import 'file_browser_controller.dart';
import 'file_browser_screen.dart';

/// Pick one or more backups to import.
///
/// Resolves to the chosen files, or `null` if the browser was dismissed. Pushed
/// on the **root** navigator so it covers the tab bar: choosing a file is a
/// focused, blocking task, and a half-covered shell invites a tab tap that
/// strands the flow.
Future<List<FileEntry>?> openFileBrowser(
  BuildContext context, {
  VaultAccent accent = VaultAccent.violet,
  VoidCallback? onUseSystemPicker,
}) {
  return pushFileBrowser(
    Navigator.of(context, rootNavigator: true),
    accent: accent,
    onUseSystemPicker: onUseSystemPicker,
  );
}

/// Pick where an export should be written. Resolves to the full destination
/// path, or `null` if dismissed — which the caller must treat as a cancel, not
/// a failure.
Future<String?> openSaveBrowser(
  BuildContext context, {
  required String suggestedName,
  VaultAccent accent = VaultAccent.emerald,
  VoidCallback? onUseSystemPicker,
}) {
  return pushSaveBrowser(
    Navigator.of(context, rootNavigator: true),
    suggestedName: suggestedName,
    accent: accent,
    onUseSystemPicker: onUseSystemPicker,
  );
}

/// The same two entry points, against a [NavigatorState] captured earlier.
///
/// A caller that only reaches the browser *after* an await needs these: the
/// widget it started from may be gone by then, and a `BuildContext` looked up
/// at that point is either unmounted or belongs to something else. The export
/// flow is exactly that case — the action bar is torn down the moment the build
/// starts, long before there is a file to save. A `NavigatorState` outlives it.
Future<List<FileEntry>?> pushFileBrowser(
  NavigatorState navigator, {
  VaultAccent accent = VaultAccent.violet,
  VoidCallback? onUseSystemPicker,
}) {
  return navigator.push<List<FileEntry>>(
    MaterialPageRoute(
      builder: (_) => FileBrowserScreen(
        mode: FileBrowserMode.open,
        accent: accent,
        title: 'Select Backup',
        onUseSystemPicker: onUseSystemPicker,
      ),
    ),
  );
}

Future<String?> pushSaveBrowser(
  NavigatorState navigator, {
  required String suggestedName,
  VaultAccent accent = VaultAccent.emerald,
  VoidCallback? onUseSystemPicker,
}) {
  return navigator.push<String>(
    MaterialPageRoute(
      builder: (_) => FileBrowserScreen(
        mode: FileBrowserMode.save,
        accent: accent,
        title: 'Save Backup',
        suggestedName: suggestedName,
        onUseSystemPicker: onUseSystemPicker,
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/core/files/file_access.dart';
import 'package:mangavault/core/files/storage_roots.dart';
import 'package:mangavault/core/files/vault_file_system.dart';
import 'package:mangavault/features/files/file_browser_controller.dart';
import 'package:mangavault/features/files/file_browser_screen.dart';
import 'package:mangavault/theme/app_accents.dart';
import 'package:mangavault/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_file_system.dart';

const _root = '/storage/emulated/0';
const _downloads = '$_root/Download';

/// Access states, seeded rather than requested — the browser must be testable
/// without the permission_handler plugin.
class _GrantedAccess extends FileAccessController {
  @override
  FileAccessStatus build() => FileAccessStatus.granted;
}

class _DeniedAccess extends FileAccessController {
  @override
  FileAccessStatus build() => FileAccessStatus.denied;
}

/// A tree standing in for a phone that has run Mihon.
FakeFileSystem _tree() {
  final fs = FakeFileSystem()
    ..addDirectory(_root)
    ..addDirectory('$_root/Mihon/autobackup')
    ..addDirectory('$_root/Empty')
    ..addFile(
      '$_downloads/app.mihon_2026-08-01.tachibk',
      size: 3000,
      modifiedMillis: 3000000,
    )
    ..addFile(
      '$_downloads/app.komikku_2026-01-01.tachibk',
      size: 1000,
      modifiedMillis: 1000000,
    )
    ..addFile('$_downloads/holiday.jpg', size: 500, modifiedMillis: 2000000)
    ..addFile('$_root/Mihon/autobackup/auto.tachibk', size: 2000);
  return fs;
}

/// A container over the fake disk and a seeded permission state.
///
/// Returns the container rather than the override list because `Override`
/// isn't exported from `flutter_riverpod`'s top-level library, so the list has
/// no nameable type here.
ProviderContainer _container(FakeFileSystem fs, {bool granted = true}) {
  final container = ProviderContainer(overrides: [
    vaultFileSystemProvider.overrideWithValue(fs),
    fileAccessProvider.overrideWith(
      granted ? _GrantedAccess.new : _DeniedAccess.new,
    ),
  ]);
  addTearDown(container.dispose);
  return container;
}

/// Push the browser through a real route, so `Navigator.pop` has somewhere to
/// go and the popped result can be captured.
Future<List<Object?>> _pumpBrowser(
  WidgetTester tester,
  FakeFileSystem fs, {
  FileBrowserMode mode = FileBrowserMode.open,
  String suggestedName = '',
  bool granted = true,
}) async {
  // A real phone width. The default 800dp test surface is wide enough to hide
  // a footer or toolbar that overflows on the device it actually ships to.
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(400, 900);
  addTearDown(tester.view.reset);

  final results = <Object?>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        vaultFileSystemProvider.overrideWithValue(fs),
        fileAccessProvider.overrideWith(
          granted ? _GrantedAccess.new : _DeniedAccess.new,
        ),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                results.add(
                  await Navigator.of(context).push<Object>(
                    MaterialPageRoute(
                      builder: (_) => FileBrowserScreen(
                        mode: mode,
                        accent: VaultAccent.violet,
                        title: mode == FileBrowserMode.open
                            ? 'Select Backup'
                            : 'Save Backup',
                        suggestedName: suggestedName,
                      ),
                    ),
                  ),
                );
              },
              child: const Text('open browser'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open browser'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('FileBrowserController', () {
    /// One container, one controller, driven directly — swapping a provider
    /// override between pumps does not re-run a notifier's `build()`.
    Future<(ProviderContainer, FileBrowserController)> open(
      FakeFileSystem fs, {
      FileBrowserMode mode = FileBrowserMode.open,
    }) async {
      final container = _container(fs);
      final controller = container.read(fileBrowserProvider.notifier);
      await controller.open(mode: mode);
      return (container, controller);
    }

    test('opens at the volume root and lists folders before files', () async {
      final (container, _) = await open(_tree());
      final state = container.read(fileBrowserProvider);

      expect(state.directory, _root);
      expect(state.visible.map((e) => e.name), ['Download', 'Empty', 'Mihon']);
    });

    test('newest-first is the default sort, and name reorders', () async {
      final (container, controller) = await open(_tree());
      await controller.navigateTo(_downloads);

      // Only the two backups are visible; the .jpg is filtered out.
      expect(
        container.read(fileBrowserProvider).visible.map((e) => e.name),
        ['app.mihon_2026-08-01.tachibk', 'app.komikku_2026-01-01.tachibk'],
      );

      controller.setSort(FileSort.name);
      expect(
        container.read(fileBrowserProvider).visible.map((e) => e.name),
        ['app.komikku_2026-01-01.tachibk', 'app.mihon_2026-08-01.tachibk'],
      );
    });

    test('non-backups appear only when "all files" is on', () async {
      final (container, controller) = await open(_tree());
      await controller.navigateTo(_downloads);
      expect(container.read(fileBrowserProvider).hiddenFileCount, 1);

      controller.toggleShowAllFiles();
      final state = container.read(fileBrowserProvider);
      expect(state.visible.map((e) => e.name), contains('holiday.jpg'));
      // Visible, but never pickable: the import flow can't take it.
      expect(
        state.canSelect(state.visible.firstWhere((e) => e.name == 'holiday.jpg')),
        isFalse,
      );
    });

    test('search filters the current folder only', () async {
      final (container, controller) = await open(_tree());
      await controller.navigateTo(_downloads);
      controller.setSearch('komikku');

      expect(
        container.read(fileBrowserProvider).visible.map((e) => e.name),
        ['app.komikku_2026-01-01.tachibk'],
      );
    });

    test('navigating clears the search and the selection', () async {
      final (container, controller) = await open(_tree());
      await controller.navigateTo(_downloads);
      final entry = container.read(fileBrowserProvider).visible.first;
      controller.toggleSelected(entry);
      controller.setSearch('mihon');
      expect(container.read(fileBrowserProvider).selected, hasLength(1));

      await controller.navigateTo(_root);
      final state = container.read(fileBrowserProvider);
      expect(state.selected, isEmpty);
      expect(state.search, isEmpty);
    });

    test('selection accumulates and toggles back off', () async {
      final (container, controller) = await open(_tree());
      await controller.navigateTo(_downloads);
      final visible = container.read(fileBrowserProvider).visible;

      controller.toggleSelected(visible[0]);
      controller.toggleSelected(visible[1]);
      expect(controller.selectedEntries, hasLength(2));

      controller.toggleSelected(visible[0]);
      expect(controller.selectedEntries.single.name, visible[1].name);
    });

    test('save mode selects nothing, even a real backup', () async {
      final (container, controller) =
          await open(_tree(), mode: FileBrowserMode.save);
      await controller.navigateTo(_downloads);
      final entry = container.read(fileBrowserProvider).visible.first;

      controller.toggleSelected(entry);
      expect(container.read(fileBrowserProvider).selected, isEmpty);
    });

    test('breadcrumbs jump to an ancestor, and up stops at the root', () async {
      final (container, controller) = await open(_tree());
      await controller.navigateTo('$_root/Mihon/autobackup');
      expect(container.read(fileBrowserProvider).crumbs, ['Mihon', 'autobackup']);

      await controller.jumpToCrumb(1);
      expect(container.read(fileBrowserProvider).directory, '$_root/Mihon');

      await controller.goUp();
      expect(container.read(fileBrowserProvider).directory, _root);
      expect(container.read(fileBrowserProvider).isAtVolumeRoot, isTrue);

      // Already at the root: going up must not climb into /storage, which is
      // unreadable and would look like the browser broke.
      await controller.goUp();
      expect(container.read(fileBrowserProvider).directory, _root);
    });

    test('quick access offers Downloads and the detected Mihon folder', () async {
      final (container, _) = await open(_tree());
      final labels =
          container.read(fileBrowserProvider).quickFolders.map((f) => f.label);

      expect(labels, containsAll(['Downloads', 'Mihon backups']));
      // Not on this device, so not offered.
      expect(labels, isNot(contains('Tachiyomi backups')));
    });

    test('an unreadable folder surfaces as an error, keeping the location',
        () async {
      final fs = _tree()..unreadable.add('$_root/Empty');
      final (container, controller) = await open(fs);
      await controller.navigateTo('$_root/Empty');

      final state = container.read(fileBrowserProvider);
      expect(state.entries.hasError, isTrue);
      expect(state.directory, '$_root/Empty');
    });

    test('createFolder rejects a duplicate and navigates into a new one',
        () async {
      final fs = _tree();
      final (container, controller) = await open(fs, mode: FileBrowserMode.save);

      expect(await controller.createFolder('Empty'), 'That folder already exists.');
      expect(await controller.createFolder('Vault/x'), isNotNull);

      expect(await controller.createFolder('Vault'), isNull);
      expect(container.read(fileBrowserProvider).directory, '$_root/Vault');
    });

    test('a remembered folder is reopened, unless it has gone away', () async {
      final fs = _tree();
      final container = _container(fs);
      container.read(folderMemoryProvider.notifier).remember(_downloads);

      final controller = container.read(fileBrowserProvider.notifier);
      await controller.open(mode: FileBrowserMode.open);
      expect(container.read(fileBrowserProvider).directory, _downloads);

      container.read(folderMemoryProvider.notifier).remember('$_root/Gone');
      await controller.open(mode: FileBrowserMode.open);
      expect(container.read(fileBrowserProvider).directory, _root);
    });
  });

  group('FileBrowserScreen', () {
    testWidgets('picking backups pops them to the caller', (tester) async {
      final fs = _tree();
      final results = await _pumpBrowser(tester, fs);

      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();

      expect(find.text('holiday.jpg'), findsNothing);
      expect(find.text('Select one or more backups'), findsOneWidget);

      await tester.tap(find.text('app.mihon_2026-08-01.tachibk'));
      await tester.pumpAndSettle();
      expect(find.text('1 file selected'), findsOneWidget);

      await tester.tap(find.text('Import 1'));
      await tester.pumpAndSettle();

      final picked = results.single as List<FileEntry>;
      expect(picked.single.path, '$_downloads/app.mihon_2026-08-01.tachibk');
    });

    testWidgets('the empty state says how many files were hidden',
        (tester) async {
      final fs = _tree()
        ..addDirectory('$_root/Photos')
        ..addFile('$_root/Photos/a.jpg')
        ..addFile('$_root/Photos/b.jpg');
      await _pumpBrowser(tester, fs);

      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();

      expect(find.text('No backups here'), findsOneWidget);
      expect(
        find.textContaining('2 other file(s) are hidden'),
        findsOneWidget,
      );
    });

    testWidgets('back goes up a folder before it closes the browser',
        (tester) async {
      final fs = _tree();
      await _pumpBrowser(tester, fs);

      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      expect(find.text('app.mihon_2026-08-01.tachibk'), findsOneWidget);

      // The system back gesture, not the app bar's close button — this is the
      // one that has to be intercepted by `PopScope`.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Still in the browser, one level up.
      expect(find.text('Select Backup'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
    });

    testWidgets('saving over an existing file asks first', (tester) async {
      final fs = _tree();
      final results = await _pumpBrowser(
        tester,
        fs,
        mode: FileBrowserMode.save,
        suggestedName: 'app.mihon_2026-08-01.tachibk',
      );

      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save here'));
      await tester.pumpAndSettle();

      expect(find.text('Replace file?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(results, isEmpty); // still open, nothing chosen

      await tester.tap(find.text('Save here'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();

      expect(results.single, '$_downloads/app.mihon_2026-08-01.tachibk');
    });

    testWidgets('a name typed without an extension gets .tachibk back',
        (tester) async {
      final fs = _tree();
      final results =
          await _pumpBrowser(tester, fs, mode: FileBrowserMode.save);

      await tester.enterText(find.byType(TextField).last, 'my library');
      await tester.tap(find.text('Save here'));
      await tester.pumpAndSettle();

      expect(results.single, '$_root/my library.tachibk');
    });

    testWidgets('without access the gate replaces the listing', (tester) async {
      final fs = _tree();
      await _pumpBrowser(tester, fs, granted: false);

      expect(find.text('Let MangaVault browse your files'), findsOneWidget);
      expect(find.text('Grant file access'), findsOneWidget);
      // No footer, and nothing was listed.
      expect(find.text('Select one or more backups'), findsNothing);
      expect(find.text('Download'), findsNothing);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/files/file_access.dart';
import '../../core/files/vault_file_system.dart';
import '../../theme/app_accents.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/bento_cell.dart';
import '../../widgets/entrance_fade.dart';
import '../../widgets/pill_button.dart';
import 'file_access_gate.dart';
import 'file_browser_controller.dart';
import 'file_browser_widgets.dart';

/// MangaVault's own file selector.
///
/// A full-screen route rather than a sheet: save mode needs the keyboard, and
/// the back gesture has to mean "up one folder" — which fights a sheet whose
/// back gesture already means "dismiss".
class FileBrowserScreen extends ConsumerStatefulWidget {
  const FileBrowserScreen({
    super.key,
    required this.mode,
    required this.accent,
    required this.title,
    this.suggestedName = '',
    this.onUseSystemPicker,
  });

  final FileBrowserMode mode;
  final VaultAccent accent;
  final String title;

  /// Save mode only: the filename to prefill.
  final String suggestedName;

  /// Shown on the permission gate. Popping with a `null` result and letting the
  /// caller fall back keeps the fallback logic in one place.
  final VoidCallback? onUseSystemPicker;

  @override
  ConsumerState<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends ConsumerState<FileBrowserScreen> {
  late final TextEditingController _fileName =
      TextEditingController(text: widget.suggestedName);
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openIfGranted());
  }

  @override
  void dispose() {
    _fileName.dispose();
    super.dispose();
  }

  /// Load the first listing, but only once access exists — otherwise every
  /// folder read fails and the gate is buried under an error.
  void _openIfGranted() {
    if (_opened || !mounted) return;
    if (!ref.read(fileAccessProvider).isGranted) return;
    _opened = true;
    ref.read(fileBrowserProvider.notifier).open(mode: widget.mode);
  }

  FileBrowserController get _controller =>
      ref.read(fileBrowserProvider.notifier);

  void _confirmOpen() {
    final picked = _controller.selectedEntries;
    if (picked.isEmpty) return;
    _controller.rememberCurrentFolder();
    Navigator.of(context).pop(picked);
  }

  Future<void> _confirmSave() async {
    final state = ref.read(fileBrowserProvider);
    final name = _normalizedFileName();
    if (name == null) return;

    final path = p.posix.join(state.directory, name);
    if (await ref.read(vaultFileSystemProvider).exists(path)) {
      if (!mounted) return;
      final replace = await _confirmOverwrite(name);
      if (replace != true) return;
    }
    if (!mounted) return;
    _controller.rememberCurrentFolder();
    Navigator.of(context).pop(path);
  }

  /// Validates the typed filename and puts the extension back if it was
  /// deleted — the format is identified by its name, and a `.tachibk` saved
  /// without its suffix is a file no reading app will offer to restore.
  String? _normalizedFileName() {
    final raw = _fileName.text.trim();
    if (raw.isEmpty) {
      _showError('Give the backup a filename.');
      return null;
    }
    if (RegExp(r'[\\/:*?"<>|]').hasMatch(raw)) {
      _showError(r'A filename cannot contain \ / : * ? " < > |');
      return null;
    }
    return isBackupFileName(raw) ? raw : '$raw.tachibk';
  }

  Future<bool?> _confirmOverwrite(String name) => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace file?'),
          content: Text(
            '$name already exists in this folder. Saving will overwrite it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );

  Future<void> _newFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          inputFormatters: [
            FilteringTextInputFormatter.deny(RegExp(r'[\\/:*?"<>|]')),
          ],
          decoration: const InputDecoration(
            labelText: 'Folder name',
            hintText: 'MangaVault backups',
            isDense: true,
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    final error = await _controller.createFolder(name);
    if (error != null) _showError(error);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(fileAccessProvider);
    // The grant lands while this screen is open (the user is sent to Android's
    // settings and comes back), so load the first listing on that transition
    // rather than only in initState.
    ref.listen(fileAccessProvider, (_, next) {
      if (next.isGranted) _openIfGranted();
    });

    final state = ref.watch(fileBrowserProvider);
    final granted = access.isGranted;

    return PopScope(
      // Back means "up a folder" until there is nowhere left to go, at which
      // point it closes the browser.
      canPop: !granted || state.isAtVolumeRoot,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _controller.goUp();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            if (granted)
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: _controller.refresh,
              ),
          ],
        ),
        body: granted ? _browser(state) : _gate(),
        bottomNavigationBar: granted ? _footer(state) : null,
      ),
    );
  }

  Widget _gate() => ListView(
        padding: const EdgeInsets.all(AppDimens.gutter),
        children: [
          FileAccessGate(
            onUseSystemPicker: widget.onUseSystemPicker == null
                ? null
                : () {
                    Navigator.of(context).pop();
                    widget.onUseSystemPicker!();
                  },
            systemPickerLabel: widget.mode == FileBrowserMode.open
                ? 'Use the system picker instead'
                : 'Use the system save dialog instead',
          ),
        ],
      );

  Widget _browser(FileBrowserState state) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.gutter,
            0,
            AppDimens.gutter,
            AppDimens.unit,
          ),
          child: BrowserLocationCell(
            state: state,
            accent: widget.accent,
            onJumpToCrumb: _controller.jumpToCrumb,
            onSwitchVolume: _controller.switchVolume,
          ),
        ),
        QuickAccessRow(
          folders: state.quickFolders,
          current: state.directory,
          onTap: (folder) => _controller.navigateTo(folder.path),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.gutter,
            AppDimens.unit,
            AppDimens.gutter,
            AppDimens.unit,
          ),
          child: BrowserToolbar(
            state: state,
            onSort: _controller.setSort,
            onSearch: _controller.setSearch,
            onToggleShowAll: _controller.toggleShowAllFiles,
          ),
        ),
        Expanded(child: _listing(state)),
      ],
    );
  }

  Widget _listing(FileBrowserState state) {
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedSwitcher(
      duration: still ? Duration.zero : const Duration(milliseconds: 260),
      reverseDuration: still ? Duration.zero : const Duration(milliseconds: 160),
      switchInCurve: kEntranceCurve,
      switchOutCurve: Curves.easeIn,
      // Keyed by folder, not by the async state: a cross-fade is how "you moved
      // somewhere else" reads. Rows are deliberately *not* staggered
      // individually — a recycled ListView row would replay its entrance every
      // time it scrolled back into view.
      child: KeyedSubtree(
        key: ValueKey('${state.directory}|${state.entries.isLoading}'),
        child: state.entries.when(
          loading: () => Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: widget.accent.color,
              ),
            ),
          ),
          error: (e, _) => _message(
            icon: Icons.lock_outline,
            accent: VaultAccent.rose,
            title: "Can't open this folder",
            body: '$e',
          ),
          data: (_) {
            final visible = state.visible;
            if (visible.isEmpty) return _empty(state);
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.gutter,
                0,
                AppDimens.gutter,
                AppDimens.gutter,
              ),
              itemCount: visible.length,
              itemBuilder: (context, i) {
                final entry = visible[i];
                final selectable = state.canSelect(entry);
                return FileRow(
                  key: ValueKey(entry.path),
                  entry: entry,
                  selected: state.selected.contains(entry.path),
                  selectable: selectable,
                  accent: widget.accent,
                  onTap: entry.isDirectory
                      ? () => _controller.navigateTo(entry.path)
                      : selectable
                          ? () => _controller.toggleSelected(entry)
                          : null,
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _empty(FileBrowserState state) {
    final hidden = state.hiddenFileCount;
    if (state.search.trim().isNotEmpty) {
      return _message(
        icon: Icons.search_off,
        accent: widget.accent,
        title: 'Nothing matches',
        body: 'No file or folder here is named like "${state.search.trim()}".',
      );
    }
    return _message(
      icon: Icons.folder_off_outlined,
      accent: widget.accent,
      title: hidden > 0 ? 'No backups here' : 'This folder is empty',
      body: hidden > 0
          // Saying how many were hidden is what stops this reading as a bug in
          // a folder the user knows is full of files.
          ? '$hidden other file(s) are hidden because they are not .tachibk or '
              '.json backups. Tap "All" above to show them.'
          : 'Nothing in this folder.',
    );
  }

  Widget _message({
    required IconData icon,
    required VaultAccent accent,
    required String title,
    required String body,
  }) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppDimens.gutter),
      children: [
        BentoCell(
          accent: accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AccentIconWell(icon: icon, accent: accent),
                  const SizedBox(width: AppDimens.unit * 1.5),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium!
                          .copyWith(color: accent.color),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimens.unit),
              Text(
                body,
                style: theme.textTheme.bodyMedium!
                    .copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _footer(FileBrowserState state) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.gutter,
            AppDimens.unit * 1.5,
            AppDimens.gutter,
            AppDimens.unit * 1.5,
          ),
          child: widget.mode == FileBrowserMode.open
              ? _openFooter(state)
              : _saveFooter(),
        ),
      ),
    );
  }

  Widget _openFooter(FileBrowserState state) {
    final count = state.selected.length;
    return Row(
      children: [
        Expanded(
          child: Text(
            count == 0
                ? 'Select one or more backups'
                : '$count file${count == 1 ? '' : 's'} selected',
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        const SizedBox(width: AppDimens.unit),
        PillButton(
          label: count == 0 ? 'Import' : 'Import $count',
          icon: Icons.upload_file,
          accent: widget.accent,
          onPressed: count == 0 ? null : _confirmOpen,
        ),
      ],
    );
  }

  Widget _saveFooter() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _fileName,
          inputFormatters: [
            FilteringTextInputFormatter.deny(RegExp(r'[\\/:*?"<>|]')),
          ],
          decoration: const InputDecoration(
            labelText: 'File name',
            isDense: true,
          ),
        ),
        const SizedBox(height: AppDimens.unit),
        Row(
          children: [
            // `Expanded` + `Align`, not a `Spacer`: at 400dp the two controls
            // together are wider than the row, and a Spacer has no give — the
            // secondary label is what should shrink, never the save button.
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _newFolder,
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  label: const Text(
                    'New folder',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppDimens.unit),
            PillButton(
              label: 'Save here',
              icon: Icons.save_alt,
              accent: widget.accent,
              onPressed: _confirmSave,
            ),
          ],
        ),
      ],
    );
  }
}

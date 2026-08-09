import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/backup_apps/backup_app_models.dart';
import '../../data/backup_apps/backup_apps_repository.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/bento_cell.dart';
import '../../widgets/selectable_chip.dart';

/// Ask which reading app a backup came from.
///
/// Backups are named `<applicationId>_<timestamp>.tachibk`, so normally the
/// filename answers this and the sheet never opens. It opens for a file that was
/// renamed, or came from a fork that doesn't follow the convention — and for
/// correcting a wrong tag before committing.
///
/// Resolves to the chosen application id, or `null` if the user dismissed it
/// (which leaves the backup unidentified — still importable).
Future<String?> showSourceAppSheet(
  BuildContext context, {
  required String fileName,
  String? current,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppDimens.cellRadius)),
    ),
    builder: (_) => _SourceAppSheet(fileName: fileName, current: current),
  );
}

class _SourceAppSheet extends ConsumerStatefulWidget {
  const _SourceAppSheet({required this.fileName, this.current});

  final String fileName;
  final String? current;

  @override
  ConsumerState<_SourceAppSheet> createState() => _SourceAppSheetState();
}

class _SourceAppSheetState extends ConsumerState<_SourceAppSheet> {
  final _nameController = TextEditingController();
  final _idController = TextEditingController();
  bool _adding = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    super.dispose();
  }

  /// Turn "My Reader" into "my.reader" so the user only has to type a name.
  /// An application id is what the backup filename actually carries, but asking
  /// for one up front is a bad first question.
  static String slugify(String displayName) => displayName
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '.')
      .replaceAll(RegExp(r'^\.+|\.+$'), '');

  Future<void> _submitNew() async {
    final displayName = _nameController.text.trim();
    final id = _idController.text.trim().isEmpty
        ? slugify(displayName)
        : _idController.text.trim().toLowerCase();

    if (displayName.isEmpty) {
      setState(() => _error = 'Give the app a name.');
      return;
    }
    if (id.length < 2) {
      setState(() => _error = "That name doesn't make a usable app id — "
          'type one below.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final created =
          await ref.read(backupAppsRepositoryProvider).create(id, displayName);
      ref.invalidate(backupAppsProvider);
      if (mounted) Navigator.of(context).pop(created.id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final apps = ref.watch(backupAppsProvider);

    return SafeArea(
      child: Padding(
        // Lift the sheet above the keyboard when the "add app" fields are open.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppDimens.cellPadding),
              child: Row(
                children: [
                  const AccentIconWell(icon: Icons.smartphone_rounded),
                  const SizedBox(width: AppDimens.unit * 1.5),
                  Expanded(
                    child: Text(
                      'Which app is this backup from?',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimens.unit * 1.5),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppDimens.cellPadding),
              child: NestedWell(
                child: Row(
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppDimens.unit),
                    Expanded(
                      child: Text(
                        widget.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall!
                            .copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppDimens.unit),
            Flexible(
              child: apps.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(AppDimens.cellPadding),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                // Reaching the registry is not required to import: the user can
                // still name the app by hand, or skip and leave it unknown.
                error: (_, _) => Padding(
                  padding: const EdgeInsets.all(AppDimens.cellPadding),
                  child: Text(
                    "Couldn't reach the server for the app list — add the app "
                    'below, or skip and tag it later.',
                    style: theme.textTheme.bodySmall!
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                data: (all) => _AppList(
                  apps: all,
                  current: widget.current,
                  onPick: (id) => Navigator.of(context).pop(id),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.cellPadding,
                AppDimens.unit,
                AppDimens.cellPadding,
                AppDimens.unit,
              ),
              child: _adding
                  ? _AddAppForm(
                      nameController: _nameController,
                      idController: _idController,
                      submitting: _submitting,
                      error: _error,
                      onCancel: () => setState(() {
                        _adding = false;
                        _error = null;
                      }),
                      onSubmit: _submitting ? null : _submitNew,
                    )
                  : Row(
                      children: [
                        TextButton.icon(
                          onPressed: () => setState(() => _adding = true),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add another app'),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(''),
                          child: const Text('Skip'),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Apps you've imported from before, then the rest of what the server knows.
///
/// The split matters: with a handful of curated apps plus anything you've added,
/// the list you actually reach for is short, and burying it in an alphabetical
/// list of everything would make the common case the slow one.
class _AppList extends StatelessWidget {
  const _AppList({
    required this.apps,
    required this.current,
    required this.onPick,
  });

  final List<BackupApp> apps;
  final String? current;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final used = apps.where((a) => a.used).toList();
    final unused = apps.where((a) => !a.used).toList();

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.cellPadding,
        vertical: AppDimens.unit,
      ),
      children: [
        if (used.isNotEmpty) ...[
          const CellLabel('Imported from before'),
          const SizedBox(height: AppDimens.unit),
          _chips(used),
          const SizedBox(height: AppDimens.unit * 2),
        ],
        if (unused.isNotEmpty) ...[
          CellLabel(used.isEmpty ? 'Reading apps' : 'Other known apps'),
          const SizedBox(height: AppDimens.unit),
          _chips(unused),
        ],
        if (apps.isEmpty)
          Text(
            'No apps known yet — add the one this backup came from.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }

  Widget _chips(List<BackupApp> list) => Wrap(
        spacing: AppDimens.unit,
        runSpacing: AppDimens.unit,
        children: [
          for (final app in list)
            SelectableChip(
              label: app.displayName,
              trailing: app.used ? '${app.titleCount}' : null,
              selected: app.id == current,
              onTap: () => onPick(app.id),
            ),
        ],
      );
}

class _AddAppForm extends StatelessWidget {
  const _AddAppForm({
    required this.nameController,
    required this.idController,
    required this.submitting,
    required this.error,
    required this.onCancel,
    required this.onSubmit,
  });

  final TextEditingController nameController;
  final TextEditingController idController;
  final bool submitting;
  final String? error;
  final VoidCallback onCancel;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'App name',
            hintText: 'Komikku',
            isDense: true,
          ),
        ),
        const SizedBox(height: AppDimens.unit),
        TextField(
          controller: idController,
          // The id is matched against the filename prefix, which is always
          // lower-case and never contains spaces.
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._-]')),
          ],
          decoration: const InputDecoration(
            labelText: 'Application id (optional)',
            hintText: 'app.komikku — from the backup filename',
            isDense: true,
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: AppDimens.unit),
          Text(
            error!,
            style: theme.textTheme.bodySmall!
                .copyWith(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: AppDimens.unit),
        Row(
          children: [
            TextButton(onPressed: onCancel, child: const Text('Cancel')),
            const Spacer(),
            FilledButton(
              onPressed: onSubmit,
              child: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Add'),
            ),
          ],
        ),
      ],
    );
  }
}

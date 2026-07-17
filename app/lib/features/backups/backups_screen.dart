import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../widgets/bento_cell.dart';
import '../../widgets/pill_button.dart';

/// Backup & Sources: import hub per the `backup_sources` mockup.
/// File upload + staged-import review arrive with the import API (M2).
class BackupsScreen extends StatelessWidget {
  const BackupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Backups & Sources')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.gutter, 0, AppDimens.gutter, 96),
        children: [
          BentoCell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CellLabel('Import backup'),
                const SizedBox(height: AppDimens.unit),
                Text(
                  'Upload .tachibk or legacy .json backups from Mihon and its forks.',
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppDimens.unit * 2),
                PillButton(
                  label: 'Choose files',
                  icon: Icons.upload_file,
                  // Enabled in M2 when the import pipeline exists.
                  onPressed: null,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.gutter),
          BentoCell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CellLabel('Import history'),
                const SizedBox(height: AppDimens.unit),
                Text(
                  'No imports yet.',
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

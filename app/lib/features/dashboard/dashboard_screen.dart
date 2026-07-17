import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_dimens.dart';
import '../../widgets/bento_cell.dart';
import '../../widgets/pill_button.dart';

/// Archive Dashboard (home). Bento cells per the `archive_dashboard` mockup.
/// Placeholder data until the stats API lands (M5).
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('MangaVault')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.gutter, 0, AppDimens.gutter, 96),
        children: [
          Row(
            children: [
              Expanded(
                child: BentoCell(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CellLabel('Total titles'),
                      const SizedBox(height: AppDimens.unit),
                      Text('—', style: theme.textTheme.headlineLarge),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppDimens.gutter),
              Expanded(
                child: BentoCell(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CellLabel('Chapters'),
                      const SizedBox(height: AppDimens.unit),
                      Text('—', style: theme.textTheme.headlineLarge),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.gutter),
          BentoCell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CellLabel('Backup health'),
                const SizedBox(height: AppDimens.unit),
                Text(
                  'No backups imported yet',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: AppDimens.unit * 2),
                PillButton(
                  label: 'Import a backup',
                  icon: Icons.upload_file,
                  onPressed: () => context.go('/backups'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.gutter),
          BentoCell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CellLabel('Resume reading'),
                const SizedBox(height: AppDimens.unit),
                Text(
                  'Reading progress will appear here once your library is imported.',
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

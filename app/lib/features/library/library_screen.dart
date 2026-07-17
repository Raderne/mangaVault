import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_dimens.dart';
import '../../widgets/status_chip.dart';

/// Library Archive: cover grid with filter chips per the `library_archive`
/// mockup. Wired to the paged library API in M3.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppDimens.gutter),
            child: Wrap(
              spacing: AppDimens.unit,
              children: const [
                StatusChip('All titles', emphasized: true),
                StatusChip('Ongoing'),
                StatusChip('Completed'),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.collections_bookmark_outlined,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: AppDimens.unit * 2),
                  Text('Your archive is empty', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppDimens.unit),
                  Text(
                    'Import a backup to fill the library.',
                    style: theme.textTheme.bodyMedium!.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppDimens.unit * 2),
                  TextButton(
                    onPressed: () => context.go('/backups'),
                    child: const Text('Go to Backups'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

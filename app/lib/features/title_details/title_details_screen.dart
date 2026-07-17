import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../widgets/bento_cell.dart';

/// Title Details: modular bento view per the `title_details` mockup.
/// Fed from `/library/:id` in M3.
class TitleDetailsScreen extends StatelessWidget {
  const TitleDetailsScreen({super.key, required this.titleId});

  final String titleId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Title details')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.gutter, 0, AppDimens.gutter, 96),
        children: [
          BentoCell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CellLabel('Synopsis'),
                const SizedBox(height: AppDimens.unit),
                Text(
                  'Title $titleId — details load here once the library API '
                  'is connected (M3).',
                  style: theme.textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/app_dimens.dart';

/// Vertical library card: fixed-aspect cover with a chapter-count overlay in
/// the bottom-right corner, title and source below.
class MangaCard extends StatelessWidget {
  const MangaCard({
    super.key,
    required this.title,
    this.sourceName,
    this.coverUrl,
    this.chapterCount,
    this.onTap,
  });

  final String title;
  final String? sourceName;
  final String? coverUrl;
  final int? chapterCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimens.coverRadius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: AppDimens.coverAspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppDimens.coverRadius),
                  child: coverUrl != null
                      ? Image.network(
                          coverUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const _CoverPlaceholder(),
                        )
                      : const _CoverPlaceholder(),
                ),
                if (chapterCount != null)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLowest.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$chapterCount ch',
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.unit),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600),
          ),
          if (sourceName != null)
            Text(
              sourceName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall!
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHigh,
      child: Icon(Icons.menu_book_outlined, color: scheme.onSurfaceVariant, size: 32),
    );
  }
}

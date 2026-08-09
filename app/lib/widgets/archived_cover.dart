import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/covers/cover_cache.dart';
import '../data/covers/cover_repository.dart';
import 'entrance_fade.dart';

/// Renders a title's archived cover with the bearer header attached (the serve
/// route is guarded and the image loader doesn't use Dio), gently fading the
/// image in as it decodes. Backed by a persistent on-device disk cache
/// ([CoverCache]) keyed by manga id, so a cover is fetched from the server once
/// and then read from disk across restarts. Falls back to [placeholder] while
/// unarchived / loading / on error, so the layout is identical with or without
/// a cover.
///
/// A `ConsumerWidget` because the server it loads from is chosen at runtime:
/// switching servers must rebuild every cover against the new origin.
class ArchivedCover extends ConsumerWidget {
  const ArchivedCover({
    super.key,
    required this.coverState,
    required this.mangaId,
    required this.placeholder,
    this.fit = BoxFit.cover,
  });

  final String coverState;
  final String mangaId;
  final Widget placeholder;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final covers = ref.watch(coverUrlsProvider);
    final url = covers.cover(coverState, mangaId);
    if (url == null) return placeholder;
    return CachedNetworkImage(
      imageUrl: url,
      cacheKey: mangaId,
      cacheManager: CoverCache.manager,
      httpHeaders: covers.authHeaders,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 300),
      fadeInCurve: kEntranceCurve,
      placeholder: (_, _) => placeholder,
      errorWidget: (_, _, _) => placeholder,
    );
  }
}

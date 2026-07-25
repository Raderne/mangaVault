import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Persistent on-device cache for archived cover images.
///
/// Covers are effectively immutable per manga id — the `/covers/:id` URL is
/// stable and the bytes only change on an explicit re-fetch / custom upload —
/// so a long stale period and a generous object count suit a multi-thousand
/// title library: after the first load a cover is read from disk (surviving app
/// restarts and grid scrolling), not re-fetched from the server every time.
///
/// The cache is keyed by **manga id**, not the URL, so it stays valid even if
/// the compiled-in `SERVER_URL` changes between builds.
class CoverCache {
  const CoverCache._();

  static const key = 'mangavault_covers';

  static final CacheManager manager = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 180),
      maxNrOfCacheObjects: 5000,
    ),
  );

  /// Drop a cover from both the disk cache and Flutter's decoded-image cache so
  /// a replaced cover (re-fetch / custom upload) reloads fresh — the serve URL
  /// is stable, so without this the stale image would be served from cache.
  static Future<void> evict(String mangaId, String url) async {
    try {
      await manager.removeFile(mangaId);
    } catch (_) {
      // Nothing cached yet for this id — fine.
    }
    await CachedNetworkImageProvider(
      url,
      cacheKey: mangaId,
      cacheManager: manager,
    ).evict();
  }
}

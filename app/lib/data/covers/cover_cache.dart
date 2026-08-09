import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Persistent on-device cache for archived cover images.
///
/// Covers are effectively immutable per manga id — the `/covers/:id` URL is
/// stable and the bytes only change on an explicit re-fetch / custom upload —
/// so a long stale period and a generous object count suit a multi-thousand
/// title library: after the first load a cover is read from disk (surviving app
/// restarts and grid scrolling), not re-fetched from the server every time.
///
/// The cache is keyed by **manga id**, not the URL, so it survives a change of
/// server address for the *same* vault (a LAN IP moving, a domain going up in
/// front of it) without refetching thousands of images.
///
/// The flip side, and the reason [clear] exists: an id-keyed cache is only
/// valid for one vault. Two different servers can mint the same id, so
/// connecting the app to a different server must empty this — otherwise one
/// vault's cover art appears on another's titles.
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

  /// Empty the whole cache. Used when the app is pointed at a different
  /// server — see the class doc.
  static Future<void> clear() async {
    try {
      await manager.emptyCache();
    } catch (_) {
      // Opportunistic cleanup: a cache we failed to clear must not block a
      // disconnect the user has already confirmed.
    }
  }

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

/// Indirection for [CoverCache.clear] so it can be substituted.
///
/// Not ceremony: merely *touching* [CoverCache.manager] constructs a
/// `flutter_cache_manager` `Config`, which calls `getTemporaryDirectory()`.
/// Under `flutter_test` that raises a `MissingPluginException` **as an
/// unhandled async error in the zone** — it never surfaces through the `await`,
/// so no `try`/`catch` at the call site can contain it, and it fails whichever
/// test happens to be running. Tests override this with a no-op.
final coverCacheCleanerProvider = Provider<Future<void> Function()>(
  (ref) => CoverCache.clear,
);

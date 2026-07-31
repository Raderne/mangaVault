// Dart mirror of the server's DeletedTitleDto
// (server/src/modules/library/library.dto.ts).

/// One entry in the deletion registry: a title the user deleted, which every
/// import now skips until it is restored or purged.
class DeletedTitle {
  const DeletedTitle({
    required this.id,
    required this.sourceId,
    required this.sourceName,
    required this.title,
    required this.chapterCount,
    required this.readCount,
    required this.deletedAt,
    required this.lastSeenAt,
    required this.seenCount,
  });

  /// Registry row id — what restore/purge take, **not** the old manga id
  /// (that id is tombstoned and gone from every mirror).
  final String id;
  final String sourceId;
  final String sourceName;
  final String title;
  final int chapterCount;
  final int readCount;
  final int deletedAt;

  /// When an import last offered this title again (null = not since deletion).
  final int? lastSeenAt;

  /// How many imports have been blocked from re-adding it.
  final int seenCount;

  /// A backup has tried to bring this title back — the strongest hint that it
  /// is worth restoring (or purging for good).
  bool get seenSinceDelete => seenCount > 0;

  factory DeletedTitle.fromJson(Map<String, dynamic> j) => DeletedTitle(
        id: j['id'] as String,
        sourceId: (j['sourceId'] as String?) ?? '',
        sourceName: (j['sourceName'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        chapterCount: (j['chapterCount'] as num?)?.toInt() ?? 0,
        readCount: (j['readCount'] as num?)?.toInt() ?? 0,
        deletedAt: (j['deletedAt'] as num?)?.toInt() ?? 0,
        lastSeenAt: (j['lastSeenAt'] as num?)?.toInt(),
        seenCount: (j['seenCount'] as num?)?.toInt() ?? 0,
      );
}

/// Outcome of a restore request.
class RestoreResult {
  const RestoreResult({required this.restored, required this.skipped});

  final int restored;

  /// Entries that couldn't be restored (already present again, or failed).
  final int skipped;

  factory RestoreResult.fromJson(Map<String, dynamic> j) => RestoreResult(
        restored: (j['restored'] as num?)?.toInt() ?? 0,
        skipped: (j['skipped'] as num?)?.toInt() ?? 0,
      );
}

/// The registry plus what it costs on disk.
///
/// The size travels with the list because the snapshots are exactly what gets
/// questioned: measured, an archived chapter costs ~64 B against ~512 B for the
/// same chapter live, so deleting a title still frees ~87% of its storage.
class DeletedTitlesPage {
  const DeletedTitlesPage({required this.items, required this.totalBytes});

  final List<DeletedTitle> items;

  /// Whole-table size on the server (heap + TOAST + indexes).
  final int totalBytes;

  factory DeletedTitlesPage.fromJson(Map<String, dynamic> j) =>
      DeletedTitlesPage(
        items: ((j['items'] as List?) ?? const [])
            .map((e) => DeletedTitle.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalBytes: (j['totalBytes'] as num?)?.toInt() ?? 0,
      );
}

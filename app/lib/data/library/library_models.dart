// Dart mirrors of the server's library DTOs
// (server/src/modules/library/library.dto.ts). Manual `fromJson` in the same
// style as the import models — small, read-only, no codegen.

/// Slim row for the virtualized library grid.
class MangaListItem {
  const MangaListItem({
    required this.id,
    required this.title,
    required this.author,
    required this.status,
    required this.coverPath,
    required this.coverState,
    required this.sourceName,
    required this.sourceId,
    required this.chapterCount,
    required this.unreadCount,
    required this.lastReadAt,
  });

  final String id;
  final String title;
  final String? author;
  final String status;
  final String? coverPath;
  final String coverState;
  final String sourceName;
  final String sourceId;
  final int chapterCount;
  final int unreadCount;
  final int? lastReadAt;

  factory MangaListItem.fromJson(Map<String, dynamic> j) => MangaListItem(
        id: j['id'] as String,
        title: (j['title'] as String?) ?? '',
        author: j['author'] as String?,
        status: (j['status'] as String?) ?? 'unknown',
        coverPath: j['coverPath'] as String?,
        coverState: (j['coverState'] as String?) ?? 'none',
        sourceName: (j['sourceName'] as String?) ?? '',
        sourceId: (j['sourceId'] as String?) ?? '',
        chapterCount: (j['chapterCount'] as num?)?.toInt() ?? 0,
        unreadCount: (j['unreadCount'] as num?)?.toInt() ?? 0,
        lastReadAt: (j['lastReadAt'] as num?)?.toInt(),
      );
}

/// One page of library results plus the full match count.
class LibraryPage {
  const LibraryPage({
    required this.items,
    required this.total,
    required this.offset,
    required this.limit,
  });

  final List<MangaListItem> items;
  final int total;
  final int offset;
  final int limit;

  factory LibraryPage.fromJson(Map<String, dynamic> j) => LibraryPage(
        items: ((j['items'] as List?) ?? const [])
            .map((e) => MangaListItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: (j['total'] as num?)?.toInt() ?? 0,
        offset: (j['offset'] as num?)?.toInt() ?? 0,
        limit: (j['limit'] as num?)?.toInt() ?? 0,
      );
}

/// One Mihon source present in the library, with how many titles came from it.
///
/// Derived from the mirror rather than the server's `known_source` registry:
/// the filter should only offer sources you actually have titles from.
class SourceOption {
  const SourceOption({
    required this.id,
    required this.name,
    required this.count,
  });

  final String id;

  /// Display name as recorded in the backup — often empty (a fork that didn't
  /// write `backupSources`, or a source that was uninstalled before export).
  final String name;
  final int count;

  /// What to show in the UI. Backups from some forks carry no source name at
  /// all, and a blank chip is unusable — fall back to the numeric source id,
  /// which is at least stable and greppable.
  String get label => sourceLabel(name, id);
}

/// Display name for a source: its name, or the raw id when the name is blank.
String sourceLabel(String name, String id) =>
    name.trim().isNotEmpty ? name.trim() : (id.isNotEmpty ? id : 'Unknown');

/// A category with the number of titles assigned to it (filter chips).
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.sort,
    required this.count,
  });

  final String id;
  final String name;
  final int sort;
  final int count;

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        sort: (j['sort'] as num?)?.toInt() ?? 0,
        count: (j['count'] as num?)?.toInt() ?? 0,
      );
}

/// Slim category reference attached to a title.
class CategoryRef {
  const CategoryRef({required this.id, required this.name});

  final String id;
  final String name;

  factory CategoryRef.fromJson(Map<String, dynamic> j) => CategoryRef(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
      );
}

/// A chapter pointer (reading-progress readout / continue-reading target).
class ChapterRef {
  const ChapterRef({required this.name, required this.number});

  final String name;
  final double number;

  factory ChapterRef.fromJson(Map<String, dynamic> j) => ChapterRef(
        name: (j['name'] as String?) ?? '',
        number: (j['number'] as num?)?.toDouble() ?? -1,
      );
}

/// One backup that contributed this title (archive history).
class ArchiveEntry {
  const ArchiveEntry({
    required this.id,
    required this.fileName,
    required this.sourceApp,
    required this.container,
    required this.importedAt,
  });

  final String id;
  final String fileName;
  final String sourceApp;
  final String container;
  final int importedAt;

  factory ArchiveEntry.fromJson(Map<String, dynamic> j) => ArchiveEntry(
        id: j['id'] as String,
        fileName: (j['fileName'] as String?) ?? '',
        sourceApp: (j['sourceApp'] as String?) ?? '',
        container: (j['container'] as String?) ?? '',
        importedAt: (j['importedAt'] as num?)?.toInt() ?? 0,
      );
}

/// Full title record backing the Title Details screen.
class VaultManga {
  const VaultManga({
    required this.id,
    required this.sourceId,
    required this.sourceName,
    required this.title,
    required this.author,
    required this.artist,
    required this.description,
    required this.genres,
    required this.status,
    required this.coverPath,
    required this.coverState,
    required this.notes,
    required this.dateAdded,
    required this.chapterCount,
    required this.readCount,
    required this.unreadCount,
    required this.lastReadChapter,
    required this.nextChapter,
    required this.categories,
    required this.archive,
  });

  final String id;
  final String sourceId;
  final String sourceName;
  final String title;
  final String? author;
  final String? artist;
  final String? description;
  final List<String> genres;
  final String status;
  final String? coverPath;
  final String coverState;
  final String notes;
  final int dateAdded;
  final int chapterCount;
  final int readCount;
  final int unreadCount;
  final ChapterRef? lastReadChapter;
  final ChapterRef? nextChapter;
  final List<CategoryRef> categories;
  final List<ArchiveEntry> archive;

  /// Read fraction in [0, 1] for the progress bar.
  double get readFraction =>
      chapterCount == 0 ? 0 : (readCount / chapterCount).clamp(0.0, 1.0);

  factory VaultManga.fromJson(Map<String, dynamic> j) => VaultManga(
        id: j['id'] as String,
        sourceId: (j['sourceId'] as String?) ?? '',
        sourceName: (j['sourceName'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        author: j['author'] as String?,
        artist: j['artist'] as String?,
        description: j['description'] as String?,
        genres: ((j['genres'] as List?) ?? const [])
            .map((e) => e as String)
            .toList(),
        status: (j['status'] as String?) ?? 'unknown',
        coverPath: j['coverPath'] as String?,
        coverState: (j['coverState'] as String?) ?? 'none',
        notes: (j['notes'] as String?) ?? '',
        dateAdded: (j['dateAdded'] as num?)?.toInt() ?? 0,
        chapterCount: (j['chapterCount'] as num?)?.toInt() ?? 0,
        readCount: (j['readCount'] as num?)?.toInt() ?? 0,
        unreadCount: (j['unreadCount'] as num?)?.toInt() ?? 0,
        lastReadChapter: j['lastReadChapter'] == null
            ? null
            : ChapterRef.fromJson(j['lastReadChapter'] as Map<String, dynamic>),
        nextChapter: j['nextChapter'] == null
            ? null
            : ChapterRef.fromJson(j['nextChapter'] as Map<String, dynamic>),
        categories: ((j['categories'] as List?) ?? const [])
            .map((e) => CategoryRef.fromJson(e as Map<String, dynamic>))
            .toList(),
        archive: ((j['archive'] as List?) ?? const [])
            .map((e) => ArchiveEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

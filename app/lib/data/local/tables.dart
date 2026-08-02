import 'package:drift/drift.dart';

/// One row per title: the union of what the library grid and the Title Details
/// screen render, denormalized so every query the UI needs is a single table
/// scan with no joins on the hot path.
///
/// Chapters are deliberately absent — the vault holds ~182k of them and no
/// screen lists them. Reading progress arrives pre-aggregated from the server
/// alongside the two chapter pointers the details screen shows.
@DataClassName('LocalMangaRow')
class LocalManga extends Table {
  TextColumn get id => text()();

  /// Server's monotonic version for this row (int64 as a decimal string).
  TextColumn get rowVersion => text()();

  TextColumn get sourceId => text()();
  TextColumn get sourceName => text().withDefault(const Constant(''))();
  TextColumn get title => text()();

  /// Case-folded copies backing search and title sort — SQLite's `LIKE` is
  /// only ASCII-case-insensitive, and `COLLATE NOCASE` would not help the
  /// non-ASCII titles common in this library.
  TextColumn get titleLower => text()();
  TextColumn get authorLower => text().withDefault(const Constant(''))();

  TextColumn get author => text().nullable()();
  TextColumn get artist => text().nullable()();
  TextColumn get description => text().nullable()();

  /// JSON array; genres are rendered as chips, never queried.
  TextColumn get genresJson => text().withDefault(const Constant('[]'))();

  TextColumn get status => text().withDefault(const Constant('unknown'))();
  TextColumn get thumbnailUrl => text().nullable()();
  TextColumn get coverPath => text().nullable()();
  TextColumn get coverState => text().withDefault(const Constant('none'))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  BoolColumn get favorite => boolean().withDefault(const Constant(true))();

  IntColumn get dateAdded => integer().withDefault(const Constant(0))();
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();

  IntColumn get chapterCount => integer().withDefault(const Constant(0))();
  IntColumn get readCount => integer().withDefault(const Constant(0))();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  IntColumn get lastReadAt => integer().nullable()();

  TextColumn get lastReadChapterName => text().nullable()();
  RealColumn get lastReadChapterNumber => real().nullable()();
  TextColumn get nextChapterName => text().nullable()();
  RealColumn get nextChapterNumber => real().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalCategory extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get sort => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalMangaCategory extends Table {
  TextColumn get mangaId => text()();
  TextColumn get categoryId => text()();

  @override
  Set<Column> get primaryKey => {mangaId, categoryId};
}

/// Mirrors `import_record` — backs the Backups history cell and, joined through
/// [LocalMangaImport], the dashboard's per-source-app backup health.
class LocalImportRecord extends Table {
  TextColumn get id => text()();
  TextColumn get fileName => text()();
  IntColumn get fileSize => integer().withDefault(const Constant(0))();
  TextColumn get sha256 => text().withDefault(const Constant(''))();
  TextColumn get sourceApp => text().withDefault(const Constant(''))();
  TextColumn get container => text().withDefault(const Constant(''))();
  IntColumn get importedAt => integer().withDefault(const Constant(0))();

  /// The server's `import_record.stats` blob, verbatim — the history cell
  /// renders its new/merged counts.
  TextColumn get statsJson => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalMangaImport extends Table {
  TextColumn get mangaId => text()();
  TextColumn get importId => text()();

  @override
  Set<Column> get primaryKey => {mangaId, importId};
}

/// Mirrors the server's `backup_app` registry — the reading apps a backup can
/// come from. A title's apps are derived (manga → [LocalMangaImport] →
/// [LocalImportRecord.sourceApp]); this is only what turns `app.mihon` into
/// "Mihon" for the filter chips and the import picker, offline included.
class LocalBackupApp extends Table {
  /// Android application id, e.g. `app.mihon`.
  TextColumn get id => text()();
  TextColumn get displayName => text()();

  /// Hex accent for the app's chip; null falls back to the theme.
  TextColumn get accent => text().nullable()();

  /// Shipped by the server rather than added by the user.
  BoolColumn get curated => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Single-row table (`id` is always 0) holding sync bookkeeping.
class SyncMeta extends Table {
  IntColumn get id => integer().withDefault(const Constant(0))();

  /// Server high-water mark already applied locally; null means never synced.
  TextColumn get cursor => text().nullable()();

  /// Server identity — a change means Postgres was restored and the local
  /// mirror must be rebuilt from scratch.
  TextColumn get serverEpoch => text().nullable()();

  IntColumn get lastSyncedAt => integer().nullable()();

  /// Vault size in bytes; the one dashboard figure the device cannot derive.
  IntColumn get vaultSizeBytes => integer().withDefault(const Constant(0))();

  /// The same total split by where it lives on the server. Stored as parts so
  /// the dashboard can show "613 MB of that is covers" while offline.
  IntColumn get vaultDatabaseBytes => integer().withDefault(const Constant(0))();
  IntColumn get vaultCoversBytes => integer().withDefault(const Constant(0))();
  IntColumn get vaultBackupsBytes => integer().withDefault(const Constant(0))();

  /// Bumped once per committed sync transaction. Screens watch this instead of
  /// every table, so one cheap stream drives all the local-read providers.
  IntColumn get localRevision => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

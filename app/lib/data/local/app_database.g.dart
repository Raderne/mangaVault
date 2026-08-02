// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $LocalMangaTable extends LocalManga
    with TableInfo<$LocalMangaTable, LocalMangaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalMangaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<String> rowVersion = GeneratedColumn<String>(
    'row_version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceNameMeta = const VerificationMeta(
    'sourceName',
  );
  @override
  late final GeneratedColumn<String> sourceName = GeneratedColumn<String>(
    'source_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleLowerMeta = const VerificationMeta(
    'titleLower',
  );
  @override
  late final GeneratedColumn<String> titleLower = GeneratedColumn<String>(
    'title_lower',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorLowerMeta = const VerificationMeta(
    'authorLower',
  );
  @override
  late final GeneratedColumn<String> authorLower = GeneratedColumn<String>(
    'author_lower',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
    'author',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
    'artist',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _genresJsonMeta = const VerificationMeta(
    'genresJson',
  );
  @override
  late final GeneratedColumn<String> genresJson = GeneratedColumn<String>(
    'genres_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unknown'),
  );
  static const VerificationMeta _thumbnailUrlMeta = const VerificationMeta(
    'thumbnailUrl',
  );
  @override
  late final GeneratedColumn<String> thumbnailUrl = GeneratedColumn<String>(
    'thumbnail_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverPathMeta = const VerificationMeta(
    'coverPath',
  );
  @override
  late final GeneratedColumn<String> coverPath = GeneratedColumn<String>(
    'cover_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverStateMeta = const VerificationMeta(
    'coverState',
  );
  @override
  late final GeneratedColumn<String> coverState = GeneratedColumn<String>(
    'cover_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('none'),
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _favoriteMeta = const VerificationMeta(
    'favorite',
  );
  @override
  late final GeneratedColumn<bool> favorite = GeneratedColumn<bool>(
    'favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _dateAddedMeta = const VerificationMeta(
    'dateAdded',
  );
  @override
  late final GeneratedColumn<int> dateAdded = GeneratedColumn<int>(
    'date_added',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _chapterCountMeta = const VerificationMeta(
    'chapterCount',
  );
  @override
  late final GeneratedColumn<int> chapterCount = GeneratedColumn<int>(
    'chapter_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _readCountMeta = const VerificationMeta(
    'readCount',
  );
  @override
  late final GeneratedColumn<int> readCount = GeneratedColumn<int>(
    'read_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _unreadCountMeta = const VerificationMeta(
    'unreadCount',
  );
  @override
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
    'unread_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastReadAtMeta = const VerificationMeta(
    'lastReadAt',
  );
  @override
  late final GeneratedColumn<int> lastReadAt = GeneratedColumn<int>(
    'last_read_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastReadChapterNameMeta =
      const VerificationMeta('lastReadChapterName');
  @override
  late final GeneratedColumn<String> lastReadChapterName =
      GeneratedColumn<String>(
        'last_read_chapter_name',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastReadChapterNumberMeta =
      const VerificationMeta('lastReadChapterNumber');
  @override
  late final GeneratedColumn<double> lastReadChapterNumber =
      GeneratedColumn<double>(
        'last_read_chapter_number',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _nextChapterNameMeta = const VerificationMeta(
    'nextChapterName',
  );
  @override
  late final GeneratedColumn<String> nextChapterName = GeneratedColumn<String>(
    'next_chapter_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nextChapterNumberMeta = const VerificationMeta(
    'nextChapterNumber',
  );
  @override
  late final GeneratedColumn<double> nextChapterNumber =
      GeneratedColumn<double>(
        'next_chapter_number',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    rowVersion,
    sourceId,
    sourceName,
    title,
    titleLower,
    authorLower,
    author,
    artist,
    description,
    genresJson,
    status,
    thumbnailUrl,
    coverPath,
    coverState,
    notes,
    favorite,
    dateAdded,
    updatedAt,
    chapterCount,
    readCount,
    unreadCount,
    lastReadAt,
    lastReadChapterName,
    lastReadChapterNumber,
    nextChapterName,
    nextChapterNumber,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_manga';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalMangaRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    } else if (isInserting) {
      context.missing(_rowVersionMeta);
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('source_name')) {
      context.handle(
        _sourceNameMeta,
        sourceName.isAcceptableOrUnknown(data['source_name']!, _sourceNameMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('title_lower')) {
      context.handle(
        _titleLowerMeta,
        titleLower.isAcceptableOrUnknown(data['title_lower']!, _titleLowerMeta),
      );
    } else if (isInserting) {
      context.missing(_titleLowerMeta);
    }
    if (data.containsKey('author_lower')) {
      context.handle(
        _authorLowerMeta,
        authorLower.isAcceptableOrUnknown(
          data['author_lower']!,
          _authorLowerMeta,
        ),
      );
    }
    if (data.containsKey('author')) {
      context.handle(
        _authorMeta,
        author.isAcceptableOrUnknown(data['author']!, _authorMeta),
      );
    }
    if (data.containsKey('artist')) {
      context.handle(
        _artistMeta,
        artist.isAcceptableOrUnknown(data['artist']!, _artistMeta),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('genres_json')) {
      context.handle(
        _genresJsonMeta,
        genresJson.isAcceptableOrUnknown(data['genres_json']!, _genresJsonMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('thumbnail_url')) {
      context.handle(
        _thumbnailUrlMeta,
        thumbnailUrl.isAcceptableOrUnknown(
          data['thumbnail_url']!,
          _thumbnailUrlMeta,
        ),
      );
    }
    if (data.containsKey('cover_path')) {
      context.handle(
        _coverPathMeta,
        coverPath.isAcceptableOrUnknown(data['cover_path']!, _coverPathMeta),
      );
    }
    if (data.containsKey('cover_state')) {
      context.handle(
        _coverStateMeta,
        coverState.isAcceptableOrUnknown(data['cover_state']!, _coverStateMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('favorite')) {
      context.handle(
        _favoriteMeta,
        favorite.isAcceptableOrUnknown(data['favorite']!, _favoriteMeta),
      );
    }
    if (data.containsKey('date_added')) {
      context.handle(
        _dateAddedMeta,
        dateAdded.isAcceptableOrUnknown(data['date_added']!, _dateAddedMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('chapter_count')) {
      context.handle(
        _chapterCountMeta,
        chapterCount.isAcceptableOrUnknown(
          data['chapter_count']!,
          _chapterCountMeta,
        ),
      );
    }
    if (data.containsKey('read_count')) {
      context.handle(
        _readCountMeta,
        readCount.isAcceptableOrUnknown(data['read_count']!, _readCountMeta),
      );
    }
    if (data.containsKey('unread_count')) {
      context.handle(
        _unreadCountMeta,
        unreadCount.isAcceptableOrUnknown(
          data['unread_count']!,
          _unreadCountMeta,
        ),
      );
    }
    if (data.containsKey('last_read_at')) {
      context.handle(
        _lastReadAtMeta,
        lastReadAt.isAcceptableOrUnknown(
          data['last_read_at']!,
          _lastReadAtMeta,
        ),
      );
    }
    if (data.containsKey('last_read_chapter_name')) {
      context.handle(
        _lastReadChapterNameMeta,
        lastReadChapterName.isAcceptableOrUnknown(
          data['last_read_chapter_name']!,
          _lastReadChapterNameMeta,
        ),
      );
    }
    if (data.containsKey('last_read_chapter_number')) {
      context.handle(
        _lastReadChapterNumberMeta,
        lastReadChapterNumber.isAcceptableOrUnknown(
          data['last_read_chapter_number']!,
          _lastReadChapterNumberMeta,
        ),
      );
    }
    if (data.containsKey('next_chapter_name')) {
      context.handle(
        _nextChapterNameMeta,
        nextChapterName.isAcceptableOrUnknown(
          data['next_chapter_name']!,
          _nextChapterNameMeta,
        ),
      );
    }
    if (data.containsKey('next_chapter_number')) {
      context.handle(
        _nextChapterNumberMeta,
        nextChapterNumber.isAcceptableOrUnknown(
          data['next_chapter_number']!,
          _nextChapterNumberMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalMangaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalMangaRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}row_version'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      sourceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_name'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      titleLower: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title_lower'],
      )!,
      authorLower: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author_lower'],
      )!,
      author: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author'],
      ),
      artist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist'],
      ),
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      genresJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}genres_json'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      thumbnailUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail_url'],
      ),
      coverPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_path'],
      ),
      coverState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_state'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      )!,
      favorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}favorite'],
      )!,
      dateAdded: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}date_added'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      chapterCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chapter_count'],
      )!,
      readCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}read_count'],
      )!,
      unreadCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unread_count'],
      )!,
      lastReadAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_read_at'],
      ),
      lastReadChapterName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_read_chapter_name'],
      ),
      lastReadChapterNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}last_read_chapter_number'],
      ),
      nextChapterName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}next_chapter_name'],
      ),
      nextChapterNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}next_chapter_number'],
      ),
    );
  }

  @override
  $LocalMangaTable createAlias(String alias) {
    return $LocalMangaTable(attachedDatabase, alias);
  }
}

class LocalMangaRow extends DataClass implements Insertable<LocalMangaRow> {
  final String id;

  /// Server's monotonic version for this row (int64 as a decimal string).
  final String rowVersion;
  final String sourceId;
  final String sourceName;
  final String title;

  /// Case-folded copies backing search and title sort — SQLite's `LIKE` is
  /// only ASCII-case-insensitive, and `COLLATE NOCASE` would not help the
  /// non-ASCII titles common in this library.
  final String titleLower;
  final String authorLower;
  final String? author;
  final String? artist;
  final String? description;

  /// JSON array; genres are rendered as chips, never queried.
  final String genresJson;
  final String status;
  final String? thumbnailUrl;
  final String? coverPath;
  final String coverState;
  final String notes;
  final bool favorite;
  final int dateAdded;
  final int updatedAt;
  final int chapterCount;
  final int readCount;
  final int unreadCount;
  final int? lastReadAt;
  final String? lastReadChapterName;
  final double? lastReadChapterNumber;
  final String? nextChapterName;
  final double? nextChapterNumber;
  const LocalMangaRow({
    required this.id,
    required this.rowVersion,
    required this.sourceId,
    required this.sourceName,
    required this.title,
    required this.titleLower,
    required this.authorLower,
    this.author,
    this.artist,
    this.description,
    required this.genresJson,
    required this.status,
    this.thumbnailUrl,
    this.coverPath,
    required this.coverState,
    required this.notes,
    required this.favorite,
    required this.dateAdded,
    required this.updatedAt,
    required this.chapterCount,
    required this.readCount,
    required this.unreadCount,
    this.lastReadAt,
    this.lastReadChapterName,
    this.lastReadChapterNumber,
    this.nextChapterName,
    this.nextChapterNumber,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['row_version'] = Variable<String>(rowVersion);
    map['source_id'] = Variable<String>(sourceId);
    map['source_name'] = Variable<String>(sourceName);
    map['title'] = Variable<String>(title);
    map['title_lower'] = Variable<String>(titleLower);
    map['author_lower'] = Variable<String>(authorLower);
    if (!nullToAbsent || author != null) {
      map['author'] = Variable<String>(author);
    }
    if (!nullToAbsent || artist != null) {
      map['artist'] = Variable<String>(artist);
    }
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['genres_json'] = Variable<String>(genresJson);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || thumbnailUrl != null) {
      map['thumbnail_url'] = Variable<String>(thumbnailUrl);
    }
    if (!nullToAbsent || coverPath != null) {
      map['cover_path'] = Variable<String>(coverPath);
    }
    map['cover_state'] = Variable<String>(coverState);
    map['notes'] = Variable<String>(notes);
    map['favorite'] = Variable<bool>(favorite);
    map['date_added'] = Variable<int>(dateAdded);
    map['updated_at'] = Variable<int>(updatedAt);
    map['chapter_count'] = Variable<int>(chapterCount);
    map['read_count'] = Variable<int>(readCount);
    map['unread_count'] = Variable<int>(unreadCount);
    if (!nullToAbsent || lastReadAt != null) {
      map['last_read_at'] = Variable<int>(lastReadAt);
    }
    if (!nullToAbsent || lastReadChapterName != null) {
      map['last_read_chapter_name'] = Variable<String>(lastReadChapterName);
    }
    if (!nullToAbsent || lastReadChapterNumber != null) {
      map['last_read_chapter_number'] = Variable<double>(lastReadChapterNumber);
    }
    if (!nullToAbsent || nextChapterName != null) {
      map['next_chapter_name'] = Variable<String>(nextChapterName);
    }
    if (!nullToAbsent || nextChapterNumber != null) {
      map['next_chapter_number'] = Variable<double>(nextChapterNumber);
    }
    return map;
  }

  LocalMangaCompanion toCompanion(bool nullToAbsent) {
    return LocalMangaCompanion(
      id: Value(id),
      rowVersion: Value(rowVersion),
      sourceId: Value(sourceId),
      sourceName: Value(sourceName),
      title: Value(title),
      titleLower: Value(titleLower),
      authorLower: Value(authorLower),
      author: author == null && nullToAbsent
          ? const Value.absent()
          : Value(author),
      artist: artist == null && nullToAbsent
          ? const Value.absent()
          : Value(artist),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      genresJson: Value(genresJson),
      status: Value(status),
      thumbnailUrl: thumbnailUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailUrl),
      coverPath: coverPath == null && nullToAbsent
          ? const Value.absent()
          : Value(coverPath),
      coverState: Value(coverState),
      notes: Value(notes),
      favorite: Value(favorite),
      dateAdded: Value(dateAdded),
      updatedAt: Value(updatedAt),
      chapterCount: Value(chapterCount),
      readCount: Value(readCount),
      unreadCount: Value(unreadCount),
      lastReadAt: lastReadAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReadAt),
      lastReadChapterName: lastReadChapterName == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReadChapterName),
      lastReadChapterNumber: lastReadChapterNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReadChapterNumber),
      nextChapterName: nextChapterName == null && nullToAbsent
          ? const Value.absent()
          : Value(nextChapterName),
      nextChapterNumber: nextChapterNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(nextChapterNumber),
    );
  }

  factory LocalMangaRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalMangaRow(
      id: serializer.fromJson<String>(json['id']),
      rowVersion: serializer.fromJson<String>(json['rowVersion']),
      sourceId: serializer.fromJson<String>(json['sourceId']),
      sourceName: serializer.fromJson<String>(json['sourceName']),
      title: serializer.fromJson<String>(json['title']),
      titleLower: serializer.fromJson<String>(json['titleLower']),
      authorLower: serializer.fromJson<String>(json['authorLower']),
      author: serializer.fromJson<String?>(json['author']),
      artist: serializer.fromJson<String?>(json['artist']),
      description: serializer.fromJson<String?>(json['description']),
      genresJson: serializer.fromJson<String>(json['genresJson']),
      status: serializer.fromJson<String>(json['status']),
      thumbnailUrl: serializer.fromJson<String?>(json['thumbnailUrl']),
      coverPath: serializer.fromJson<String?>(json['coverPath']),
      coverState: serializer.fromJson<String>(json['coverState']),
      notes: serializer.fromJson<String>(json['notes']),
      favorite: serializer.fromJson<bool>(json['favorite']),
      dateAdded: serializer.fromJson<int>(json['dateAdded']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      chapterCount: serializer.fromJson<int>(json['chapterCount']),
      readCount: serializer.fromJson<int>(json['readCount']),
      unreadCount: serializer.fromJson<int>(json['unreadCount']),
      lastReadAt: serializer.fromJson<int?>(json['lastReadAt']),
      lastReadChapterName: serializer.fromJson<String?>(
        json['lastReadChapterName'],
      ),
      lastReadChapterNumber: serializer.fromJson<double?>(
        json['lastReadChapterNumber'],
      ),
      nextChapterName: serializer.fromJson<String?>(json['nextChapterName']),
      nextChapterNumber: serializer.fromJson<double?>(
        json['nextChapterNumber'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'rowVersion': serializer.toJson<String>(rowVersion),
      'sourceId': serializer.toJson<String>(sourceId),
      'sourceName': serializer.toJson<String>(sourceName),
      'title': serializer.toJson<String>(title),
      'titleLower': serializer.toJson<String>(titleLower),
      'authorLower': serializer.toJson<String>(authorLower),
      'author': serializer.toJson<String?>(author),
      'artist': serializer.toJson<String?>(artist),
      'description': serializer.toJson<String?>(description),
      'genresJson': serializer.toJson<String>(genresJson),
      'status': serializer.toJson<String>(status),
      'thumbnailUrl': serializer.toJson<String?>(thumbnailUrl),
      'coverPath': serializer.toJson<String?>(coverPath),
      'coverState': serializer.toJson<String>(coverState),
      'notes': serializer.toJson<String>(notes),
      'favorite': serializer.toJson<bool>(favorite),
      'dateAdded': serializer.toJson<int>(dateAdded),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'chapterCount': serializer.toJson<int>(chapterCount),
      'readCount': serializer.toJson<int>(readCount),
      'unreadCount': serializer.toJson<int>(unreadCount),
      'lastReadAt': serializer.toJson<int?>(lastReadAt),
      'lastReadChapterName': serializer.toJson<String?>(lastReadChapterName),
      'lastReadChapterNumber': serializer.toJson<double?>(
        lastReadChapterNumber,
      ),
      'nextChapterName': serializer.toJson<String?>(nextChapterName),
      'nextChapterNumber': serializer.toJson<double?>(nextChapterNumber),
    };
  }

  LocalMangaRow copyWith({
    String? id,
    String? rowVersion,
    String? sourceId,
    String? sourceName,
    String? title,
    String? titleLower,
    String? authorLower,
    Value<String?> author = const Value.absent(),
    Value<String?> artist = const Value.absent(),
    Value<String?> description = const Value.absent(),
    String? genresJson,
    String? status,
    Value<String?> thumbnailUrl = const Value.absent(),
    Value<String?> coverPath = const Value.absent(),
    String? coverState,
    String? notes,
    bool? favorite,
    int? dateAdded,
    int? updatedAt,
    int? chapterCount,
    int? readCount,
    int? unreadCount,
    Value<int?> lastReadAt = const Value.absent(),
    Value<String?> lastReadChapterName = const Value.absent(),
    Value<double?> lastReadChapterNumber = const Value.absent(),
    Value<String?> nextChapterName = const Value.absent(),
    Value<double?> nextChapterNumber = const Value.absent(),
  }) => LocalMangaRow(
    id: id ?? this.id,
    rowVersion: rowVersion ?? this.rowVersion,
    sourceId: sourceId ?? this.sourceId,
    sourceName: sourceName ?? this.sourceName,
    title: title ?? this.title,
    titleLower: titleLower ?? this.titleLower,
    authorLower: authorLower ?? this.authorLower,
    author: author.present ? author.value : this.author,
    artist: artist.present ? artist.value : this.artist,
    description: description.present ? description.value : this.description,
    genresJson: genresJson ?? this.genresJson,
    status: status ?? this.status,
    thumbnailUrl: thumbnailUrl.present ? thumbnailUrl.value : this.thumbnailUrl,
    coverPath: coverPath.present ? coverPath.value : this.coverPath,
    coverState: coverState ?? this.coverState,
    notes: notes ?? this.notes,
    favorite: favorite ?? this.favorite,
    dateAdded: dateAdded ?? this.dateAdded,
    updatedAt: updatedAt ?? this.updatedAt,
    chapterCount: chapterCount ?? this.chapterCount,
    readCount: readCount ?? this.readCount,
    unreadCount: unreadCount ?? this.unreadCount,
    lastReadAt: lastReadAt.present ? lastReadAt.value : this.lastReadAt,
    lastReadChapterName: lastReadChapterName.present
        ? lastReadChapterName.value
        : this.lastReadChapterName,
    lastReadChapterNumber: lastReadChapterNumber.present
        ? lastReadChapterNumber.value
        : this.lastReadChapterNumber,
    nextChapterName: nextChapterName.present
        ? nextChapterName.value
        : this.nextChapterName,
    nextChapterNumber: nextChapterNumber.present
        ? nextChapterNumber.value
        : this.nextChapterNumber,
  );
  LocalMangaRow copyWithCompanion(LocalMangaCompanion data) {
    return LocalMangaRow(
      id: data.id.present ? data.id.value : this.id,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      sourceName: data.sourceName.present
          ? data.sourceName.value
          : this.sourceName,
      title: data.title.present ? data.title.value : this.title,
      titleLower: data.titleLower.present
          ? data.titleLower.value
          : this.titleLower,
      authorLower: data.authorLower.present
          ? data.authorLower.value
          : this.authorLower,
      author: data.author.present ? data.author.value : this.author,
      artist: data.artist.present ? data.artist.value : this.artist,
      description: data.description.present
          ? data.description.value
          : this.description,
      genresJson: data.genresJson.present
          ? data.genresJson.value
          : this.genresJson,
      status: data.status.present ? data.status.value : this.status,
      thumbnailUrl: data.thumbnailUrl.present
          ? data.thumbnailUrl.value
          : this.thumbnailUrl,
      coverPath: data.coverPath.present ? data.coverPath.value : this.coverPath,
      coverState: data.coverState.present
          ? data.coverState.value
          : this.coverState,
      notes: data.notes.present ? data.notes.value : this.notes,
      favorite: data.favorite.present ? data.favorite.value : this.favorite,
      dateAdded: data.dateAdded.present ? data.dateAdded.value : this.dateAdded,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      chapterCount: data.chapterCount.present
          ? data.chapterCount.value
          : this.chapterCount,
      readCount: data.readCount.present ? data.readCount.value : this.readCount,
      unreadCount: data.unreadCount.present
          ? data.unreadCount.value
          : this.unreadCount,
      lastReadAt: data.lastReadAt.present
          ? data.lastReadAt.value
          : this.lastReadAt,
      lastReadChapterName: data.lastReadChapterName.present
          ? data.lastReadChapterName.value
          : this.lastReadChapterName,
      lastReadChapterNumber: data.lastReadChapterNumber.present
          ? data.lastReadChapterNumber.value
          : this.lastReadChapterNumber,
      nextChapterName: data.nextChapterName.present
          ? data.nextChapterName.value
          : this.nextChapterName,
      nextChapterNumber: data.nextChapterNumber.present
          ? data.nextChapterNumber.value
          : this.nextChapterNumber,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalMangaRow(')
          ..write('id: $id, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('sourceId: $sourceId, ')
          ..write('sourceName: $sourceName, ')
          ..write('title: $title, ')
          ..write('titleLower: $titleLower, ')
          ..write('authorLower: $authorLower, ')
          ..write('author: $author, ')
          ..write('artist: $artist, ')
          ..write('description: $description, ')
          ..write('genresJson: $genresJson, ')
          ..write('status: $status, ')
          ..write('thumbnailUrl: $thumbnailUrl, ')
          ..write('coverPath: $coverPath, ')
          ..write('coverState: $coverState, ')
          ..write('notes: $notes, ')
          ..write('favorite: $favorite, ')
          ..write('dateAdded: $dateAdded, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('chapterCount: $chapterCount, ')
          ..write('readCount: $readCount, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('lastReadChapterName: $lastReadChapterName, ')
          ..write('lastReadChapterNumber: $lastReadChapterNumber, ')
          ..write('nextChapterName: $nextChapterName, ')
          ..write('nextChapterNumber: $nextChapterNumber')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    rowVersion,
    sourceId,
    sourceName,
    title,
    titleLower,
    authorLower,
    author,
    artist,
    description,
    genresJson,
    status,
    thumbnailUrl,
    coverPath,
    coverState,
    notes,
    favorite,
    dateAdded,
    updatedAt,
    chapterCount,
    readCount,
    unreadCount,
    lastReadAt,
    lastReadChapterName,
    lastReadChapterNumber,
    nextChapterName,
    nextChapterNumber,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalMangaRow &&
          other.id == this.id &&
          other.rowVersion == this.rowVersion &&
          other.sourceId == this.sourceId &&
          other.sourceName == this.sourceName &&
          other.title == this.title &&
          other.titleLower == this.titleLower &&
          other.authorLower == this.authorLower &&
          other.author == this.author &&
          other.artist == this.artist &&
          other.description == this.description &&
          other.genresJson == this.genresJson &&
          other.status == this.status &&
          other.thumbnailUrl == this.thumbnailUrl &&
          other.coverPath == this.coverPath &&
          other.coverState == this.coverState &&
          other.notes == this.notes &&
          other.favorite == this.favorite &&
          other.dateAdded == this.dateAdded &&
          other.updatedAt == this.updatedAt &&
          other.chapterCount == this.chapterCount &&
          other.readCount == this.readCount &&
          other.unreadCount == this.unreadCount &&
          other.lastReadAt == this.lastReadAt &&
          other.lastReadChapterName == this.lastReadChapterName &&
          other.lastReadChapterNumber == this.lastReadChapterNumber &&
          other.nextChapterName == this.nextChapterName &&
          other.nextChapterNumber == this.nextChapterNumber);
}

class LocalMangaCompanion extends UpdateCompanion<LocalMangaRow> {
  final Value<String> id;
  final Value<String> rowVersion;
  final Value<String> sourceId;
  final Value<String> sourceName;
  final Value<String> title;
  final Value<String> titleLower;
  final Value<String> authorLower;
  final Value<String?> author;
  final Value<String?> artist;
  final Value<String?> description;
  final Value<String> genresJson;
  final Value<String> status;
  final Value<String?> thumbnailUrl;
  final Value<String?> coverPath;
  final Value<String> coverState;
  final Value<String> notes;
  final Value<bool> favorite;
  final Value<int> dateAdded;
  final Value<int> updatedAt;
  final Value<int> chapterCount;
  final Value<int> readCount;
  final Value<int> unreadCount;
  final Value<int?> lastReadAt;
  final Value<String?> lastReadChapterName;
  final Value<double?> lastReadChapterNumber;
  final Value<String?> nextChapterName;
  final Value<double?> nextChapterNumber;
  final Value<int> rowid;
  const LocalMangaCompanion({
    this.id = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.sourceName = const Value.absent(),
    this.title = const Value.absent(),
    this.titleLower = const Value.absent(),
    this.authorLower = const Value.absent(),
    this.author = const Value.absent(),
    this.artist = const Value.absent(),
    this.description = const Value.absent(),
    this.genresJson = const Value.absent(),
    this.status = const Value.absent(),
    this.thumbnailUrl = const Value.absent(),
    this.coverPath = const Value.absent(),
    this.coverState = const Value.absent(),
    this.notes = const Value.absent(),
    this.favorite = const Value.absent(),
    this.dateAdded = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.chapterCount = const Value.absent(),
    this.readCount = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.lastReadAt = const Value.absent(),
    this.lastReadChapterName = const Value.absent(),
    this.lastReadChapterNumber = const Value.absent(),
    this.nextChapterName = const Value.absent(),
    this.nextChapterNumber = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalMangaCompanion.insert({
    required String id,
    required String rowVersion,
    required String sourceId,
    this.sourceName = const Value.absent(),
    required String title,
    required String titleLower,
    this.authorLower = const Value.absent(),
    this.author = const Value.absent(),
    this.artist = const Value.absent(),
    this.description = const Value.absent(),
    this.genresJson = const Value.absent(),
    this.status = const Value.absent(),
    this.thumbnailUrl = const Value.absent(),
    this.coverPath = const Value.absent(),
    this.coverState = const Value.absent(),
    this.notes = const Value.absent(),
    this.favorite = const Value.absent(),
    this.dateAdded = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.chapterCount = const Value.absent(),
    this.readCount = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.lastReadAt = const Value.absent(),
    this.lastReadChapterName = const Value.absent(),
    this.lastReadChapterNumber = const Value.absent(),
    this.nextChapterName = const Value.absent(),
    this.nextChapterNumber = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       rowVersion = Value(rowVersion),
       sourceId = Value(sourceId),
       title = Value(title),
       titleLower = Value(titleLower);
  static Insertable<LocalMangaRow> custom({
    Expression<String>? id,
    Expression<String>? rowVersion,
    Expression<String>? sourceId,
    Expression<String>? sourceName,
    Expression<String>? title,
    Expression<String>? titleLower,
    Expression<String>? authorLower,
    Expression<String>? author,
    Expression<String>? artist,
    Expression<String>? description,
    Expression<String>? genresJson,
    Expression<String>? status,
    Expression<String>? thumbnailUrl,
    Expression<String>? coverPath,
    Expression<String>? coverState,
    Expression<String>? notes,
    Expression<bool>? favorite,
    Expression<int>? dateAdded,
    Expression<int>? updatedAt,
    Expression<int>? chapterCount,
    Expression<int>? readCount,
    Expression<int>? unreadCount,
    Expression<int>? lastReadAt,
    Expression<String>? lastReadChapterName,
    Expression<double>? lastReadChapterNumber,
    Expression<String>? nextChapterName,
    Expression<double>? nextChapterNumber,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (rowVersion != null) 'row_version': rowVersion,
      if (sourceId != null) 'source_id': sourceId,
      if (sourceName != null) 'source_name': sourceName,
      if (title != null) 'title': title,
      if (titleLower != null) 'title_lower': titleLower,
      if (authorLower != null) 'author_lower': authorLower,
      if (author != null) 'author': author,
      if (artist != null) 'artist': artist,
      if (description != null) 'description': description,
      if (genresJson != null) 'genres_json': genresJson,
      if (status != null) 'status': status,
      if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
      if (coverPath != null) 'cover_path': coverPath,
      if (coverState != null) 'cover_state': coverState,
      if (notes != null) 'notes': notes,
      if (favorite != null) 'favorite': favorite,
      if (dateAdded != null) 'date_added': dateAdded,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (chapterCount != null) 'chapter_count': chapterCount,
      if (readCount != null) 'read_count': readCount,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (lastReadAt != null) 'last_read_at': lastReadAt,
      if (lastReadChapterName != null)
        'last_read_chapter_name': lastReadChapterName,
      if (lastReadChapterNumber != null)
        'last_read_chapter_number': lastReadChapterNumber,
      if (nextChapterName != null) 'next_chapter_name': nextChapterName,
      if (nextChapterNumber != null) 'next_chapter_number': nextChapterNumber,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalMangaCompanion copyWith({
    Value<String>? id,
    Value<String>? rowVersion,
    Value<String>? sourceId,
    Value<String>? sourceName,
    Value<String>? title,
    Value<String>? titleLower,
    Value<String>? authorLower,
    Value<String?>? author,
    Value<String?>? artist,
    Value<String?>? description,
    Value<String>? genresJson,
    Value<String>? status,
    Value<String?>? thumbnailUrl,
    Value<String?>? coverPath,
    Value<String>? coverState,
    Value<String>? notes,
    Value<bool>? favorite,
    Value<int>? dateAdded,
    Value<int>? updatedAt,
    Value<int>? chapterCount,
    Value<int>? readCount,
    Value<int>? unreadCount,
    Value<int?>? lastReadAt,
    Value<String?>? lastReadChapterName,
    Value<double?>? lastReadChapterNumber,
    Value<String?>? nextChapterName,
    Value<double?>? nextChapterNumber,
    Value<int>? rowid,
  }) {
    return LocalMangaCompanion(
      id: id ?? this.id,
      rowVersion: rowVersion ?? this.rowVersion,
      sourceId: sourceId ?? this.sourceId,
      sourceName: sourceName ?? this.sourceName,
      title: title ?? this.title,
      titleLower: titleLower ?? this.titleLower,
      authorLower: authorLower ?? this.authorLower,
      author: author ?? this.author,
      artist: artist ?? this.artist,
      description: description ?? this.description,
      genresJson: genresJson ?? this.genresJson,
      status: status ?? this.status,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      coverPath: coverPath ?? this.coverPath,
      coverState: coverState ?? this.coverState,
      notes: notes ?? this.notes,
      favorite: favorite ?? this.favorite,
      dateAdded: dateAdded ?? this.dateAdded,
      updatedAt: updatedAt ?? this.updatedAt,
      chapterCount: chapterCount ?? this.chapterCount,
      readCount: readCount ?? this.readCount,
      unreadCount: unreadCount ?? this.unreadCount,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      lastReadChapterName: lastReadChapterName ?? this.lastReadChapterName,
      lastReadChapterNumber:
          lastReadChapterNumber ?? this.lastReadChapterNumber,
      nextChapterName: nextChapterName ?? this.nextChapterName,
      nextChapterNumber: nextChapterNumber ?? this.nextChapterNumber,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<String>(rowVersion.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (sourceName.present) {
      map['source_name'] = Variable<String>(sourceName.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (titleLower.present) {
      map['title_lower'] = Variable<String>(titleLower.value);
    }
    if (authorLower.present) {
      map['author_lower'] = Variable<String>(authorLower.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (genresJson.present) {
      map['genres_json'] = Variable<String>(genresJson.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (thumbnailUrl.present) {
      map['thumbnail_url'] = Variable<String>(thumbnailUrl.value);
    }
    if (coverPath.present) {
      map['cover_path'] = Variable<String>(coverPath.value);
    }
    if (coverState.present) {
      map['cover_state'] = Variable<String>(coverState.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (favorite.present) {
      map['favorite'] = Variable<bool>(favorite.value);
    }
    if (dateAdded.present) {
      map['date_added'] = Variable<int>(dateAdded.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (chapterCount.present) {
      map['chapter_count'] = Variable<int>(chapterCount.value);
    }
    if (readCount.present) {
      map['read_count'] = Variable<int>(readCount.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (lastReadAt.present) {
      map['last_read_at'] = Variable<int>(lastReadAt.value);
    }
    if (lastReadChapterName.present) {
      map['last_read_chapter_name'] = Variable<String>(
        lastReadChapterName.value,
      );
    }
    if (lastReadChapterNumber.present) {
      map['last_read_chapter_number'] = Variable<double>(
        lastReadChapterNumber.value,
      );
    }
    if (nextChapterName.present) {
      map['next_chapter_name'] = Variable<String>(nextChapterName.value);
    }
    if (nextChapterNumber.present) {
      map['next_chapter_number'] = Variable<double>(nextChapterNumber.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalMangaCompanion(')
          ..write('id: $id, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('sourceId: $sourceId, ')
          ..write('sourceName: $sourceName, ')
          ..write('title: $title, ')
          ..write('titleLower: $titleLower, ')
          ..write('authorLower: $authorLower, ')
          ..write('author: $author, ')
          ..write('artist: $artist, ')
          ..write('description: $description, ')
          ..write('genresJson: $genresJson, ')
          ..write('status: $status, ')
          ..write('thumbnailUrl: $thumbnailUrl, ')
          ..write('coverPath: $coverPath, ')
          ..write('coverState: $coverState, ')
          ..write('notes: $notes, ')
          ..write('favorite: $favorite, ')
          ..write('dateAdded: $dateAdded, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('chapterCount: $chapterCount, ')
          ..write('readCount: $readCount, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('lastReadChapterName: $lastReadChapterName, ')
          ..write('lastReadChapterNumber: $lastReadChapterNumber, ')
          ..write('nextChapterName: $nextChapterName, ')
          ..write('nextChapterNumber: $nextChapterNumber, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalCategoryTable extends LocalCategory
    with TableInfo<$LocalCategoryTable, LocalCategoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalCategoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortMeta = const VerificationMeta('sort');
  @override
  late final GeneratedColumn<int> sort = GeneratedColumn<int>(
    'sort',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, sort];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_category';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalCategoryData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort')) {
      context.handle(
        _sortMeta,
        sort.isAcceptableOrUnknown(data['sort']!, _sortMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalCategoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalCategoryData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort'],
      )!,
    );
  }

  @override
  $LocalCategoryTable createAlias(String alias) {
    return $LocalCategoryTable(attachedDatabase, alias);
  }
}

class LocalCategoryData extends DataClass
    implements Insertable<LocalCategoryData> {
  final String id;
  final String name;
  final int sort;
  const LocalCategoryData({
    required this.id,
    required this.name,
    required this.sort,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['sort'] = Variable<int>(sort);
    return map;
  }

  LocalCategoryCompanion toCompanion(bool nullToAbsent) {
    return LocalCategoryCompanion(
      id: Value(id),
      name: Value(name),
      sort: Value(sort),
    );
  }

  factory LocalCategoryData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalCategoryData(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      sort: serializer.fromJson<int>(json['sort']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'sort': serializer.toJson<int>(sort),
    };
  }

  LocalCategoryData copyWith({String? id, String? name, int? sort}) =>
      LocalCategoryData(
        id: id ?? this.id,
        name: name ?? this.name,
        sort: sort ?? this.sort,
      );
  LocalCategoryData copyWithCompanion(LocalCategoryCompanion data) {
    return LocalCategoryData(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      sort: data.sort.present ? data.sort.value : this.sort,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalCategoryData(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sort: $sort')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, sort);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalCategoryData &&
          other.id == this.id &&
          other.name == this.name &&
          other.sort == this.sort);
}

class LocalCategoryCompanion extends UpdateCompanion<LocalCategoryData> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> sort;
  final Value<int> rowid;
  const LocalCategoryCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.sort = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalCategoryCompanion.insert({
    required String id,
    required String name,
    this.sort = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<LocalCategoryData> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? sort,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (sort != null) 'sort': sort,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalCategoryCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? sort,
    Value<int>? rowid,
  }) {
    return LocalCategoryCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      sort: sort ?? this.sort,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sort.present) {
      map['sort'] = Variable<int>(sort.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalCategoryCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sort: $sort, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalMangaCategoryTable extends LocalMangaCategory
    with TableInfo<$LocalMangaCategoryTable, LocalMangaCategoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalMangaCategoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mangaIdMeta = const VerificationMeta(
    'mangaId',
  );
  @override
  late final GeneratedColumn<String> mangaId = GeneratedColumn<String>(
    'manga_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [mangaId, categoryId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_manga_category';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalMangaCategoryData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('manga_id')) {
      context.handle(
        _mangaIdMeta,
        mangaId.isAcceptableOrUnknown(data['manga_id']!, _mangaIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mangaIdMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mangaId, categoryId};
  @override
  LocalMangaCategoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalMangaCategoryData(
      mangaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manga_id'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      )!,
    );
  }

  @override
  $LocalMangaCategoryTable createAlias(String alias) {
    return $LocalMangaCategoryTable(attachedDatabase, alias);
  }
}

class LocalMangaCategoryData extends DataClass
    implements Insertable<LocalMangaCategoryData> {
  final String mangaId;
  final String categoryId;
  const LocalMangaCategoryData({
    required this.mangaId,
    required this.categoryId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['manga_id'] = Variable<String>(mangaId);
    map['category_id'] = Variable<String>(categoryId);
    return map;
  }

  LocalMangaCategoryCompanion toCompanion(bool nullToAbsent) {
    return LocalMangaCategoryCompanion(
      mangaId: Value(mangaId),
      categoryId: Value(categoryId),
    );
  }

  factory LocalMangaCategoryData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalMangaCategoryData(
      mangaId: serializer.fromJson<String>(json['mangaId']),
      categoryId: serializer.fromJson<String>(json['categoryId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'mangaId': serializer.toJson<String>(mangaId),
      'categoryId': serializer.toJson<String>(categoryId),
    };
  }

  LocalMangaCategoryData copyWith({String? mangaId, String? categoryId}) =>
      LocalMangaCategoryData(
        mangaId: mangaId ?? this.mangaId,
        categoryId: categoryId ?? this.categoryId,
      );
  LocalMangaCategoryData copyWithCompanion(LocalMangaCategoryCompanion data) {
    return LocalMangaCategoryData(
      mangaId: data.mangaId.present ? data.mangaId.value : this.mangaId,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalMangaCategoryData(')
          ..write('mangaId: $mangaId, ')
          ..write('categoryId: $categoryId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(mangaId, categoryId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalMangaCategoryData &&
          other.mangaId == this.mangaId &&
          other.categoryId == this.categoryId);
}

class LocalMangaCategoryCompanion
    extends UpdateCompanion<LocalMangaCategoryData> {
  final Value<String> mangaId;
  final Value<String> categoryId;
  final Value<int> rowid;
  const LocalMangaCategoryCompanion({
    this.mangaId = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalMangaCategoryCompanion.insert({
    required String mangaId,
    required String categoryId,
    this.rowid = const Value.absent(),
  }) : mangaId = Value(mangaId),
       categoryId = Value(categoryId);
  static Insertable<LocalMangaCategoryData> custom({
    Expression<String>? mangaId,
    Expression<String>? categoryId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mangaId != null) 'manga_id': mangaId,
      if (categoryId != null) 'category_id': categoryId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalMangaCategoryCompanion copyWith({
    Value<String>? mangaId,
    Value<String>? categoryId,
    Value<int>? rowid,
  }) {
    return LocalMangaCategoryCompanion(
      mangaId: mangaId ?? this.mangaId,
      categoryId: categoryId ?? this.categoryId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mangaId.present) {
      map['manga_id'] = Variable<String>(mangaId.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalMangaCategoryCompanion(')
          ..write('mangaId: $mangaId, ')
          ..write('categoryId: $categoryId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalImportRecordTable extends LocalImportRecord
    with TableInfo<$LocalImportRecordTable, LocalImportRecordData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalImportRecordTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileSizeMeta = const VerificationMeta(
    'fileSize',
  );
  @override
  late final GeneratedColumn<int> fileSize = GeneratedColumn<int>(
    'file_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sourceAppMeta = const VerificationMeta(
    'sourceApp',
  );
  @override
  late final GeneratedColumn<String> sourceApp = GeneratedColumn<String>(
    'source_app',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _containerMeta = const VerificationMeta(
    'container',
  );
  @override
  late final GeneratedColumn<String> container = GeneratedColumn<String>(
    'container',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _importedAtMeta = const VerificationMeta(
    'importedAt',
  );
  @override
  late final GeneratedColumn<int> importedAt = GeneratedColumn<int>(
    'imported_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _statsJsonMeta = const VerificationMeta(
    'statsJson',
  );
  @override
  late final GeneratedColumn<String> statsJson = GeneratedColumn<String>(
    'stats_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    fileName,
    fileSize,
    sha256,
    sourceApp,
    container,
    importedAt,
    statsJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_import_record';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalImportRecordData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('file_size')) {
      context.handle(
        _fileSizeMeta,
        fileSize.isAcceptableOrUnknown(data['file_size']!, _fileSizeMeta),
      );
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    }
    if (data.containsKey('source_app')) {
      context.handle(
        _sourceAppMeta,
        sourceApp.isAcceptableOrUnknown(data['source_app']!, _sourceAppMeta),
      );
    }
    if (data.containsKey('container')) {
      context.handle(
        _containerMeta,
        container.isAcceptableOrUnknown(data['container']!, _containerMeta),
      );
    }
    if (data.containsKey('imported_at')) {
      context.handle(
        _importedAtMeta,
        importedAt.isAcceptableOrUnknown(data['imported_at']!, _importedAtMeta),
      );
    }
    if (data.containsKey('stats_json')) {
      context.handle(
        _statsJsonMeta,
        statsJson.isAcceptableOrUnknown(data['stats_json']!, _statsJsonMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalImportRecordData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalImportRecordData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      fileSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_size'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      )!,
      sourceApp: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_app'],
      )!,
      container: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}container'],
      )!,
      importedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}imported_at'],
      )!,
      statsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stats_json'],
      )!,
    );
  }

  @override
  $LocalImportRecordTable createAlias(String alias) {
    return $LocalImportRecordTable(attachedDatabase, alias);
  }
}

class LocalImportRecordData extends DataClass
    implements Insertable<LocalImportRecordData> {
  final String id;
  final String fileName;
  final int fileSize;
  final String sha256;
  final String sourceApp;
  final String container;
  final int importedAt;

  /// The server's `import_record.stats` blob, verbatim — the history cell
  /// renders its new/merged counts.
  final String statsJson;
  const LocalImportRecordData({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.sha256,
    required this.sourceApp,
    required this.container,
    required this.importedAt,
    required this.statsJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['file_name'] = Variable<String>(fileName);
    map['file_size'] = Variable<int>(fileSize);
    map['sha256'] = Variable<String>(sha256);
    map['source_app'] = Variable<String>(sourceApp);
    map['container'] = Variable<String>(container);
    map['imported_at'] = Variable<int>(importedAt);
    map['stats_json'] = Variable<String>(statsJson);
    return map;
  }

  LocalImportRecordCompanion toCompanion(bool nullToAbsent) {
    return LocalImportRecordCompanion(
      id: Value(id),
      fileName: Value(fileName),
      fileSize: Value(fileSize),
      sha256: Value(sha256),
      sourceApp: Value(sourceApp),
      container: Value(container),
      importedAt: Value(importedAt),
      statsJson: Value(statsJson),
    );
  }

  factory LocalImportRecordData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalImportRecordData(
      id: serializer.fromJson<String>(json['id']),
      fileName: serializer.fromJson<String>(json['fileName']),
      fileSize: serializer.fromJson<int>(json['fileSize']),
      sha256: serializer.fromJson<String>(json['sha256']),
      sourceApp: serializer.fromJson<String>(json['sourceApp']),
      container: serializer.fromJson<String>(json['container']),
      importedAt: serializer.fromJson<int>(json['importedAt']),
      statsJson: serializer.fromJson<String>(json['statsJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'fileName': serializer.toJson<String>(fileName),
      'fileSize': serializer.toJson<int>(fileSize),
      'sha256': serializer.toJson<String>(sha256),
      'sourceApp': serializer.toJson<String>(sourceApp),
      'container': serializer.toJson<String>(container),
      'importedAt': serializer.toJson<int>(importedAt),
      'statsJson': serializer.toJson<String>(statsJson),
    };
  }

  LocalImportRecordData copyWith({
    String? id,
    String? fileName,
    int? fileSize,
    String? sha256,
    String? sourceApp,
    String? container,
    int? importedAt,
    String? statsJson,
  }) => LocalImportRecordData(
    id: id ?? this.id,
    fileName: fileName ?? this.fileName,
    fileSize: fileSize ?? this.fileSize,
    sha256: sha256 ?? this.sha256,
    sourceApp: sourceApp ?? this.sourceApp,
    container: container ?? this.container,
    importedAt: importedAt ?? this.importedAt,
    statsJson: statsJson ?? this.statsJson,
  );
  LocalImportRecordData copyWithCompanion(LocalImportRecordCompanion data) {
    return LocalImportRecordData(
      id: data.id.present ? data.id.value : this.id,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      fileSize: data.fileSize.present ? data.fileSize.value : this.fileSize,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      sourceApp: data.sourceApp.present ? data.sourceApp.value : this.sourceApp,
      container: data.container.present ? data.container.value : this.container,
      importedAt: data.importedAt.present
          ? data.importedAt.value
          : this.importedAt,
      statsJson: data.statsJson.present ? data.statsJson.value : this.statsJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalImportRecordData(')
          ..write('id: $id, ')
          ..write('fileName: $fileName, ')
          ..write('fileSize: $fileSize, ')
          ..write('sha256: $sha256, ')
          ..write('sourceApp: $sourceApp, ')
          ..write('container: $container, ')
          ..write('importedAt: $importedAt, ')
          ..write('statsJson: $statsJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    fileName,
    fileSize,
    sha256,
    sourceApp,
    container,
    importedAt,
    statsJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalImportRecordData &&
          other.id == this.id &&
          other.fileName == this.fileName &&
          other.fileSize == this.fileSize &&
          other.sha256 == this.sha256 &&
          other.sourceApp == this.sourceApp &&
          other.container == this.container &&
          other.importedAt == this.importedAt &&
          other.statsJson == this.statsJson);
}

class LocalImportRecordCompanion
    extends UpdateCompanion<LocalImportRecordData> {
  final Value<String> id;
  final Value<String> fileName;
  final Value<int> fileSize;
  final Value<String> sha256;
  final Value<String> sourceApp;
  final Value<String> container;
  final Value<int> importedAt;
  final Value<String> statsJson;
  final Value<int> rowid;
  const LocalImportRecordCompanion({
    this.id = const Value.absent(),
    this.fileName = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.sourceApp = const Value.absent(),
    this.container = const Value.absent(),
    this.importedAt = const Value.absent(),
    this.statsJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalImportRecordCompanion.insert({
    required String id,
    required String fileName,
    this.fileSize = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.sourceApp = const Value.absent(),
    this.container = const Value.absent(),
    this.importedAt = const Value.absent(),
    this.statsJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       fileName = Value(fileName);
  static Insertable<LocalImportRecordData> custom({
    Expression<String>? id,
    Expression<String>? fileName,
    Expression<int>? fileSize,
    Expression<String>? sha256,
    Expression<String>? sourceApp,
    Expression<String>? container,
    Expression<int>? importedAt,
    Expression<String>? statsJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fileName != null) 'file_name': fileName,
      if (fileSize != null) 'file_size': fileSize,
      if (sha256 != null) 'sha256': sha256,
      if (sourceApp != null) 'source_app': sourceApp,
      if (container != null) 'container': container,
      if (importedAt != null) 'imported_at': importedAt,
      if (statsJson != null) 'stats_json': statsJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalImportRecordCompanion copyWith({
    Value<String>? id,
    Value<String>? fileName,
    Value<int>? fileSize,
    Value<String>? sha256,
    Value<String>? sourceApp,
    Value<String>? container,
    Value<int>? importedAt,
    Value<String>? statsJson,
    Value<int>? rowid,
  }) {
    return LocalImportRecordCompanion(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      sha256: sha256 ?? this.sha256,
      sourceApp: sourceApp ?? this.sourceApp,
      container: container ?? this.container,
      importedAt: importedAt ?? this.importedAt,
      statsJson: statsJson ?? this.statsJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (fileSize.present) {
      map['file_size'] = Variable<int>(fileSize.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (sourceApp.present) {
      map['source_app'] = Variable<String>(sourceApp.value);
    }
    if (container.present) {
      map['container'] = Variable<String>(container.value);
    }
    if (importedAt.present) {
      map['imported_at'] = Variable<int>(importedAt.value);
    }
    if (statsJson.present) {
      map['stats_json'] = Variable<String>(statsJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalImportRecordCompanion(')
          ..write('id: $id, ')
          ..write('fileName: $fileName, ')
          ..write('fileSize: $fileSize, ')
          ..write('sha256: $sha256, ')
          ..write('sourceApp: $sourceApp, ')
          ..write('container: $container, ')
          ..write('importedAt: $importedAt, ')
          ..write('statsJson: $statsJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalMangaImportTable extends LocalMangaImport
    with TableInfo<$LocalMangaImportTable, LocalMangaImportData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalMangaImportTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mangaIdMeta = const VerificationMeta(
    'mangaId',
  );
  @override
  late final GeneratedColumn<String> mangaId = GeneratedColumn<String>(
    'manga_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _importIdMeta = const VerificationMeta(
    'importId',
  );
  @override
  late final GeneratedColumn<String> importId = GeneratedColumn<String>(
    'import_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [mangaId, importId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_manga_import';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalMangaImportData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('manga_id')) {
      context.handle(
        _mangaIdMeta,
        mangaId.isAcceptableOrUnknown(data['manga_id']!, _mangaIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mangaIdMeta);
    }
    if (data.containsKey('import_id')) {
      context.handle(
        _importIdMeta,
        importId.isAcceptableOrUnknown(data['import_id']!, _importIdMeta),
      );
    } else if (isInserting) {
      context.missing(_importIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mangaId, importId};
  @override
  LocalMangaImportData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalMangaImportData(
      mangaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manga_id'],
      )!,
      importId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}import_id'],
      )!,
    );
  }

  @override
  $LocalMangaImportTable createAlias(String alias) {
    return $LocalMangaImportTable(attachedDatabase, alias);
  }
}

class LocalMangaImportData extends DataClass
    implements Insertable<LocalMangaImportData> {
  final String mangaId;
  final String importId;
  const LocalMangaImportData({required this.mangaId, required this.importId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['manga_id'] = Variable<String>(mangaId);
    map['import_id'] = Variable<String>(importId);
    return map;
  }

  LocalMangaImportCompanion toCompanion(bool nullToAbsent) {
    return LocalMangaImportCompanion(
      mangaId: Value(mangaId),
      importId: Value(importId),
    );
  }

  factory LocalMangaImportData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalMangaImportData(
      mangaId: serializer.fromJson<String>(json['mangaId']),
      importId: serializer.fromJson<String>(json['importId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'mangaId': serializer.toJson<String>(mangaId),
      'importId': serializer.toJson<String>(importId),
    };
  }

  LocalMangaImportData copyWith({String? mangaId, String? importId}) =>
      LocalMangaImportData(
        mangaId: mangaId ?? this.mangaId,
        importId: importId ?? this.importId,
      );
  LocalMangaImportData copyWithCompanion(LocalMangaImportCompanion data) {
    return LocalMangaImportData(
      mangaId: data.mangaId.present ? data.mangaId.value : this.mangaId,
      importId: data.importId.present ? data.importId.value : this.importId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalMangaImportData(')
          ..write('mangaId: $mangaId, ')
          ..write('importId: $importId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(mangaId, importId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalMangaImportData &&
          other.mangaId == this.mangaId &&
          other.importId == this.importId);
}

class LocalMangaImportCompanion extends UpdateCompanion<LocalMangaImportData> {
  final Value<String> mangaId;
  final Value<String> importId;
  final Value<int> rowid;
  const LocalMangaImportCompanion({
    this.mangaId = const Value.absent(),
    this.importId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalMangaImportCompanion.insert({
    required String mangaId,
    required String importId,
    this.rowid = const Value.absent(),
  }) : mangaId = Value(mangaId),
       importId = Value(importId);
  static Insertable<LocalMangaImportData> custom({
    Expression<String>? mangaId,
    Expression<String>? importId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mangaId != null) 'manga_id': mangaId,
      if (importId != null) 'import_id': importId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalMangaImportCompanion copyWith({
    Value<String>? mangaId,
    Value<String>? importId,
    Value<int>? rowid,
  }) {
    return LocalMangaImportCompanion(
      mangaId: mangaId ?? this.mangaId,
      importId: importId ?? this.importId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mangaId.present) {
      map['manga_id'] = Variable<String>(mangaId.value);
    }
    if (importId.present) {
      map['import_id'] = Variable<String>(importId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalMangaImportCompanion(')
          ..write('mangaId: $mangaId, ')
          ..write('importId: $importId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalBackupAppTable extends LocalBackupApp
    with TableInfo<$LocalBackupAppTable, LocalBackupAppData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalBackupAppTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accentMeta = const VerificationMeta('accent');
  @override
  late final GeneratedColumn<String> accent = GeneratedColumn<String>(
    'accent',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _curatedMeta = const VerificationMeta(
    'curated',
  );
  @override
  late final GeneratedColumn<bool> curated = GeneratedColumn<bool>(
    'curated',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("curated" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [id, displayName, accent, curated];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_backup_app';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalBackupAppData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('accent')) {
      context.handle(
        _accentMeta,
        accent.isAcceptableOrUnknown(data['accent']!, _accentMeta),
      );
    }
    if (data.containsKey('curated')) {
      context.handle(
        _curatedMeta,
        curated.isAcceptableOrUnknown(data['curated']!, _curatedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalBackupAppData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalBackupAppData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      accent: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}accent'],
      ),
      curated: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}curated'],
      )!,
    );
  }

  @override
  $LocalBackupAppTable createAlias(String alias) {
    return $LocalBackupAppTable(attachedDatabase, alias);
  }
}

class LocalBackupAppData extends DataClass
    implements Insertable<LocalBackupAppData> {
  /// Android application id, e.g. `app.mihon`.
  final String id;
  final String displayName;

  /// Hex accent for the app's chip; null falls back to the theme.
  final String? accent;

  /// Shipped by the server rather than added by the user.
  final bool curated;
  const LocalBackupAppData({
    required this.id,
    required this.displayName,
    this.accent,
    required this.curated,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['display_name'] = Variable<String>(displayName);
    if (!nullToAbsent || accent != null) {
      map['accent'] = Variable<String>(accent);
    }
    map['curated'] = Variable<bool>(curated);
    return map;
  }

  LocalBackupAppCompanion toCompanion(bool nullToAbsent) {
    return LocalBackupAppCompanion(
      id: Value(id),
      displayName: Value(displayName),
      accent: accent == null && nullToAbsent
          ? const Value.absent()
          : Value(accent),
      curated: Value(curated),
    );
  }

  factory LocalBackupAppData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalBackupAppData(
      id: serializer.fromJson<String>(json['id']),
      displayName: serializer.fromJson<String>(json['displayName']),
      accent: serializer.fromJson<String?>(json['accent']),
      curated: serializer.fromJson<bool>(json['curated']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'displayName': serializer.toJson<String>(displayName),
      'accent': serializer.toJson<String?>(accent),
      'curated': serializer.toJson<bool>(curated),
    };
  }

  LocalBackupAppData copyWith({
    String? id,
    String? displayName,
    Value<String?> accent = const Value.absent(),
    bool? curated,
  }) => LocalBackupAppData(
    id: id ?? this.id,
    displayName: displayName ?? this.displayName,
    accent: accent.present ? accent.value : this.accent,
    curated: curated ?? this.curated,
  );
  LocalBackupAppData copyWithCompanion(LocalBackupAppCompanion data) {
    return LocalBackupAppData(
      id: data.id.present ? data.id.value : this.id,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      accent: data.accent.present ? data.accent.value : this.accent,
      curated: data.curated.present ? data.curated.value : this.curated,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalBackupAppData(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('accent: $accent, ')
          ..write('curated: $curated')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, displayName, accent, curated);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalBackupAppData &&
          other.id == this.id &&
          other.displayName == this.displayName &&
          other.accent == this.accent &&
          other.curated == this.curated);
}

class LocalBackupAppCompanion extends UpdateCompanion<LocalBackupAppData> {
  final Value<String> id;
  final Value<String> displayName;
  final Value<String?> accent;
  final Value<bool> curated;
  final Value<int> rowid;
  const LocalBackupAppCompanion({
    this.id = const Value.absent(),
    this.displayName = const Value.absent(),
    this.accent = const Value.absent(),
    this.curated = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalBackupAppCompanion.insert({
    required String id,
    required String displayName,
    this.accent = const Value.absent(),
    this.curated = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       displayName = Value(displayName);
  static Insertable<LocalBackupAppData> custom({
    Expression<String>? id,
    Expression<String>? displayName,
    Expression<String>? accent,
    Expression<bool>? curated,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (displayName != null) 'display_name': displayName,
      if (accent != null) 'accent': accent,
      if (curated != null) 'curated': curated,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalBackupAppCompanion copyWith({
    Value<String>? id,
    Value<String>? displayName,
    Value<String?>? accent,
    Value<bool>? curated,
    Value<int>? rowid,
  }) {
    return LocalBackupAppCompanion(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      accent: accent ?? this.accent,
      curated: curated ?? this.curated,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (accent.present) {
      map['accent'] = Variable<String>(accent.value);
    }
    if (curated.present) {
      map['curated'] = Variable<bool>(curated.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalBackupAppCompanion(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('accent: $accent, ')
          ..write('curated: $curated, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncMetaTable extends SyncMeta
    with TableInfo<$SyncMetaTable, SyncMetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _cursorMeta = const VerificationMeta('cursor');
  @override
  late final GeneratedColumn<String> cursor = GeneratedColumn<String>(
    'cursor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverEpochMeta = const VerificationMeta(
    'serverEpoch',
  );
  @override
  late final GeneratedColumn<String> serverEpoch = GeneratedColumn<String>(
    'server_epoch',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSyncedAtMeta = const VerificationMeta(
    'lastSyncedAt',
  );
  @override
  late final GeneratedColumn<int> lastSyncedAt = GeneratedColumn<int>(
    'last_synced_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _vaultSizeBytesMeta = const VerificationMeta(
    'vaultSizeBytes',
  );
  @override
  late final GeneratedColumn<int> vaultSizeBytes = GeneratedColumn<int>(
    'vault_size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _vaultDatabaseBytesMeta =
      const VerificationMeta('vaultDatabaseBytes');
  @override
  late final GeneratedColumn<int> vaultDatabaseBytes = GeneratedColumn<int>(
    'vault_database_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _vaultCoversBytesMeta = const VerificationMeta(
    'vaultCoversBytes',
  );
  @override
  late final GeneratedColumn<int> vaultCoversBytes = GeneratedColumn<int>(
    'vault_covers_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _vaultBackupsBytesMeta = const VerificationMeta(
    'vaultBackupsBytes',
  );
  @override
  late final GeneratedColumn<int> vaultBackupsBytes = GeneratedColumn<int>(
    'vault_backups_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _localRevisionMeta = const VerificationMeta(
    'localRevision',
  );
  @override
  late final GeneratedColumn<int> localRevision = GeneratedColumn<int>(
    'local_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    cursor,
    serverEpoch,
    lastSyncedAt,
    vaultSizeBytes,
    vaultDatabaseBytes,
    vaultCoversBytes,
    vaultBackupsBytes,
    localRevision,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncMetaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('cursor')) {
      context.handle(
        _cursorMeta,
        cursor.isAcceptableOrUnknown(data['cursor']!, _cursorMeta),
      );
    }
    if (data.containsKey('server_epoch')) {
      context.handle(
        _serverEpochMeta,
        serverEpoch.isAcceptableOrUnknown(
          data['server_epoch']!,
          _serverEpochMeta,
        ),
      );
    }
    if (data.containsKey('last_synced_at')) {
      context.handle(
        _lastSyncedAtMeta,
        lastSyncedAt.isAcceptableOrUnknown(
          data['last_synced_at']!,
          _lastSyncedAtMeta,
        ),
      );
    }
    if (data.containsKey('vault_size_bytes')) {
      context.handle(
        _vaultSizeBytesMeta,
        vaultSizeBytes.isAcceptableOrUnknown(
          data['vault_size_bytes']!,
          _vaultSizeBytesMeta,
        ),
      );
    }
    if (data.containsKey('vault_database_bytes')) {
      context.handle(
        _vaultDatabaseBytesMeta,
        vaultDatabaseBytes.isAcceptableOrUnknown(
          data['vault_database_bytes']!,
          _vaultDatabaseBytesMeta,
        ),
      );
    }
    if (data.containsKey('vault_covers_bytes')) {
      context.handle(
        _vaultCoversBytesMeta,
        vaultCoversBytes.isAcceptableOrUnknown(
          data['vault_covers_bytes']!,
          _vaultCoversBytesMeta,
        ),
      );
    }
    if (data.containsKey('vault_backups_bytes')) {
      context.handle(
        _vaultBackupsBytesMeta,
        vaultBackupsBytes.isAcceptableOrUnknown(
          data['vault_backups_bytes']!,
          _vaultBackupsBytesMeta,
        ),
      );
    }
    if (data.containsKey('local_revision')) {
      context.handle(
        _localRevisionMeta,
        localRevision.isAcceptableOrUnknown(
          data['local_revision']!,
          _localRevisionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncMetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncMetaData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      cursor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cursor'],
      ),
      serverEpoch: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_epoch'],
      ),
      lastSyncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_synced_at'],
      ),
      vaultSizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}vault_size_bytes'],
      )!,
      vaultDatabaseBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}vault_database_bytes'],
      )!,
      vaultCoversBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}vault_covers_bytes'],
      )!,
      vaultBackupsBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}vault_backups_bytes'],
      )!,
      localRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_revision'],
      )!,
    );
  }

  @override
  $SyncMetaTable createAlias(String alias) {
    return $SyncMetaTable(attachedDatabase, alias);
  }
}

class SyncMetaData extends DataClass implements Insertable<SyncMetaData> {
  final int id;

  /// Server high-water mark already applied locally; null means never synced.
  final String? cursor;

  /// Server identity — a change means Postgres was restored and the local
  /// mirror must be rebuilt from scratch.
  final String? serverEpoch;
  final int? lastSyncedAt;

  /// Vault size in bytes; the one dashboard figure the device cannot derive.
  final int vaultSizeBytes;

  /// The same total split by where it lives on the server. Stored as parts so
  /// the dashboard can show "613 MB of that is covers" while offline.
  final int vaultDatabaseBytes;
  final int vaultCoversBytes;
  final int vaultBackupsBytes;

  /// Bumped once per committed sync transaction. Screens watch this instead of
  /// every table, so one cheap stream drives all the local-read providers.
  final int localRevision;
  const SyncMetaData({
    required this.id,
    this.cursor,
    this.serverEpoch,
    this.lastSyncedAt,
    required this.vaultSizeBytes,
    required this.vaultDatabaseBytes,
    required this.vaultCoversBytes,
    required this.vaultBackupsBytes,
    required this.localRevision,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || cursor != null) {
      map['cursor'] = Variable<String>(cursor);
    }
    if (!nullToAbsent || serverEpoch != null) {
      map['server_epoch'] = Variable<String>(serverEpoch);
    }
    if (!nullToAbsent || lastSyncedAt != null) {
      map['last_synced_at'] = Variable<int>(lastSyncedAt);
    }
    map['vault_size_bytes'] = Variable<int>(vaultSizeBytes);
    map['vault_database_bytes'] = Variable<int>(vaultDatabaseBytes);
    map['vault_covers_bytes'] = Variable<int>(vaultCoversBytes);
    map['vault_backups_bytes'] = Variable<int>(vaultBackupsBytes);
    map['local_revision'] = Variable<int>(localRevision);
    return map;
  }

  SyncMetaCompanion toCompanion(bool nullToAbsent) {
    return SyncMetaCompanion(
      id: Value(id),
      cursor: cursor == null && nullToAbsent
          ? const Value.absent()
          : Value(cursor),
      serverEpoch: serverEpoch == null && nullToAbsent
          ? const Value.absent()
          : Value(serverEpoch),
      lastSyncedAt: lastSyncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncedAt),
      vaultSizeBytes: Value(vaultSizeBytes),
      vaultDatabaseBytes: Value(vaultDatabaseBytes),
      vaultCoversBytes: Value(vaultCoversBytes),
      vaultBackupsBytes: Value(vaultBackupsBytes),
      localRevision: Value(localRevision),
    );
  }

  factory SyncMetaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncMetaData(
      id: serializer.fromJson<int>(json['id']),
      cursor: serializer.fromJson<String?>(json['cursor']),
      serverEpoch: serializer.fromJson<String?>(json['serverEpoch']),
      lastSyncedAt: serializer.fromJson<int?>(json['lastSyncedAt']),
      vaultSizeBytes: serializer.fromJson<int>(json['vaultSizeBytes']),
      vaultDatabaseBytes: serializer.fromJson<int>(json['vaultDatabaseBytes']),
      vaultCoversBytes: serializer.fromJson<int>(json['vaultCoversBytes']),
      vaultBackupsBytes: serializer.fromJson<int>(json['vaultBackupsBytes']),
      localRevision: serializer.fromJson<int>(json['localRevision']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'cursor': serializer.toJson<String?>(cursor),
      'serverEpoch': serializer.toJson<String?>(serverEpoch),
      'lastSyncedAt': serializer.toJson<int?>(lastSyncedAt),
      'vaultSizeBytes': serializer.toJson<int>(vaultSizeBytes),
      'vaultDatabaseBytes': serializer.toJson<int>(vaultDatabaseBytes),
      'vaultCoversBytes': serializer.toJson<int>(vaultCoversBytes),
      'vaultBackupsBytes': serializer.toJson<int>(vaultBackupsBytes),
      'localRevision': serializer.toJson<int>(localRevision),
    };
  }

  SyncMetaData copyWith({
    int? id,
    Value<String?> cursor = const Value.absent(),
    Value<String?> serverEpoch = const Value.absent(),
    Value<int?> lastSyncedAt = const Value.absent(),
    int? vaultSizeBytes,
    int? vaultDatabaseBytes,
    int? vaultCoversBytes,
    int? vaultBackupsBytes,
    int? localRevision,
  }) => SyncMetaData(
    id: id ?? this.id,
    cursor: cursor.present ? cursor.value : this.cursor,
    serverEpoch: serverEpoch.present ? serverEpoch.value : this.serverEpoch,
    lastSyncedAt: lastSyncedAt.present ? lastSyncedAt.value : this.lastSyncedAt,
    vaultSizeBytes: vaultSizeBytes ?? this.vaultSizeBytes,
    vaultDatabaseBytes: vaultDatabaseBytes ?? this.vaultDatabaseBytes,
    vaultCoversBytes: vaultCoversBytes ?? this.vaultCoversBytes,
    vaultBackupsBytes: vaultBackupsBytes ?? this.vaultBackupsBytes,
    localRevision: localRevision ?? this.localRevision,
  );
  SyncMetaData copyWithCompanion(SyncMetaCompanion data) {
    return SyncMetaData(
      id: data.id.present ? data.id.value : this.id,
      cursor: data.cursor.present ? data.cursor.value : this.cursor,
      serverEpoch: data.serverEpoch.present
          ? data.serverEpoch.value
          : this.serverEpoch,
      lastSyncedAt: data.lastSyncedAt.present
          ? data.lastSyncedAt.value
          : this.lastSyncedAt,
      vaultSizeBytes: data.vaultSizeBytes.present
          ? data.vaultSizeBytes.value
          : this.vaultSizeBytes,
      vaultDatabaseBytes: data.vaultDatabaseBytes.present
          ? data.vaultDatabaseBytes.value
          : this.vaultDatabaseBytes,
      vaultCoversBytes: data.vaultCoversBytes.present
          ? data.vaultCoversBytes.value
          : this.vaultCoversBytes,
      vaultBackupsBytes: data.vaultBackupsBytes.present
          ? data.vaultBackupsBytes.value
          : this.vaultBackupsBytes,
      localRevision: data.localRevision.present
          ? data.localRevision.value
          : this.localRevision,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaData(')
          ..write('id: $id, ')
          ..write('cursor: $cursor, ')
          ..write('serverEpoch: $serverEpoch, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('vaultSizeBytes: $vaultSizeBytes, ')
          ..write('vaultDatabaseBytes: $vaultDatabaseBytes, ')
          ..write('vaultCoversBytes: $vaultCoversBytes, ')
          ..write('vaultBackupsBytes: $vaultBackupsBytes, ')
          ..write('localRevision: $localRevision')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    cursor,
    serverEpoch,
    lastSyncedAt,
    vaultSizeBytes,
    vaultDatabaseBytes,
    vaultCoversBytes,
    vaultBackupsBytes,
    localRevision,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncMetaData &&
          other.id == this.id &&
          other.cursor == this.cursor &&
          other.serverEpoch == this.serverEpoch &&
          other.lastSyncedAt == this.lastSyncedAt &&
          other.vaultSizeBytes == this.vaultSizeBytes &&
          other.vaultDatabaseBytes == this.vaultDatabaseBytes &&
          other.vaultCoversBytes == this.vaultCoversBytes &&
          other.vaultBackupsBytes == this.vaultBackupsBytes &&
          other.localRevision == this.localRevision);
}

class SyncMetaCompanion extends UpdateCompanion<SyncMetaData> {
  final Value<int> id;
  final Value<String?> cursor;
  final Value<String?> serverEpoch;
  final Value<int?> lastSyncedAt;
  final Value<int> vaultSizeBytes;
  final Value<int> vaultDatabaseBytes;
  final Value<int> vaultCoversBytes;
  final Value<int> vaultBackupsBytes;
  final Value<int> localRevision;
  const SyncMetaCompanion({
    this.id = const Value.absent(),
    this.cursor = const Value.absent(),
    this.serverEpoch = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.vaultSizeBytes = const Value.absent(),
    this.vaultDatabaseBytes = const Value.absent(),
    this.vaultCoversBytes = const Value.absent(),
    this.vaultBackupsBytes = const Value.absent(),
    this.localRevision = const Value.absent(),
  });
  SyncMetaCompanion.insert({
    this.id = const Value.absent(),
    this.cursor = const Value.absent(),
    this.serverEpoch = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.vaultSizeBytes = const Value.absent(),
    this.vaultDatabaseBytes = const Value.absent(),
    this.vaultCoversBytes = const Value.absent(),
    this.vaultBackupsBytes = const Value.absent(),
    this.localRevision = const Value.absent(),
  });
  static Insertable<SyncMetaData> custom({
    Expression<int>? id,
    Expression<String>? cursor,
    Expression<String>? serverEpoch,
    Expression<int>? lastSyncedAt,
    Expression<int>? vaultSizeBytes,
    Expression<int>? vaultDatabaseBytes,
    Expression<int>? vaultCoversBytes,
    Expression<int>? vaultBackupsBytes,
    Expression<int>? localRevision,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cursor != null) 'cursor': cursor,
      if (serverEpoch != null) 'server_epoch': serverEpoch,
      if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt,
      if (vaultSizeBytes != null) 'vault_size_bytes': vaultSizeBytes,
      if (vaultDatabaseBytes != null)
        'vault_database_bytes': vaultDatabaseBytes,
      if (vaultCoversBytes != null) 'vault_covers_bytes': vaultCoversBytes,
      if (vaultBackupsBytes != null) 'vault_backups_bytes': vaultBackupsBytes,
      if (localRevision != null) 'local_revision': localRevision,
    });
  }

  SyncMetaCompanion copyWith({
    Value<int>? id,
    Value<String?>? cursor,
    Value<String?>? serverEpoch,
    Value<int?>? lastSyncedAt,
    Value<int>? vaultSizeBytes,
    Value<int>? vaultDatabaseBytes,
    Value<int>? vaultCoversBytes,
    Value<int>? vaultBackupsBytes,
    Value<int>? localRevision,
  }) {
    return SyncMetaCompanion(
      id: id ?? this.id,
      cursor: cursor ?? this.cursor,
      serverEpoch: serverEpoch ?? this.serverEpoch,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      vaultSizeBytes: vaultSizeBytes ?? this.vaultSizeBytes,
      vaultDatabaseBytes: vaultDatabaseBytes ?? this.vaultDatabaseBytes,
      vaultCoversBytes: vaultCoversBytes ?? this.vaultCoversBytes,
      vaultBackupsBytes: vaultBackupsBytes ?? this.vaultBackupsBytes,
      localRevision: localRevision ?? this.localRevision,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (cursor.present) {
      map['cursor'] = Variable<String>(cursor.value);
    }
    if (serverEpoch.present) {
      map['server_epoch'] = Variable<String>(serverEpoch.value);
    }
    if (lastSyncedAt.present) {
      map['last_synced_at'] = Variable<int>(lastSyncedAt.value);
    }
    if (vaultSizeBytes.present) {
      map['vault_size_bytes'] = Variable<int>(vaultSizeBytes.value);
    }
    if (vaultDatabaseBytes.present) {
      map['vault_database_bytes'] = Variable<int>(vaultDatabaseBytes.value);
    }
    if (vaultCoversBytes.present) {
      map['vault_covers_bytes'] = Variable<int>(vaultCoversBytes.value);
    }
    if (vaultBackupsBytes.present) {
      map['vault_backups_bytes'] = Variable<int>(vaultBackupsBytes.value);
    }
    if (localRevision.present) {
      map['local_revision'] = Variable<int>(localRevision.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaCompanion(')
          ..write('id: $id, ')
          ..write('cursor: $cursor, ')
          ..write('serverEpoch: $serverEpoch, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('vaultSizeBytes: $vaultSizeBytes, ')
          ..write('vaultDatabaseBytes: $vaultDatabaseBytes, ')
          ..write('vaultCoversBytes: $vaultCoversBytes, ')
          ..write('vaultBackupsBytes: $vaultBackupsBytes, ')
          ..write('localRevision: $localRevision')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $LocalMangaTable localManga = $LocalMangaTable(this);
  late final $LocalCategoryTable localCategory = $LocalCategoryTable(this);
  late final $LocalMangaCategoryTable localMangaCategory =
      $LocalMangaCategoryTable(this);
  late final $LocalImportRecordTable localImportRecord =
      $LocalImportRecordTable(this);
  late final $LocalMangaImportTable localMangaImport = $LocalMangaImportTable(
    this,
  );
  late final $LocalBackupAppTable localBackupApp = $LocalBackupAppTable(this);
  late final $SyncMetaTable syncMeta = $SyncMetaTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localManga,
    localCategory,
    localMangaCategory,
    localImportRecord,
    localMangaImport,
    localBackupApp,
    syncMeta,
  ];
}

typedef $$LocalMangaTableCreateCompanionBuilder =
    LocalMangaCompanion Function({
      required String id,
      required String rowVersion,
      required String sourceId,
      Value<String> sourceName,
      required String title,
      required String titleLower,
      Value<String> authorLower,
      Value<String?> author,
      Value<String?> artist,
      Value<String?> description,
      Value<String> genresJson,
      Value<String> status,
      Value<String?> thumbnailUrl,
      Value<String?> coverPath,
      Value<String> coverState,
      Value<String> notes,
      Value<bool> favorite,
      Value<int> dateAdded,
      Value<int> updatedAt,
      Value<int> chapterCount,
      Value<int> readCount,
      Value<int> unreadCount,
      Value<int?> lastReadAt,
      Value<String?> lastReadChapterName,
      Value<double?> lastReadChapterNumber,
      Value<String?> nextChapterName,
      Value<double?> nextChapterNumber,
      Value<int> rowid,
    });
typedef $$LocalMangaTableUpdateCompanionBuilder =
    LocalMangaCompanion Function({
      Value<String> id,
      Value<String> rowVersion,
      Value<String> sourceId,
      Value<String> sourceName,
      Value<String> title,
      Value<String> titleLower,
      Value<String> authorLower,
      Value<String?> author,
      Value<String?> artist,
      Value<String?> description,
      Value<String> genresJson,
      Value<String> status,
      Value<String?> thumbnailUrl,
      Value<String?> coverPath,
      Value<String> coverState,
      Value<String> notes,
      Value<bool> favorite,
      Value<int> dateAdded,
      Value<int> updatedAt,
      Value<int> chapterCount,
      Value<int> readCount,
      Value<int> unreadCount,
      Value<int?> lastReadAt,
      Value<String?> lastReadChapterName,
      Value<double?> lastReadChapterNumber,
      Value<String?> nextChapterName,
      Value<double?> nextChapterNumber,
      Value<int> rowid,
    });

class $$LocalMangaTableFilterComposer
    extends Composer<_$AppDatabase, $LocalMangaTable> {
  $$LocalMangaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get titleLower => $composableBuilder(
    column: $table.titleLower,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authorLower => $composableBuilder(
    column: $table.authorLower,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get genresJson => $composableBuilder(
    column: $table.genresJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbnailUrl => $composableBuilder(
    column: $table.thumbnailUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverState => $composableBuilder(
    column: $table.coverState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dateAdded => $composableBuilder(
    column: $table.dateAdded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chapterCount => $composableBuilder(
    column: $table.chapterCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get readCount => $composableBuilder(
    column: $table.readCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastReadChapterName => $composableBuilder(
    column: $table.lastReadChapterName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lastReadChapterNumber => $composableBuilder(
    column: $table.lastReadChapterNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nextChapterName => $composableBuilder(
    column: $table.nextChapterName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get nextChapterNumber => $composableBuilder(
    column: $table.nextChapterNumber,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalMangaTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalMangaTable> {
  $$LocalMangaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get titleLower => $composableBuilder(
    column: $table.titleLower,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authorLower => $composableBuilder(
    column: $table.authorLower,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get genresJson => $composableBuilder(
    column: $table.genresJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnailUrl => $composableBuilder(
    column: $table.thumbnailUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverState => $composableBuilder(
    column: $table.coverState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dateAdded => $composableBuilder(
    column: $table.dateAdded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chapterCount => $composableBuilder(
    column: $table.chapterCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get readCount => $composableBuilder(
    column: $table.readCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastReadChapterName => $composableBuilder(
    column: $table.lastReadChapterName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lastReadChapterNumber => $composableBuilder(
    column: $table.lastReadChapterNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nextChapterName => $composableBuilder(
    column: $table.nextChapterName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get nextChapterNumber => $composableBuilder(
    column: $table.nextChapterNumber,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalMangaTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalMangaTable> {
  $$LocalMangaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get titleLower => $composableBuilder(
    column: $table.titleLower,
    builder: (column) => column,
  );

  GeneratedColumn<String> get authorLower => $composableBuilder(
    column: $table.authorLower,
    builder: (column) => column,
  );

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get genresJson => $composableBuilder(
    column: $table.genresJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get thumbnailUrl => $composableBuilder(
    column: $table.thumbnailUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get coverPath =>
      $composableBuilder(column: $table.coverPath, builder: (column) => column);

  GeneratedColumn<String> get coverState => $composableBuilder(
    column: $table.coverState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<bool> get favorite =>
      $composableBuilder(column: $table.favorite, builder: (column) => column);

  GeneratedColumn<int> get dateAdded =>
      $composableBuilder(column: $table.dateAdded, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get chapterCount => $composableBuilder(
    column: $table.chapterCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get readCount =>
      $composableBuilder(column: $table.readCount, builder: (column) => column);

  GeneratedColumn<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastReadChapterName => $composableBuilder(
    column: $table.lastReadChapterName,
    builder: (column) => column,
  );

  GeneratedColumn<double> get lastReadChapterNumber => $composableBuilder(
    column: $table.lastReadChapterNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nextChapterName => $composableBuilder(
    column: $table.nextChapterName,
    builder: (column) => column,
  );

  GeneratedColumn<double> get nextChapterNumber => $composableBuilder(
    column: $table.nextChapterNumber,
    builder: (column) => column,
  );
}

class $$LocalMangaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalMangaTable,
          LocalMangaRow,
          $$LocalMangaTableFilterComposer,
          $$LocalMangaTableOrderingComposer,
          $$LocalMangaTableAnnotationComposer,
          $$LocalMangaTableCreateCompanionBuilder,
          $$LocalMangaTableUpdateCompanionBuilder,
          (
            LocalMangaRow,
            BaseReferences<_$AppDatabase, $LocalMangaTable, LocalMangaRow>,
          ),
          LocalMangaRow,
          PrefetchHooks Function()
        > {
  $$LocalMangaTableTableManager(_$AppDatabase db, $LocalMangaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalMangaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalMangaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalMangaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> rowVersion = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<String> sourceName = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> titleLower = const Value.absent(),
                Value<String> authorLower = const Value.absent(),
                Value<String?> author = const Value.absent(),
                Value<String?> artist = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String> genresJson = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> thumbnailUrl = const Value.absent(),
                Value<String?> coverPath = const Value.absent(),
                Value<String> coverState = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<int> dateAdded = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> chapterCount = const Value.absent(),
                Value<int> readCount = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<int?> lastReadAt = const Value.absent(),
                Value<String?> lastReadChapterName = const Value.absent(),
                Value<double?> lastReadChapterNumber = const Value.absent(),
                Value<String?> nextChapterName = const Value.absent(),
                Value<double?> nextChapterNumber = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalMangaCompanion(
                id: id,
                rowVersion: rowVersion,
                sourceId: sourceId,
                sourceName: sourceName,
                title: title,
                titleLower: titleLower,
                authorLower: authorLower,
                author: author,
                artist: artist,
                description: description,
                genresJson: genresJson,
                status: status,
                thumbnailUrl: thumbnailUrl,
                coverPath: coverPath,
                coverState: coverState,
                notes: notes,
                favorite: favorite,
                dateAdded: dateAdded,
                updatedAt: updatedAt,
                chapterCount: chapterCount,
                readCount: readCount,
                unreadCount: unreadCount,
                lastReadAt: lastReadAt,
                lastReadChapterName: lastReadChapterName,
                lastReadChapterNumber: lastReadChapterNumber,
                nextChapterName: nextChapterName,
                nextChapterNumber: nextChapterNumber,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String rowVersion,
                required String sourceId,
                Value<String> sourceName = const Value.absent(),
                required String title,
                required String titleLower,
                Value<String> authorLower = const Value.absent(),
                Value<String?> author = const Value.absent(),
                Value<String?> artist = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String> genresJson = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> thumbnailUrl = const Value.absent(),
                Value<String?> coverPath = const Value.absent(),
                Value<String> coverState = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<int> dateAdded = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> chapterCount = const Value.absent(),
                Value<int> readCount = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<int?> lastReadAt = const Value.absent(),
                Value<String?> lastReadChapterName = const Value.absent(),
                Value<double?> lastReadChapterNumber = const Value.absent(),
                Value<String?> nextChapterName = const Value.absent(),
                Value<double?> nextChapterNumber = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalMangaCompanion.insert(
                id: id,
                rowVersion: rowVersion,
                sourceId: sourceId,
                sourceName: sourceName,
                title: title,
                titleLower: titleLower,
                authorLower: authorLower,
                author: author,
                artist: artist,
                description: description,
                genresJson: genresJson,
                status: status,
                thumbnailUrl: thumbnailUrl,
                coverPath: coverPath,
                coverState: coverState,
                notes: notes,
                favorite: favorite,
                dateAdded: dateAdded,
                updatedAt: updatedAt,
                chapterCount: chapterCount,
                readCount: readCount,
                unreadCount: unreadCount,
                lastReadAt: lastReadAt,
                lastReadChapterName: lastReadChapterName,
                lastReadChapterNumber: lastReadChapterNumber,
                nextChapterName: nextChapterName,
                nextChapterNumber: nextChapterNumber,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalMangaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalMangaTable,
      LocalMangaRow,
      $$LocalMangaTableFilterComposer,
      $$LocalMangaTableOrderingComposer,
      $$LocalMangaTableAnnotationComposer,
      $$LocalMangaTableCreateCompanionBuilder,
      $$LocalMangaTableUpdateCompanionBuilder,
      (
        LocalMangaRow,
        BaseReferences<_$AppDatabase, $LocalMangaTable, LocalMangaRow>,
      ),
      LocalMangaRow,
      PrefetchHooks Function()
    >;
typedef $$LocalCategoryTableCreateCompanionBuilder =
    LocalCategoryCompanion Function({
      required String id,
      required String name,
      Value<int> sort,
      Value<int> rowid,
    });
typedef $$LocalCategoryTableUpdateCompanionBuilder =
    LocalCategoryCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<int> sort,
      Value<int> rowid,
    });

class $$LocalCategoryTableFilterComposer
    extends Composer<_$AppDatabase, $LocalCategoryTable> {
  $$LocalCategoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalCategoryTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalCategoryTable> {
  $$LocalCategoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalCategoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalCategoryTable> {
  $$LocalCategoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sort =>
      $composableBuilder(column: $table.sort, builder: (column) => column);
}

class $$LocalCategoryTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalCategoryTable,
          LocalCategoryData,
          $$LocalCategoryTableFilterComposer,
          $$LocalCategoryTableOrderingComposer,
          $$LocalCategoryTableAnnotationComposer,
          $$LocalCategoryTableCreateCompanionBuilder,
          $$LocalCategoryTableUpdateCompanionBuilder,
          (
            LocalCategoryData,
            BaseReferences<
              _$AppDatabase,
              $LocalCategoryTable,
              LocalCategoryData
            >,
          ),
          LocalCategoryData,
          PrefetchHooks Function()
        > {
  $$LocalCategoryTableTableManager(_$AppDatabase db, $LocalCategoryTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalCategoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalCategoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalCategoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> sort = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalCategoryCompanion(
                id: id,
                name: name,
                sort: sort,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<int> sort = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalCategoryCompanion.insert(
                id: id,
                name: name,
                sort: sort,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalCategoryTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalCategoryTable,
      LocalCategoryData,
      $$LocalCategoryTableFilterComposer,
      $$LocalCategoryTableOrderingComposer,
      $$LocalCategoryTableAnnotationComposer,
      $$LocalCategoryTableCreateCompanionBuilder,
      $$LocalCategoryTableUpdateCompanionBuilder,
      (
        LocalCategoryData,
        BaseReferences<_$AppDatabase, $LocalCategoryTable, LocalCategoryData>,
      ),
      LocalCategoryData,
      PrefetchHooks Function()
    >;
typedef $$LocalMangaCategoryTableCreateCompanionBuilder =
    LocalMangaCategoryCompanion Function({
      required String mangaId,
      required String categoryId,
      Value<int> rowid,
    });
typedef $$LocalMangaCategoryTableUpdateCompanionBuilder =
    LocalMangaCategoryCompanion Function({
      Value<String> mangaId,
      Value<String> categoryId,
      Value<int> rowid,
    });

class $$LocalMangaCategoryTableFilterComposer
    extends Composer<_$AppDatabase, $LocalMangaCategoryTable> {
  $$LocalMangaCategoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get mangaId => $composableBuilder(
    column: $table.mangaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalMangaCategoryTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalMangaCategoryTable> {
  $$LocalMangaCategoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get mangaId => $composableBuilder(
    column: $table.mangaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalMangaCategoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalMangaCategoryTable> {
  $$LocalMangaCategoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mangaId =>
      $composableBuilder(column: $table.mangaId, builder: (column) => column);

  GeneratedColumn<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );
}

class $$LocalMangaCategoryTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalMangaCategoryTable,
          LocalMangaCategoryData,
          $$LocalMangaCategoryTableFilterComposer,
          $$LocalMangaCategoryTableOrderingComposer,
          $$LocalMangaCategoryTableAnnotationComposer,
          $$LocalMangaCategoryTableCreateCompanionBuilder,
          $$LocalMangaCategoryTableUpdateCompanionBuilder,
          (
            LocalMangaCategoryData,
            BaseReferences<
              _$AppDatabase,
              $LocalMangaCategoryTable,
              LocalMangaCategoryData
            >,
          ),
          LocalMangaCategoryData,
          PrefetchHooks Function()
        > {
  $$LocalMangaCategoryTableTableManager(
    _$AppDatabase db,
    $LocalMangaCategoryTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalMangaCategoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalMangaCategoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalMangaCategoryTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> mangaId = const Value.absent(),
                Value<String> categoryId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalMangaCategoryCompanion(
                mangaId: mangaId,
                categoryId: categoryId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String mangaId,
                required String categoryId,
                Value<int> rowid = const Value.absent(),
              }) => LocalMangaCategoryCompanion.insert(
                mangaId: mangaId,
                categoryId: categoryId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalMangaCategoryTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalMangaCategoryTable,
      LocalMangaCategoryData,
      $$LocalMangaCategoryTableFilterComposer,
      $$LocalMangaCategoryTableOrderingComposer,
      $$LocalMangaCategoryTableAnnotationComposer,
      $$LocalMangaCategoryTableCreateCompanionBuilder,
      $$LocalMangaCategoryTableUpdateCompanionBuilder,
      (
        LocalMangaCategoryData,
        BaseReferences<
          _$AppDatabase,
          $LocalMangaCategoryTable,
          LocalMangaCategoryData
        >,
      ),
      LocalMangaCategoryData,
      PrefetchHooks Function()
    >;
typedef $$LocalImportRecordTableCreateCompanionBuilder =
    LocalImportRecordCompanion Function({
      required String id,
      required String fileName,
      Value<int> fileSize,
      Value<String> sha256,
      Value<String> sourceApp,
      Value<String> container,
      Value<int> importedAt,
      Value<String> statsJson,
      Value<int> rowid,
    });
typedef $$LocalImportRecordTableUpdateCompanionBuilder =
    LocalImportRecordCompanion Function({
      Value<String> id,
      Value<String> fileName,
      Value<int> fileSize,
      Value<String> sha256,
      Value<String> sourceApp,
      Value<String> container,
      Value<int> importedAt,
      Value<String> statsJson,
      Value<int> rowid,
    });

class $$LocalImportRecordTableFilterComposer
    extends Composer<_$AppDatabase, $LocalImportRecordTable> {
  $$LocalImportRecordTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceApp => $composableBuilder(
    column: $table.sourceApp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get container => $composableBuilder(
    column: $table.container,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get statsJson => $composableBuilder(
    column: $table.statsJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalImportRecordTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalImportRecordTable> {
  $$LocalImportRecordTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceApp => $composableBuilder(
    column: $table.sourceApp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get container => $composableBuilder(
    column: $table.container,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get statsJson => $composableBuilder(
    column: $table.statsJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalImportRecordTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalImportRecordTable> {
  $$LocalImportRecordTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<int> get fileSize =>
      $composableBuilder(column: $table.fileSize, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<String> get sourceApp =>
      $composableBuilder(column: $table.sourceApp, builder: (column) => column);

  GeneratedColumn<String> get container =>
      $composableBuilder(column: $table.container, builder: (column) => column);

  GeneratedColumn<int> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get statsJson =>
      $composableBuilder(column: $table.statsJson, builder: (column) => column);
}

class $$LocalImportRecordTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalImportRecordTable,
          LocalImportRecordData,
          $$LocalImportRecordTableFilterComposer,
          $$LocalImportRecordTableOrderingComposer,
          $$LocalImportRecordTableAnnotationComposer,
          $$LocalImportRecordTableCreateCompanionBuilder,
          $$LocalImportRecordTableUpdateCompanionBuilder,
          (
            LocalImportRecordData,
            BaseReferences<
              _$AppDatabase,
              $LocalImportRecordTable,
              LocalImportRecordData
            >,
          ),
          LocalImportRecordData,
          PrefetchHooks Function()
        > {
  $$LocalImportRecordTableTableManager(
    _$AppDatabase db,
    $LocalImportRecordTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalImportRecordTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalImportRecordTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalImportRecordTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<int> fileSize = const Value.absent(),
                Value<String> sha256 = const Value.absent(),
                Value<String> sourceApp = const Value.absent(),
                Value<String> container = const Value.absent(),
                Value<int> importedAt = const Value.absent(),
                Value<String> statsJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalImportRecordCompanion(
                id: id,
                fileName: fileName,
                fileSize: fileSize,
                sha256: sha256,
                sourceApp: sourceApp,
                container: container,
                importedAt: importedAt,
                statsJson: statsJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String fileName,
                Value<int> fileSize = const Value.absent(),
                Value<String> sha256 = const Value.absent(),
                Value<String> sourceApp = const Value.absent(),
                Value<String> container = const Value.absent(),
                Value<int> importedAt = const Value.absent(),
                Value<String> statsJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalImportRecordCompanion.insert(
                id: id,
                fileName: fileName,
                fileSize: fileSize,
                sha256: sha256,
                sourceApp: sourceApp,
                container: container,
                importedAt: importedAt,
                statsJson: statsJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalImportRecordTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalImportRecordTable,
      LocalImportRecordData,
      $$LocalImportRecordTableFilterComposer,
      $$LocalImportRecordTableOrderingComposer,
      $$LocalImportRecordTableAnnotationComposer,
      $$LocalImportRecordTableCreateCompanionBuilder,
      $$LocalImportRecordTableUpdateCompanionBuilder,
      (
        LocalImportRecordData,
        BaseReferences<
          _$AppDatabase,
          $LocalImportRecordTable,
          LocalImportRecordData
        >,
      ),
      LocalImportRecordData,
      PrefetchHooks Function()
    >;
typedef $$LocalMangaImportTableCreateCompanionBuilder =
    LocalMangaImportCompanion Function({
      required String mangaId,
      required String importId,
      Value<int> rowid,
    });
typedef $$LocalMangaImportTableUpdateCompanionBuilder =
    LocalMangaImportCompanion Function({
      Value<String> mangaId,
      Value<String> importId,
      Value<int> rowid,
    });

class $$LocalMangaImportTableFilterComposer
    extends Composer<_$AppDatabase, $LocalMangaImportTable> {
  $$LocalMangaImportTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get mangaId => $composableBuilder(
    column: $table.mangaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get importId => $composableBuilder(
    column: $table.importId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalMangaImportTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalMangaImportTable> {
  $$LocalMangaImportTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get mangaId => $composableBuilder(
    column: $table.mangaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get importId => $composableBuilder(
    column: $table.importId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalMangaImportTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalMangaImportTable> {
  $$LocalMangaImportTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mangaId =>
      $composableBuilder(column: $table.mangaId, builder: (column) => column);

  GeneratedColumn<String> get importId =>
      $composableBuilder(column: $table.importId, builder: (column) => column);
}

class $$LocalMangaImportTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalMangaImportTable,
          LocalMangaImportData,
          $$LocalMangaImportTableFilterComposer,
          $$LocalMangaImportTableOrderingComposer,
          $$LocalMangaImportTableAnnotationComposer,
          $$LocalMangaImportTableCreateCompanionBuilder,
          $$LocalMangaImportTableUpdateCompanionBuilder,
          (
            LocalMangaImportData,
            BaseReferences<
              _$AppDatabase,
              $LocalMangaImportTable,
              LocalMangaImportData
            >,
          ),
          LocalMangaImportData,
          PrefetchHooks Function()
        > {
  $$LocalMangaImportTableTableManager(
    _$AppDatabase db,
    $LocalMangaImportTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalMangaImportTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalMangaImportTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalMangaImportTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> mangaId = const Value.absent(),
                Value<String> importId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalMangaImportCompanion(
                mangaId: mangaId,
                importId: importId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String mangaId,
                required String importId,
                Value<int> rowid = const Value.absent(),
              }) => LocalMangaImportCompanion.insert(
                mangaId: mangaId,
                importId: importId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalMangaImportTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalMangaImportTable,
      LocalMangaImportData,
      $$LocalMangaImportTableFilterComposer,
      $$LocalMangaImportTableOrderingComposer,
      $$LocalMangaImportTableAnnotationComposer,
      $$LocalMangaImportTableCreateCompanionBuilder,
      $$LocalMangaImportTableUpdateCompanionBuilder,
      (
        LocalMangaImportData,
        BaseReferences<
          _$AppDatabase,
          $LocalMangaImportTable,
          LocalMangaImportData
        >,
      ),
      LocalMangaImportData,
      PrefetchHooks Function()
    >;
typedef $$LocalBackupAppTableCreateCompanionBuilder =
    LocalBackupAppCompanion Function({
      required String id,
      required String displayName,
      Value<String?> accent,
      Value<bool> curated,
      Value<int> rowid,
    });
typedef $$LocalBackupAppTableUpdateCompanionBuilder =
    LocalBackupAppCompanion Function({
      Value<String> id,
      Value<String> displayName,
      Value<String?> accent,
      Value<bool> curated,
      Value<int> rowid,
    });

class $$LocalBackupAppTableFilterComposer
    extends Composer<_$AppDatabase, $LocalBackupAppTable> {
  $$LocalBackupAppTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accent => $composableBuilder(
    column: $table.accent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get curated => $composableBuilder(
    column: $table.curated,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalBackupAppTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalBackupAppTable> {
  $$LocalBackupAppTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accent => $composableBuilder(
    column: $table.accent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get curated => $composableBuilder(
    column: $table.curated,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalBackupAppTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalBackupAppTable> {
  $$LocalBackupAppTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get accent =>
      $composableBuilder(column: $table.accent, builder: (column) => column);

  GeneratedColumn<bool> get curated =>
      $composableBuilder(column: $table.curated, builder: (column) => column);
}

class $$LocalBackupAppTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalBackupAppTable,
          LocalBackupAppData,
          $$LocalBackupAppTableFilterComposer,
          $$LocalBackupAppTableOrderingComposer,
          $$LocalBackupAppTableAnnotationComposer,
          $$LocalBackupAppTableCreateCompanionBuilder,
          $$LocalBackupAppTableUpdateCompanionBuilder,
          (
            LocalBackupAppData,
            BaseReferences<
              _$AppDatabase,
              $LocalBackupAppTable,
              LocalBackupAppData
            >,
          ),
          LocalBackupAppData,
          PrefetchHooks Function()
        > {
  $$LocalBackupAppTableTableManager(
    _$AppDatabase db,
    $LocalBackupAppTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalBackupAppTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalBackupAppTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalBackupAppTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String?> accent = const Value.absent(),
                Value<bool> curated = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalBackupAppCompanion(
                id: id,
                displayName: displayName,
                accent: accent,
                curated: curated,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String displayName,
                Value<String?> accent = const Value.absent(),
                Value<bool> curated = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalBackupAppCompanion.insert(
                id: id,
                displayName: displayName,
                accent: accent,
                curated: curated,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalBackupAppTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalBackupAppTable,
      LocalBackupAppData,
      $$LocalBackupAppTableFilterComposer,
      $$LocalBackupAppTableOrderingComposer,
      $$LocalBackupAppTableAnnotationComposer,
      $$LocalBackupAppTableCreateCompanionBuilder,
      $$LocalBackupAppTableUpdateCompanionBuilder,
      (
        LocalBackupAppData,
        BaseReferences<_$AppDatabase, $LocalBackupAppTable, LocalBackupAppData>,
      ),
      LocalBackupAppData,
      PrefetchHooks Function()
    >;
typedef $$SyncMetaTableCreateCompanionBuilder =
    SyncMetaCompanion Function({
      Value<int> id,
      Value<String?> cursor,
      Value<String?> serverEpoch,
      Value<int?> lastSyncedAt,
      Value<int> vaultSizeBytes,
      Value<int> vaultDatabaseBytes,
      Value<int> vaultCoversBytes,
      Value<int> vaultBackupsBytes,
      Value<int> localRevision,
    });
typedef $$SyncMetaTableUpdateCompanionBuilder =
    SyncMetaCompanion Function({
      Value<int> id,
      Value<String?> cursor,
      Value<String?> serverEpoch,
      Value<int?> lastSyncedAt,
      Value<int> vaultSizeBytes,
      Value<int> vaultDatabaseBytes,
      Value<int> vaultCoversBytes,
      Value<int> vaultBackupsBytes,
      Value<int> localRevision,
    });

class $$SyncMetaTableFilterComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cursor => $composableBuilder(
    column: $table.cursor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverEpoch => $composableBuilder(
    column: $table.serverEpoch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get vaultSizeBytes => $composableBuilder(
    column: $table.vaultSizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get vaultDatabaseBytes => $composableBuilder(
    column: $table.vaultDatabaseBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get vaultCoversBytes => $composableBuilder(
    column: $table.vaultCoversBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get vaultBackupsBytes => $composableBuilder(
    column: $table.vaultBackupsBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncMetaTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cursor => $composableBuilder(
    column: $table.cursor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverEpoch => $composableBuilder(
    column: $table.serverEpoch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get vaultSizeBytes => $composableBuilder(
    column: $table.vaultSizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get vaultDatabaseBytes => $composableBuilder(
    column: $table.vaultDatabaseBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get vaultCoversBytes => $composableBuilder(
    column: $table.vaultCoversBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get vaultBackupsBytes => $composableBuilder(
    column: $table.vaultBackupsBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncMetaTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get cursor =>
      $composableBuilder(column: $table.cursor, builder: (column) => column);

  GeneratedColumn<String> get serverEpoch => $composableBuilder(
    column: $table.serverEpoch,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get vaultSizeBytes => $composableBuilder(
    column: $table.vaultSizeBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get vaultDatabaseBytes => $composableBuilder(
    column: $table.vaultDatabaseBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get vaultCoversBytes => $composableBuilder(
    column: $table.vaultCoversBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get vaultBackupsBytes => $composableBuilder(
    column: $table.vaultBackupsBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => column,
  );
}

class $$SyncMetaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncMetaTable,
          SyncMetaData,
          $$SyncMetaTableFilterComposer,
          $$SyncMetaTableOrderingComposer,
          $$SyncMetaTableAnnotationComposer,
          $$SyncMetaTableCreateCompanionBuilder,
          $$SyncMetaTableUpdateCompanionBuilder,
          (
            SyncMetaData,
            BaseReferences<_$AppDatabase, $SyncMetaTable, SyncMetaData>,
          ),
          SyncMetaData,
          PrefetchHooks Function()
        > {
  $$SyncMetaTableTableManager(_$AppDatabase db, $SyncMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> cursor = const Value.absent(),
                Value<String?> serverEpoch = const Value.absent(),
                Value<int?> lastSyncedAt = const Value.absent(),
                Value<int> vaultSizeBytes = const Value.absent(),
                Value<int> vaultDatabaseBytes = const Value.absent(),
                Value<int> vaultCoversBytes = const Value.absent(),
                Value<int> vaultBackupsBytes = const Value.absent(),
                Value<int> localRevision = const Value.absent(),
              }) => SyncMetaCompanion(
                id: id,
                cursor: cursor,
                serverEpoch: serverEpoch,
                lastSyncedAt: lastSyncedAt,
                vaultSizeBytes: vaultSizeBytes,
                vaultDatabaseBytes: vaultDatabaseBytes,
                vaultCoversBytes: vaultCoversBytes,
                vaultBackupsBytes: vaultBackupsBytes,
                localRevision: localRevision,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> cursor = const Value.absent(),
                Value<String?> serverEpoch = const Value.absent(),
                Value<int?> lastSyncedAt = const Value.absent(),
                Value<int> vaultSizeBytes = const Value.absent(),
                Value<int> vaultDatabaseBytes = const Value.absent(),
                Value<int> vaultCoversBytes = const Value.absent(),
                Value<int> vaultBackupsBytes = const Value.absent(),
                Value<int> localRevision = const Value.absent(),
              }) => SyncMetaCompanion.insert(
                id: id,
                cursor: cursor,
                serverEpoch: serverEpoch,
                lastSyncedAt: lastSyncedAt,
                vaultSizeBytes: vaultSizeBytes,
                vaultDatabaseBytes: vaultDatabaseBytes,
                vaultCoversBytes: vaultCoversBytes,
                vaultBackupsBytes: vaultBackupsBytes,
                localRevision: localRevision,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncMetaTable,
      SyncMetaData,
      $$SyncMetaTableFilterComposer,
      $$SyncMetaTableOrderingComposer,
      $$SyncMetaTableAnnotationComposer,
      $$SyncMetaTableCreateCompanionBuilder,
      $$SyncMetaTableUpdateCompanionBuilder,
      (
        SyncMetaData,
        BaseReferences<_$AppDatabase, $SyncMetaTable, SyncMetaData>,
      ),
      SyncMetaData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$LocalMangaTableTableManager get localManga =>
      $$LocalMangaTableTableManager(_db, _db.localManga);
  $$LocalCategoryTableTableManager get localCategory =>
      $$LocalCategoryTableTableManager(_db, _db.localCategory);
  $$LocalMangaCategoryTableTableManager get localMangaCategory =>
      $$LocalMangaCategoryTableTableManager(_db, _db.localMangaCategory);
  $$LocalImportRecordTableTableManager get localImportRecord =>
      $$LocalImportRecordTableTableManager(_db, _db.localImportRecord);
  $$LocalMangaImportTableTableManager get localMangaImport =>
      $$LocalMangaImportTableTableManager(_db, _db.localMangaImport);
  $$LocalBackupAppTableTableManager get localBackupApp =>
      $$LocalBackupAppTableTableManager(_db, _db.localBackupApp);
  $$SyncMetaTableTableManager get syncMeta =>
      $$SyncMetaTableTableManager(_db, _db.syncMeta);
}

import 'package:flutter/foundation.dart';

/// How titles are picked for an export. Mirrors the server's `ExportMode`.
enum ExportMode {
  /// The whole vault; filters are ignored.
  all,

  /// The facet query in [ExportFilters].
  filter,

  /// A hand-picked list of title ids.
  ids;

  String get wire => name;

  static ExportMode fromWire(Object? raw) => switch (raw) {
    'filter' => ExportMode.filter,
    'ids' => ExportMode.ids,
    _ => ExportMode.all,
  };
}

List<String> _sorted(Iterable<String> values) {
  final list = values.toList()..sort();
  return list;
}

Set<String> _stringSet(Object? raw) => {
  for (final value in raw is List ? raw : const [])
    if (value is String && value.isNotEmpty) value,
};

/// One selectable value plus how many titles it covers.
@immutable
class ExportFacetOption {
  const ExportFacetOption({
    required this.id,
    required this.label,
    required this.count,
  });

  final String id;
  final String label;
  final int count;

  factory ExportFacetOption.fromJson(Map<String, dynamic> json) =>
      ExportFacetOption(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        count: (json['count'] as num?)?.toInt() ?? 0,
      );
}

/// Everything the scope builder can offer, with live counts.
@immutable
class ExportFacets {
  const ExportFacets({
    required this.totalTitles,
    required this.favoriteTitles,
    required this.totalChapters,
    required this.apps,
    required this.sources,
    required this.categories,
    required this.statuses,
  });

  final int totalTitles;
  final int favoriteTitles;
  final int totalChapters;
  final List<ExportFacetOption> apps;
  final List<ExportFacetOption> sources;
  final List<ExportFacetOption> categories;
  final List<ExportFacetOption> statuses;

  static List<ExportFacetOption> _list(dynamic raw) =>
      (raw as List<dynamic>? ?? const [])
          .map((e) => ExportFacetOption.fromJson(e as Map<String, dynamic>))
          .toList();

  factory ExportFacets.fromJson(Map<String, dynamic> json) => ExportFacets(
    totalTitles: (json['totalTitles'] as num?)?.toInt() ?? 0,
    favoriteTitles: (json['favoriteTitles'] as num?)?.toInt() ?? 0,
    totalChapters: (json['totalChapters'] as num?)?.toInt() ?? 0,
    apps: _list(json['apps']),
    sources: _list(json['sources']),
    categories: _list(json['categories']),
    statuses: _list(json['statuses']),
  );
}

/// The facet query. Facets **AND** together; values within a facet **OR** —
/// the same semantics as the library grid's filter.
@immutable
class ExportFilters {
  const ExportFilters({
    this.text = '',
    this.status = const {},
    this.categoryIds = const {},
    this.sourceIds = const {},
    this.sourceApps = const {},
    this.favorite,
    this.unreadOnly = false,
    this.startedOnly = false,
  });

  final String text;
  final Set<String> status;
  final Set<String> categoryIds;
  final Set<String> sourceIds;
  final Set<String> sourceApps;

  /// `true` favorites only, `false` non-favorites only, null both.
  final bool? favorite;
  final bool unreadOnly;
  final bool startedOnly;

  bool get isEmpty =>
      text.isEmpty &&
      status.isEmpty &&
      categoryIds.isEmpty &&
      sourceIds.isEmpty &&
      sourceApps.isEmpty &&
      favorite == null &&
      !unreadOnly &&
      !startedOnly;

  /// How many facets are narrowing the scope — drives the "3 filters" readout.
  int get activeCount =>
      (text.isEmpty ? 0 : 1) +
      (status.isEmpty ? 0 : 1) +
      (categoryIds.isEmpty ? 0 : 1) +
      (sourceIds.isEmpty ? 0 : 1) +
      (sourceApps.isEmpty ? 0 : 1) +
      (favorite == null ? 0 : 1) +
      (unreadOnly ? 1 : 0) +
      (startedOnly ? 1 : 0);

  ExportFilters copyWith({
    String? text,
    Set<String>? status,
    Set<String>? categoryIds,
    Set<String>? sourceIds,
    Set<String>? sourceApps,
    bool? favorite,
    bool clearFavorite = false,
    bool? unreadOnly,
    bool? startedOnly,
  }) => ExportFilters(
    text: text ?? this.text,
    status: status ?? this.status,
    categoryIds: categoryIds ?? this.categoryIds,
    sourceIds: sourceIds ?? this.sourceIds,
    sourceApps: sourceApps ?? this.sourceApps,
    favorite: clearFavorite ? null : (favorite ?? this.favorite),
    unreadOnly: unreadOnly ?? this.unreadOnly,
    startedOnly: startedOnly ?? this.startedOnly,
  );

  Map<String, dynamic> toJson() => {
    if (text.isNotEmpty) 'text': text,
    'status': _sorted(status),
    'categoryIds': _sorted(categoryIds),
    'sourceIds': _sorted(sourceIds),
    'sourceApps': _sorted(sourceApps),
    if (favorite != null) 'favorite': favorite,
    'unreadOnly': unreadOnly,
    'startedOnly': startedOnly,
  };

  factory ExportFilters.fromJson(Object? json) {
    if (json is! Map) return const ExportFilters();
    return ExportFilters(
      text: json['text'] is String ? (json['text'] as String).trim() : '',
      status: _stringSet(json['status']),
      categoryIds: _stringSet(json['categoryIds']),
      sourceIds: _stringSet(json['sourceIds']),
      sourceApps: _stringSet(json['sourceApps']),
      favorite: json['favorite'] is bool ? json['favorite'] as bool : null,
      unreadOnly: json['unreadOnly'] as bool? ?? false,
      startedOnly: json['startedOnly'] as bool? ?? false,
    );
  }
}

/// What travels with each exported title. All on by default: an archive export
/// is lossless unless the user deliberately narrows it.
@immutable
class ExportIncludes {
  const ExportIncludes({
    this.chapters = true,
    this.readProgress = true,
    this.categories = true,
    this.tracking = true,
  });

  final bool chapters;

  /// Read flags, page position and history. Meaningless without [chapters];
  /// the server forces it off in that case, and so does the UI.
  final bool readProgress;
  final bool categories;
  final bool tracking;

  bool get isLossless => chapters && readProgress && categories && tracking;

  ExportIncludes copyWith({
    bool? chapters,
    bool? readProgress,
    bool? categories,
    bool? tracking,
  }) => ExportIncludes(
    chapters: chapters ?? this.chapters,
    readProgress: readProgress ?? this.readProgress,
    categories: categories ?? this.categories,
    tracking: tracking ?? this.tracking,
  );

  Map<String, dynamic> toJson() => {
    'chapters': chapters,
    'readProgress': chapters && readProgress,
    'categories': categories,
    'tracking': tracking,
  };

  factory ExportIncludes.fromJson(Object? json) {
    if (json is! Map) return const ExportIncludes();
    final chapters = json['chapters'] as bool? ?? true;
    return ExportIncludes(
      chapters: chapters,
      readProgress: chapters && (json['readProgress'] as bool? ?? true),
      categories: json['categories'] as bool? ?? true,
      tracking: json['tracking'] as bool? ?? true,
    );
  }
}

/// A complete export request.
@immutable
class ExportScope {
  const ExportScope({
    this.mode = ExportMode.all,
    this.filters = const ExportFilters(),
    this.ids = const [],
    this.includes = const ExportIncludes(),
    this.targetApp = '',
  });

  final ExportMode mode;
  final ExportFilters filters;
  final List<String> ids;
  final ExportIncludes includes;

  /// App id the file is named for; empty means the generic `mangavault` prefix.
  final String targetApp;

  ExportScope copyWith({
    ExportMode? mode,
    ExportFilters? filters,
    List<String>? ids,
    ExportIncludes? includes,
    String? targetApp,
  }) => ExportScope(
    mode: mode ?? this.mode,
    filters: filters ?? this.filters,
    ids: ids ?? this.ids,
    includes: includes ?? this.includes,
    targetApp: targetApp ?? this.targetApp,
  );

  Map<String, dynamic> toJson() => {
    'mode': mode.wire,
    'filter': filters.toJson(),
    'ids': ids,
    'include': includes.toJson(),
    'targetApp': targetApp,
  };

  factory ExportScope.fromJson(Object? json) {
    if (json is! Map) return const ExportScope();
    final mode = ExportMode.fromWire(json['mode']);
    return ExportScope(
      mode: mode,
      filters: ExportFilters.fromJson(json['filter']),
      ids: mode == ExportMode.ids ? _sorted(_stringSet(json['ids'])) : const [],
      includes: ExportIncludes.fromJson(json['include']),
      targetApp: json['targetApp'] is String ? json['targetApp'] as String : '',
    );
  }
}

/// A title in the preview list.
@immutable
class ExportPreviewItem {
  const ExportPreviewItem({
    required this.id,
    required this.title,
    required this.sourceName,
    required this.chapterCount,
    required this.readCount,
    required this.favorite,
  });

  final String id;
  final String title;
  final String sourceName;
  final int chapterCount;
  final int readCount;
  final bool favorite;

  factory ExportPreviewItem.fromJson(Map<String, dynamic> json) =>
      ExportPreviewItem(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        sourceName: json['sourceName'] as String? ?? '',
        chapterCount: (json['chapterCount'] as num?)?.toInt() ?? 0,
        readCount: (json['readCount'] as num?)?.toInt() ?? 0,
        favorite: json['favorite'] as bool? ?? false,
      );
}

/// What a scope would produce, without producing it.
@immutable
class ExportPreview {
  const ExportPreview({
    required this.titles,
    required this.chapters,
    required this.readChapters,
    required this.categories,
    required this.sources,
    required this.trackedTitles,
    required this.fileName,
    required this.estimatedBytes,
    required this.sample,
  });

  final int titles;
  final int chapters;
  final int readChapters;
  final int categories;
  final int sources;
  final int trackedTitles;
  final String fileName;
  final int estimatedBytes;
  final List<ExportPreviewItem> sample;

  bool get isEmpty => titles == 0;

  factory ExportPreview.fromJson(Map<String, dynamic> json) => ExportPreview(
    titles: (json['titles'] as num?)?.toInt() ?? 0,
    chapters: (json['chapters'] as num?)?.toInt() ?? 0,
    readChapters: (json['readChapters'] as num?)?.toInt() ?? 0,
    categories: (json['categories'] as num?)?.toInt() ?? 0,
    sources: (json['sources'] as num?)?.toInt() ?? 0,
    trackedTitles: (json['trackedTitles'] as num?)?.toInt() ?? 0,
    fileName: json['fileName'] as String? ?? '',
    estimatedBytes: (json['estimatedBytes'] as num?)?.toInt() ?? 0,
    sample: (json['sample'] as List<dynamic>? ?? const [])
        .map((e) => ExportPreviewItem.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// A built backup, in memory, on its way to the device's file system.
@immutable
class ExportedBackup {
  const ExportedBackup({
    required this.fileName,
    required this.bytes,
    required this.titles,
  });

  final String fileName;
  final Uint8List bytes;
  final int titles;

  int get sizeBytes => bytes.lengthInBytes;
}

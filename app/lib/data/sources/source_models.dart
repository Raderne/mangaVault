import 'package:flutter/material.dart';

import '../../theme/app_accents.dart';

/// Whether any extension repository still publishes a source.
///
/// `unknown` is a real answer, not a missing one: a fork's private source, or
/// one that predates every repository we sync. It must never be shown as
/// "removed" — the user would migrate away from a source that works fine.
enum SourceRegistryState { listed, delisted, unknown }

/// Result of the last reachability check on a source.
enum SourceHealth { ok, degraded, blocked, unreachable, removed, unknown }

/// How a source's health reads on screen.
///
/// Every verdict carries an **icon and a word as well as a colour**, because
/// colour alone is not an indicator anyone can rely on. The accent choice
/// follows the vault's rules: rose is reserved for things that are actually
/// broken, amber for things that need attention, emerald for fine.
extension SourceHealthDisplay on SourceHealth {
  String get label => switch (this) {
        SourceHealth.ok => 'Working',
        SourceHealth.degraded => 'Degraded',
        SourceHealth.blocked => 'Blocked',
        SourceHealth.unreachable => 'Unreachable',
        SourceHealth.removed => 'Removed',
        SourceHealth.unknown => 'Not checked',
      };

  IconData get icon => switch (this) {
        SourceHealth.ok => Icons.check_circle_outline,
        SourceHealth.degraded => Icons.error_outline,
        SourceHealth.blocked => Icons.lock_outline,
        SourceHealth.unreachable => Icons.cloud_off_outlined,
        SourceHealth.removed => Icons.link_off,
        SourceHealth.unknown => Icons.help_outline,
      };

  VaultAccent? get accent => switch (this) {
        SourceHealth.ok => VaultAccent.emerald,
        SourceHealth.degraded => VaultAccent.amber,
        SourceHealth.blocked => VaultAccent.amber,
        SourceHealth.unreachable => VaultAccent.rose,
        SourceHealth.removed => VaultAccent.rose,
        SourceHealth.unknown => null,
      };

  /// True for the verdicts that make migrating worth offering.
  bool get needsAttention => switch (this) {
        SourceHealth.ok || SourceHealth.unknown => false,
        _ => true,
      };
}

SourceHealth _healthFrom(String? raw) => switch (raw) {
      'ok' => SourceHealth.ok,
      'degraded' => SourceHealth.degraded,
      'blocked' => SourceHealth.blocked,
      'unreachable' => SourceHealth.unreachable,
      'removed' => SourceHealth.removed,
      _ => SourceHealth.unknown,
    };

SourceRegistryState _stateFrom(String? raw) => switch (raw) {
      'listed' => SourceRegistryState.listed,
      'delisted' => SourceRegistryState.delisted,
      _ => SourceRegistryState.unknown,
    };

/// A listed source that may be the current identity of an unlisted one.
class SourceSuggestion {
  const SourceSuggestion({
    required this.sourceId,
    required this.name,
    required this.lang,
    required this.similarity,
    required this.titleCount,
    this.homeUrl,
    this.iconUrl,
  });

  final String sourceId;
  final String name;
  final String lang;

  /// Name similarity in [0, 1].
  final double similarity;

  /// Titles the vault already holds on the suggested source.
  final int titleCount;
  final String? homeUrl;
  final String? iconUrl;

  factory SourceSuggestion.fromJson(Map<String, dynamic> j) => SourceSuggestion(
        sourceId: (j['sourceId'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        lang: (j['lang'] as String?) ?? '',
        similarity: ((j['similarity'] as num?) ?? 0).toDouble(),
        titleCount: (j['titleCount'] as num?)?.toInt() ?? 0,
        homeUrl: j['homeUrl'] as String?,
        iconUrl: j['iconUrl'] as String?,
      );
}

/// A source the vault holds titles from, as the registry knows it.
class VaultSource {
  const VaultSource({
    required this.sourceId,
    required this.name,
    required this.lang,
    required this.titleCount,
    this.homeUrl,
    this.iconUrl,
    this.packageName,
    this.repoName,
    this.contentWarning,
    this.registryState = SourceRegistryState.unknown,
    this.health = SourceHealth.unknown,
    this.healthNote,
    this.healthCheckedAt,
    this.coverFailedCount = 0,
    this.suggestedReplacements = const [],
  });

  /// Mihon 64-bit source id as a decimal string — matches `manga.sourceId`.
  final String sourceId;
  final String name;
  final String lang;
  final String? homeUrl;
  final String? iconUrl;
  final String? packageName;
  final String? repoName;
  final String? contentWarning;
  final SourceRegistryState registryState;
  final SourceHealth health;

  /// Short reason shown under the verdict, e.g. "domain no longer resolves".
  final String? healthNote;
  final int? healthCheckedAt;

  /// Titles in the vault on this source — why the source matters at all.
  final int titleCount;
  final int coverFailedCount;

  /// Sources that look like this one under a new identity. Only ever populated
  /// for a source no repository lists — see `SourceDto.suggestedReplacements`.
  final List<SourceSuggestion> suggestedReplacements;

  bool get isNsfw => contentWarning == 'nsfw';

  factory VaultSource.fromJson(Map<String, dynamic> j) => VaultSource(
        sourceId: (j['sourceId'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        lang: (j['lang'] as String?) ?? '',
        homeUrl: j['homeUrl'] as String?,
        iconUrl: j['iconUrl'] as String?,
        packageName: j['packageName'] as String?,
        repoName: j['repoName'] as String?,
        contentWarning: j['contentWarning'] as String?,
        registryState: _stateFrom(j['registryState'] as String?),
        health: _healthFrom(j['health'] as String?),
        healthNote: j['healthNote'] as String?,
        healthCheckedAt: (j['healthCheckedAt'] as num?)?.toInt(),
        titleCount: (j['titleCount'] as num?)?.toInt() ?? 0,
        coverFailedCount: (j['coverFailedCount'] as num?)?.toInt() ?? 0,
        suggestedReplacements:
            ((j['suggestedReplacements'] as List?) ?? const [])
                .map((e) => SourceSuggestion.fromJson(e as Map<String, dynamic>))
                .toList(),
      );
}

/// Progress of a health-check run — polled exactly like a cover archive job.
class SourceHealthJob {
  const SourceHealthJob({
    required this.jobId,
    required this.status,
    required this.total,
    required this.done,
    required this.ok,
    required this.degraded,
    required this.unhealthy,
    required this.finished,
    this.cancelRequested = false,
    this.error,
  });

  final String jobId;
  final String status;
  final int total;
  final int done;
  final int ok;
  final int degraded;
  final int unhealthy;
  final bool finished;
  final bool cancelRequested;
  final String? error;

  double get fraction => total == 0 ? 0 : (done / total).clamp(0, 1).toDouble();

  factory SourceHealthJob.fromJson(Map<String, dynamic> j) => SourceHealthJob(
        jobId: (j['jobId'] as String?) ?? '',
        status: (j['status'] as String?) ?? 'running',
        total: (j['total'] as num?)?.toInt() ?? 0,
        done: (j['done'] as num?)?.toInt() ?? 0,
        ok: (j['ok'] as num?)?.toInt() ?? 0,
        degraded: (j['degraded'] as num?)?.toInt() ?? 0,
        unhealthy: (j['unhealthy'] as num?)?.toInt() ?? 0,
        finished: (j['finished'] as bool?) ?? false,
        cancelRequested: (j['cancelRequested'] as bool?) ?? false,
        error: j['error'] as String?,
      );
}

/// One entry of the extensions browser.
class ExtensionEntry {
  const ExtensionEntry({
    required this.packageName,
    required this.name,
    required this.versionName,
    required this.extensionLib,
    required this.contentWarning,
    required this.apkUrl,
    required this.iconUrl,
    required this.repoName,
    required this.sourceCount,
    required this.titleCount,
  });

  final String packageName;
  final String name;
  final String versionName;
  final String extensionLib;
  final String contentWarning;
  final String apkUrl;
  final String iconUrl;
  final String repoName;
  final int sourceCount;

  /// Titles in the vault from this extension's sources — "you use this one".
  final int titleCount;

  bool get isNsfw => contentWarning == 'nsfw';

  factory ExtensionEntry.fromJson(Map<String, dynamic> j) => ExtensionEntry(
        packageName: (j['packageName'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        versionName: (j['versionName'] as String?) ?? '',
        extensionLib: (j['extensionLib'] as String?) ?? '',
        contentWarning: (j['contentWarning'] as String?) ?? 'safe',
        apkUrl: (j['apkUrl'] as String?) ?? '',
        iconUrl: (j['iconUrl'] as String?) ?? '',
        repoName: (j['repoName'] as String?) ?? '',
        sourceCount: (j['sourceCount'] as num?)?.toInt() ?? 0,
        titleCount: (j['titleCount'] as num?)?.toInt() ?? 0,
      );
}

class ExtensionPage {
  const ExtensionPage({
    required this.items,
    required this.total,
    required this.offset,
    required this.limit,
  });

  final List<ExtensionEntry> items;
  final int total;
  final int offset;
  final int limit;

  bool get hasMore => offset + items.length < total;

  factory ExtensionPage.fromJson(Map<String, dynamic> j) => ExtensionPage(
        items: ((j['items'] as List?) ?? const [])
            .map((e) => ExtensionEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: (j['total'] as num?)?.toInt() ?? 0,
        offset: (j['offset'] as num?)?.toInt() ?? 0,
        limit: (j['limit'] as num?)?.toInt() ?? 0,
      );
}

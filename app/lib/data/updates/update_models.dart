import 'dart:convert';

import '../../theme/app_accents.dart';

/// A semantic version, parsed from a git tag, a GitHub release name, or
/// `package_info_plus`.
///
/// Build metadata (`+4`) is **kept but never compared** — that is semver's own
/// rule, and it happens to be what we want: our `pubspec.yaml` build number is
/// Android's `versionCode`, an install-ordering integer that says nothing about
/// which release is newer to a human.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(
    this.major,
    this.minor,
    this.patch, {
    this.preRelease = const [],
    this.build = '',
  });

  final int major;
  final int minor;
  final int patch;

  /// Dot-separated identifiers after `-`, e.g. `beta.1` → `['beta', '1']`.
  /// A version that has any is *older* than the same version without.
  final List<String> preRelease;

  /// Everything after `+`. Display only.
  final String build;

  static final _pattern = RegExp(
    r'^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+([0-9A-Za-z.-]+))?$',
  );

  /// Parses `1.2.3`, `v1.2.3`, `1.2.3-beta.1`, `1.2.3+7`. Returns null for
  /// anything else — a release tagged `nightly` is not a version we can rank,
  /// and guessing would offer the user a downgrade.
  static AppVersion? tryParse(String input) {
    final match = _pattern.firstMatch(input.trim());
    if (match == null) return null;
    final pre = match.group(4);
    return AppVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      preRelease: pre == null || pre.isEmpty ? const [] : pre.split('.'),
      build: match.group(5) ?? '',
    );
  }

  bool get isPreRelease => preRelease.isNotEmpty;

  @override
  int compareTo(AppVersion other) {
    final core = [
      major.compareTo(other.major),
      minor.compareTo(other.minor),
      patch.compareTo(other.patch),
    ].firstWhere((c) => c != 0, orElse: () => 0);
    if (core != 0) return core;

    // Semver §11.3: a pre-release ranks below the release it precedes.
    if (preRelease.isEmpty && other.preRelease.isEmpty) return 0;
    if (preRelease.isEmpty) return 1;
    if (other.preRelease.isEmpty) return -1;

    for (var i = 0; i < preRelease.length && i < other.preRelease.length; i++) {
      final a = preRelease[i];
      final b = other.preRelease[i];
      if (a == b) continue;
      final na = int.tryParse(a);
      final nb = int.tryParse(b);
      // Numeric identifiers compare numerically and always rank below
      // alphanumeric ones.
      if (na != null && nb != null) return na.compareTo(nb);
      if (na != null) return -1;
      if (nb != null) return 1;
      return a.compareTo(b);
    }
    // A longer identifier list wins when every shared field is equal.
    return preRelease.length.compareTo(other.preRelease.length);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;
  bool operator <(AppVersion other) => compareTo(other) < 0;
  bool operator >=(AppVersion other) => compareTo(other) >= 0;
  bool operator <=(AppVersion other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0 && build == other.build;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease.join('.'));

  /// `1.2.3` / `1.2.3-beta.1`. Build metadata is omitted — see [build].
  String get name {
    final core = '$major.$minor.$patch';
    return preRelease.isEmpty ? core : '$core-${preRelease.join('.')}';
  }

  @override
  String toString() => build.isEmpty ? name : '$name+$build';
}

/// A category of change in a release, mirroring Keep a Changelog's headings.
///
/// Each kind owns an accent so a long changelog is scannable by colour before
/// it is readable by word — green reads as "new", cyan as "fixed", rose as
/// "something you had is gone". The mapping is fixed here rather than at the
/// call site so every changelog in the app agrees.
enum ChangeKind {
  added('Added', VaultAccent.emerald),
  fixed('Fixed', VaultAccent.cyan),
  changed('Changed', VaultAccent.violet),
  deprecated('Deprecated', VaultAccent.amber),
  security('Security', VaultAccent.amber),
  removed('Removed', VaultAccent.rose),

  /// A heading we don't recognise. Rendered without a hue rather than dropped —
  /// losing a line of someone's release notes is worse than an unstyled one.
  other('Notes', VaultAccent.violet);

  const ChangeKind(this.label, this.accent);

  final String label;
  final VaultAccent accent;

  /// Matches a markdown heading to a kind. Tolerates trailing punctuation and
  /// the plural/past-tense spellings people actually write.
  static ChangeKind fromHeading(String heading) {
    final word = heading.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    return switch (word) {
      'added' || 'add' || 'adds' || 'new' || 'features' || 'feature' =>
        ChangeKind.added,
      'fixed' || 'fix' || 'fixes' || 'bugfixes' || 'bugfix' => ChangeKind.fixed,
      'changed' || 'change' || 'changes' || 'improved' || 'improvements' =>
        ChangeKind.changed,
      'deprecated' => ChangeKind.deprecated,
      'security' => ChangeKind.security,
      'removed' || 'remove' || 'breaking' || 'breakingchanges' =>
        ChangeKind.removed,
      _ => ChangeKind.other,
    };
  }
}

/// One `### <heading>` block of a changelog and its bullets.
class ChangeGroup {
  const ChangeGroup({required this.kind, required this.items, this.heading});

  final ChangeKind kind;
  final List<String> items;

  /// The literal heading text, kept so a [ChangeKind.other] group can still
  /// show what it was called.
  final String? heading;

  String get label => kind == ChangeKind.other && heading != null
      ? heading!.toUpperCase()
      : kind.label.toUpperCase();
}

/// A release body split into a lead paragraph and its grouped bullets.
class ReleaseNotes {
  const ReleaseNotes({required this.summary, required this.groups});

  static const empty = ReleaseNotes(summary: '', groups: []);

  /// Prose before the first heading. Often the one-line "why" of a release.
  final String summary;

  final List<ChangeGroup> groups;

  bool get isEmpty => summary.isEmpty && groups.isEmpty;

  /// Total bullets across every group — drives the "12 changes" count.
  int get changeCount =>
      groups.fold(0, (sum, group) => sum + group.items.length);
}

/// A published release of the app, as the updater sees it.
class AppRelease {
  const AppRelease({
    required this.version,
    required this.tag,
    required this.title,
    required this.publishedAt,
    required this.notes,
    required this.htmlUrl,
    this.apkUrl,
    this.apkBytes = 0,
    this.isPreRelease = false,
  });

  final AppVersion version;
  final String tag;

  /// The release's own name; falls back to the tag when GitHub has none.
  final String title;
  final DateTime? publishedAt;
  final ReleaseNotes notes;

  /// The release page, for the "view on GitHub" escape hatch.
  final String htmlUrl;

  /// Direct download for the `.apk` asset. Null when a release carries none —
  /// the update is then announced but not installable in-app.
  final String? apkUrl;
  final int apkBytes;
  final bool isPreRelease;

  bool get isInstallable => apkUrl != null;

  /// GitHub's release JSON. Draft/prerelease filtering is the caller's job.
  static AppRelease? fromJson(Map<String, dynamic> json) {
    final tag = (json['tag_name'] as String?)?.trim() ?? '';
    final name = (json['name'] as String?)?.trim() ?? '';
    // Prefer the tag; fall back to the release name so a release tagged
    // `release-1.2.0` but named `1.2.0` still resolves.
    final version = AppVersion.tryParse(tag) ?? AppVersion.tryParse(name);
    if (version == null) return null;

    final assets = (json['assets'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .where((a) => (a['name'] as String? ?? '').toLowerCase().endsWith('.apk'))
        .toList();
    final apk = assets.isEmpty ? null : assets.first;

    final published = json['published_at'] as String?;
    return AppRelease(
      version: version,
      tag: tag.isEmpty ? version.name : tag,
      title: name.isEmpty ? (tag.isEmpty ? version.name : tag) : name,
      publishedAt: published == null ? null : DateTime.tryParse(published),
      notes: parseReleaseNotes(json['body'] as String? ?? ''),
      htmlUrl: json['html_url'] as String? ?? '',
      apkUrl: apk?['browser_download_url'] as String?,
      apkBytes: (apk?['size'] as num?)?.toInt() ?? 0,
      isPreRelease: json['prerelease'] as bool? ?? false,
    );
  }
}

/// Strips the inline markdown that survives into release bullets.
///
/// The app renders release notes as themed Flutter text, not as HTML, so a
/// full markdown engine would be a dependency spent on emphasis we don't
/// style anyway. Bold/italic/code markers are removed and links collapse to
/// their label; the words — which are the point — are untouched.
String stripInlineMarkdown(String input) {
  var text = input;
  text = text.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]*\)'),
    (m) => m.group(1)!,
  );
  text = text.replaceAll(RegExp(r'`+'), '');
  text = text.replaceAll(RegExp(r'(\*\*|__)'), '');
  text = text.replaceAllMapped(
    RegExp(r'(?<![\w*])\*([^*\n]+)\*(?![\w*])'),
    (m) => m.group(1)!,
  );
  return text.trim();
}

final _headingPattern = RegExp(r'^#{1,6}\s+(.*)$');
final _bulletPattern = RegExp(r'^\s*[-*+]\s+(.*)$');
// GitHub's auto-generated footer. Useful on the web, noise in a phone card.
final _footerPattern = RegExp(
  r'^\*\*Full Changelog\*\*|^\s*\*\*?Full Changelog',
  caseSensitive: false,
);
// Markdown link-reference definitions (`[1.0.0]: https://…`). Keep a Changelog
// collects them at the foot of the file, and a release body pasted from one
// carries them along — they are link plumbing, never a change.
final _linkRefPattern = RegExp(r'^\s*\[[^\]]+\]:\s*\S+');

/// Parses a Keep a Changelog-shaped release body into [ReleaseNotes].
///
/// Deliberately forgiving: a release written as one flat bullet list, or with
/// headings we don't know, still renders — it just lands in a single
/// [ChangeKind.other] group instead of a colour-coded one.
ReleaseNotes parseReleaseNotes(String body) {
  if (body.trim().isEmpty) return ReleaseNotes.empty;

  final summary = <String>[];
  final groups = <ChangeGroup>[];
  String? heading;
  var kind = ChangeKind.other;
  var items = <String>[];

  void flush() {
    if (items.isEmpty) return;
    groups.add(ChangeGroup(kind: kind, items: items, heading: heading));
    items = <String>[];
  }

  // Whether the previous line was blank. This is what tells a *wrapped* bullet
  // apart from a new paragraph: CHANGELOG.md wraps at 100 columns, so most
  // bullets span several source lines, and treating each as its own entry
  // would shred every long item into fragments.
  var afterBlank = true;
  var inBullet = false;

  for (final raw in const LineSplitter().convert(body)) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) {
      afterBlank = true;
      continue;
    }
    if (_footerPattern.hasMatch(line.trim())) break;
    if (_linkRefPattern.hasMatch(line)) {
      // Not a continuation of whatever preceded it, either.
      inBullet = false;
      continue;
    }

    final headingMatch = _headingPattern.firstMatch(line.trim());
    if (headingMatch != null) {
      flush();
      heading = stripInlineMarkdown(headingMatch.group(1)!);
      kind = ChangeKind.fromHeading(heading);
      afterBlank = false;
      inBullet = false;
      continue;
    }

    final bulletMatch = _bulletPattern.firstMatch(line);
    if (bulletMatch != null) {
      final text = stripInlineMarkdown(bulletMatch.group(1)!);
      if (text.isNotEmpty) items.add(text);
      afterBlank = false;
      inBullet = true;
      continue;
    }

    final text = stripInlineMarkdown(line);
    final wasAfterBlank = afterBlank;
    afterBlank = false;
    if (text.isEmpty) continue;

    // A continuation line: same bullet, wrapped. Markdown's lazy continuation
    // allows it unindented, so the blank-line gap — not indentation — is the
    // signal. A paragraph *after* a blank line starts something new.
    if (inBullet && !wasAfterBlank && items.isNotEmpty) {
      items[items.length - 1] = '${items.last} $text';
      continue;
    }

    // Prose. Before any heading it is the lead paragraph; after one it is a
    // note attached to that section, folded in as an entry so it isn't
    // silently dropped.
    if (heading == null) {
      summary.add(text);
    } else {
      items.add(text);
      inBullet = true;
    }
  }
  flush();

  return ReleaseNotes(summary: summary.join(' '), groups: groups);
}

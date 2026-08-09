import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/data/updates/update_models.dart';

void main() {
  group('AppVersion.tryParse', () {
    test('accepts the shapes our tags and pubspec produce', () {
      expect(AppVersion.tryParse('1.2.3')!.name, '1.2.3');
      expect(AppVersion.tryParse('v1.2.3')!.name, '1.2.3');
      expect(AppVersion.tryParse('  v10.0.4 ')!.name, '10.0.4');

      final withBuild = AppVersion.tryParse('1.0.0+7')!;
      expect(withBuild.build, '7');
      expect(withBuild.name, '1.0.0', reason: 'build metadata is not the name');

      final pre = AppVersion.tryParse('2.0.0-beta.1')!;
      expect(pre.preRelease, ['beta', '1']);
      expect(pre.isPreRelease, isTrue);
    });

    test('rejects anything it cannot rank', () {
      for (final input in ['nightly', '1.2', 'v1', '', 'latest', '1.2.3.4']) {
        expect(AppVersion.tryParse(input), isNull, reason: input);
      }
    });
  });

  group('AppVersion ordering', () {
    test('compares core fields numerically, not lexically', () {
      expect(AppVersion.tryParse('1.10.0')! > AppVersion.tryParse('1.9.0')!,
          isTrue);
      expect(AppVersion.tryParse('2.0.0')! > AppVersion.tryParse('1.99.99')!,
          isTrue);
      expect(AppVersion.tryParse('1.0.1')! > AppVersion.tryParse('1.0.0')!,
          isTrue);
    });

    test('build metadata never affects ordering', () {
      final a = AppVersion.tryParse('1.0.0+1')!;
      final b = AppVersion.tryParse('1.0.0+99')!;
      expect(a.compareTo(b), 0);
      expect(a > b, isFalse);
      expect(b > a, isFalse);
    });

    test('a pre-release ranks below its release', () {
      expect(
        AppVersion.tryParse('1.0.0-beta.1')! < AppVersion.tryParse('1.0.0')!,
        isTrue,
      );
      expect(
        AppVersion.tryParse('1.0.0-alpha')! <
            AppVersion.tryParse('1.0.0-beta')!,
        isTrue,
      );
      expect(
        AppVersion.tryParse('1.0.0-beta.2')! >
            AppVersion.tryParse('1.0.0-beta.1')!,
        isTrue,
      );
      // Numeric identifiers rank below alphanumeric ones (semver §11.4.3).
      expect(
        AppVersion.tryParse('1.0.0-1')! < AppVersion.tryParse('1.0.0-alpha')!,
        isTrue,
      );
    });

    test('the unknown-install fallback is older than every real release', () {
      const unknown = AppVersion(0, 0, 0);
      expect(unknown < AppVersion.tryParse('0.0.1')!, isTrue);
    });
  });

  group('stripInlineMarkdown', () {
    test('removes emphasis and code fences, keeps the words', () {
      expect(stripInlineMarkdown('Import `.tachibk` files'),
          'Import .tachibk files');
      expect(stripInlineMarkdown('**Bold** and *italic*'), 'Bold and italic');
      expect(stripInlineMarkdown('__also bold__'), 'also bold');
    });

    test('collapses links to their label', () {
      expect(
        stripInlineMarkdown('See [the docs](https://example.com/x) for more'),
        'See the docs for more',
      );
    });

    test('leaves an unpaired asterisk alone', () {
      expect(stripInlineMarkdown('sorted 2 * 3 deep'), 'sorted 2 * 3 deep');
    });
  });

  group('parseReleaseNotes', () {
    test('splits a lead paragraph from colour-coded groups', () {
      final notes = parseReleaseNotes('''
This release is about imports.

### Added

- A thing
- Another thing

### Fixed

- A bug
''');

      expect(notes.summary, 'This release is about imports.');
      expect(notes.groups.length, 2);
      expect(notes.groups.first.kind, ChangeKind.added);
      expect(notes.groups.first.items, ['A thing', 'Another thing']);
      expect(notes.groups.last.kind, ChangeKind.fixed);
      expect(notes.changeCount, 3);
    });

    test('joins a wrapped bullet back into one item', () {
      // CHANGELOG.md wraps at 100 columns, so this is the common case, not
      // an edge case.
      final notes = parseReleaseNotes('''
### Added

- Import backups from Mihon and its forks, with a staged review
  step before anything is committed to the vault.
- A short one.
''');

      expect(notes.groups.single.items, [
        'Import backups from Mihon and its forks, with a staged review step '
            'before anything is committed to the vault.',
        'A short one.',
      ]);
    });

    test('a blank line ends a bullet rather than continuing it', () {
      final notes = parseReleaseNotes('''
### Changed

- First item

A separate note.
''');
      expect(notes.groups.single.items, ['First item', 'A separate note.']);
    });

    test('maps every Keep a Changelog heading to its accent', () {
      final notes = parseReleaseNotes('''
### Added
- a
### Fixed
- b
### Changed
- c
### Deprecated
- d
### Security
- e
### Removed
- f
''');
      expect(
        notes.groups.map((g) => g.kind).toList(),
        [
          ChangeKind.added,
          ChangeKind.fixed,
          ChangeKind.changed,
          ChangeKind.deprecated,
          ChangeKind.security,
          ChangeKind.removed,
        ],
      );
    });

    test('an unknown heading survives as `other`, keeping its own label', () {
      final notes = parseReleaseNotes('### Housekeeping\n- tidied up\n');
      expect(notes.groups.single.kind, ChangeKind.other);
      expect(notes.groups.single.label, 'HOUSEKEEPING');
      expect(notes.groups.single.items, ['tidied up']);
    });

    test('a flat bullet list with no headings still renders', () {
      final notes = parseReleaseNotes('- one\n- two\n');
      expect(notes.groups.single.kind, ChangeKind.other);
      expect(notes.groups.single.items, ['one', 'two']);
    });

    test('drops markdown link-reference definitions', () {
      final notes = parseReleaseNotes('''
### Added
- a thing

[Unreleased]: https://github.com/o/r/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/o/r/releases/tag/v1.0.0
''');
      expect(notes.groups.single.items, ['a thing']);
    });

    test("drops GitHub's Full Changelog footer", () {
      final notes = parseReleaseNotes('''
### Added
- a thing

**Full Changelog**: https://github.com/o/r/compare/v1.0.0...v1.1.0
''');
      expect(notes.groups.single.items, ['a thing']);
      expect(notes.changeCount, 1);
    });

    test('an empty body is empty, not a phantom group', () {
      expect(parseReleaseNotes('').isEmpty, isTrue);
      expect(parseReleaseNotes('   \n\n  ').isEmpty, isTrue);
    });
  });

  group('AppRelease.fromJson', () {
    Map<String, dynamic> release({
      String tag = 'v1.1.0',
      String name = 'Manga Vault 1.1.0',
      List<Map<String, dynamic>>? assets,
      bool prerelease = false,
    }) =>
        {
          'tag_name': tag,
          'name': name,
          'body': '### Added\n- something\n',
          'published_at': '2026-08-01T10:00:00Z',
          'html_url': 'https://github.com/o/r/releases/tag/$tag',
          'prerelease': prerelease,
          'assets': assets ??
              [
                {
                  'name': 'manga-vault-1.1.0.apk',
                  'size': 24000000,
                  'browser_download_url': 'https://example.com/app.apk',
                },
              ],
        };

    test('reads the version, notes and APK asset', () {
      final parsed = AppRelease.fromJson(release())!;
      expect(parsed.version.name, '1.1.0');
      expect(parsed.apkUrl, 'https://example.com/app.apk');
      expect(parsed.apkBytes, 24000000);
      expect(parsed.isInstallable, isTrue);
      expect(parsed.notes.groups.single.kind, ChangeKind.added);
      expect(parsed.publishedAt, DateTime.utc(2026, 8, 1, 10));
    });

    test('falls back to the release name when the tag is unparseable', () {
      final parsed = AppRelease.fromJson(
        release(tag: 'release-candidate', name: '1.4.0'),
      )!;
      expect(parsed.version.name, '1.4.0');
    });

    test('is null when neither tag nor name is a version', () {
      expect(AppRelease.fromJson(release(tag: 'nightly', name: 'Nightly')),
          isNull);
    });

    test('ignores non-APK assets and reports the release uninstallable', () {
      final parsed = AppRelease.fromJson(
        release(assets: [
          {
            'name': 'sources.zip',
            'size': 100,
            'browser_download_url': 'https://example.com/sources.zip',
          },
        ]),
      )!;
      expect(parsed.apkUrl, isNull);
      expect(parsed.isInstallable, isFalse);
    });
  });

  group('CHANGELOG.md contract', () {
    // The release workflow slices this file into the GitHub release body, and
    // the app parses that body back. If the two ever disagree the app ships
    // with a blank or mangled changelog, so pin the round trip here.
    test('the repo changelog parses into recognised groups', () {
      final file = File('../CHANGELOG.md');
      expect(file.existsSync(), isTrue, reason: 'CHANGELOG.md is missing');

      final text = file.readAsStringSync();
      final start = text.indexOf('## [1.0.0]');
      expect(start, greaterThan(-1), reason: 'no 1.0.0 section');
      final nextHeading = text.indexOf('\n## ', start + 1);
      final section = text.substring(
        text.indexOf('\n', start) + 1,
        nextHeading == -1 ? text.length : nextHeading,
      );

      final notes = parseReleaseNotes(section);
      expect(notes.summary, isNotEmpty);
      expect(notes.groups, isNotEmpty);
      expect(
        notes.groups.every((g) => g.kind != ChangeKind.other),
        isTrue,
        reason: 'every heading must map to a known ChangeKind',
      );
      // Every bullet should be a whole sentence — a stray fragment means the
      // wrapped-line join regressed.
      for (final group in notes.groups) {
        for (final item in group.items) {
          expect(item.endsWith('.'), isTrue, reason: 'fragment: "$item"');
        }
      }
    });
  });
}

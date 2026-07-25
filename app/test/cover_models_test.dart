import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/data/covers/cover_models.dart';

void main() {
  test('CoverArchiveStarted.fromJson', () {
    final s = CoverArchiveStarted.fromJson({
      'jobId': 'job-1',
      'total': 12,
      'alreadyRunning': true,
    });
    expect(s.jobId, 'job-1');
    expect(s.total, 12);
    expect(s.alreadyRunning, isTrue);
  });

  test('CoverJobStatus.fromJson computes a progress fraction', () {
    final s = CoverJobStatus.fromJson({
      'jobId': 'job-1',
      'total': 10,
      'done': 4,
      'archived': 3,
      'failed': 1,
      'skipped': 0,
      'finished': false,
    });
    expect(s.done, 4);
    expect(s.archived, 3);
    expect(s.failed, 1);
    expect(s.finished, isFalse);
    expect(s.fraction, closeTo(0.4, 1e-9));
  });

  test('CoverJobStatus fraction is 1 when there is nothing to do', () {
    final s = CoverJobStatus.fromJson({
      'jobId': 'job-1',
      'total': 0,
      'done': 0,
      'archived': 0,
      'failed': 0,
      'skipped': 0,
      'finished': true,
    });
    expect(s.fraction, 1.0);
  });

  test('CoverResult.fromJson exposes an archived flag', () {
    expect(
      CoverResult.fromJson({
        'mangaId': 'm1',
        'outcome': 'archived',
        'coverState': 'archived',
      }).archived,
      isTrue,
    );
    final failed = CoverResult.fromJson({
      'mangaId': 'm2',
      'outcome': 'failed',
      'coverState': 'failed',
      'error': 'HTTP 403',
    });
    expect(failed.archived, isFalse);
    expect(failed.error, 'HTTP 403');
  });
}

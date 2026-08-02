import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/data/backup_apps/backup_app_models.dart';
import 'package:mangavault/data/covers/cover_models.dart';
import 'package:mangavault/data/covers/cover_repository.dart';
import 'package:mangavault/data/library/library_models.dart';
import 'package:mangavault/data/library/library_repository.dart';
import 'package:mangavault/features/covers/cover_archive_controller.dart';

/// Fake cover repo returning scripted job statuses, one per poll.
class FakeCoverRepository extends CoverRepository {
  FakeCoverRepository({
    required this.started,
    required this.statuses,
    this.active,
  }) : super(Dio());

  final CoverArchiveStarted started;
  final List<CoverJobStatus> statuses;

  /// What `GET /covers/jobs/active` reports — a run this client didn't start.
  final CoverJobStatus? active;
  int polls = 0;
  int cancels = 0;

  @override
  Future<CoverArchiveStarted> archiveMissing() async => started;

  @override
  Future<CoverJobStatus> jobStatus(String jobId) async {
    final i = polls < statuses.length ? polls : statuses.length - 1;
    polls++;
    return statuses[i];
  }

  @override
  Future<CoverJobStatus?> activeJob() async => active;

  @override
  Future<CoverJobStatus> cancelJob(String jobId) async {
    cancels++;
    return statuses.isEmpty ? _status(total: 0, done: 0, archived: 0) : statuses.last;
  }
}

/// Minimal library repo so the controller's in-place reload has something to do.
class FakeLibraryRepository extends LibraryRepository {
  FakeLibraryRepository();

  // Not exercised here — this test only drives the in-place reload.
  @override
  Future<VaultManga> get(String id) => throw UnimplementedError();

  @override
  Future<LibraryPage> query({
    String text = '',
    List<String> status = const [],
    List<String> categoryIds = const [],
    List<String> sourceIds = const [],
    List<String> sourceApps = const [],
    bool? favorite,
    String sortBy = 'title',
    String sortDir = 'asc',
    int offset = 0,
    int limit = 40,
  }) async =>
      const LibraryPage(items: [], total: 0, offset: 0, limit: 40);

  @override
  Future<List<Category>> categories() async => const [];

  @override
  Future<List<SourceOption>> sources() async => const [];

  @override
  Future<List<SourceAppOption>> sourceApps() async => const [];

  @override
  Future<Map<String, String>> backupAppNames() async => const {};

  @override
  Future<void> forgetTitles(List<String> ids) async {}
}

CoverJobStatus _status({
  required int total,
  required int done,
  required int archived,
  bool finished = false,
  String status = 'running',
  String trigger = 'manual',
  bool cancelRequested = false,
}) =>
    CoverJobStatus(
      jobId: 'job-1',
      status: finished && status == 'running' ? 'finished' : status,
      trigger: trigger,
      total: total,
      done: done,
      archived: archived,
      failed: 0,
      skipped: 0,
      finished: finished,
      cancelRequested: cancelRequested,
      error: null,
    );

ProviderContainer _container(FakeCoverRepository cover) {
  final container = ProviderContainer(overrides: [
    coverRepositoryProvider.overrideWithValue(cover),
    libraryRepositoryProvider.overrideWithValue(FakeLibraryRepository()),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('finishes immediately when nothing is missing', () async {
    final repo = FakeCoverRepository(
      started: const CoverArchiveStarted(
          jobId: 'job-1', total: 0, alreadyRunning: false),
      statuses: const [],
    );
    final container = _container(repo);

    await container.read(coverArchiveControllerProvider.notifier).start();
    final state = container.read(coverArchiveControllerProvider);

    expect(state.isDone, isTrue);
    expect(state.total, 0);
    expect(repo.polls, 0); // no polling needed
  });

  test('polls to completion and reports archived counts', () async {
    final repo = FakeCoverRepository(
      started: const CoverArchiveStarted(
          jobId: 'job-1', total: 3, alreadyRunning: false),
      statuses: [
        _status(total: 3, done: 3, archived: 3, finished: true),
      ],
    );
    final container = _container(repo);

    await container.read(coverArchiveControllerProvider.notifier).start();
    // Controller is running while the first (1s) poll is pending.
    expect(container.read(coverArchiveControllerProvider).isRunning, isTrue);

    // Wait past one poll interval for the job to report finished.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final state = container.read(coverArchiveControllerProvider);

    expect(state.isDone, isTrue);
    expect(state.archived, 3);
    expect(state.done, 3);
  });

  test('adopts a run the server already had in flight', () async {
    // The server started this one itself (an import, or a resume after a
    // restart) — the app has to show it without anyone tapping anything.
    final repo = FakeCoverRepository(
      started: const CoverArchiveStarted(
          jobId: 'job-1', total: 0, alreadyRunning: false),
      active: _status(total: 8, done: 2, archived: 2, trigger: 'import'),
      statuses: [
        _status(
            total: 8, done: 8, archived: 8, trigger: 'import', finished: true),
      ],
    );
    final container = _container(repo);

    await container.read(coverArchiveControllerProvider.notifier).adopt();
    var state = container.read(coverArchiveControllerProvider);
    expect(state.isRunning, isTrue);
    expect(state.total, 8);
    expect(state.done, 2);
    expect(state.startedByServer, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 1200));
    state = container.read(coverArchiveControllerProvider);
    expect(state.isDone, isTrue);
    expect(state.archived, 8);
  });

  test('adopt is silent when no run is in flight', () async {
    final repo = FakeCoverRepository(
      started: const CoverArchiveStarted(
          jobId: 'job-1', total: 0, alreadyRunning: false),
      statuses: const [],
    );
    final container = _container(repo);

    await container.read(coverArchiveControllerProvider.notifier).adopt();

    expect(
      container.read(coverArchiveControllerProvider).phase,
      CoverArchivePhase.idle,
    );
    expect(repo.polls, 0);
  });

  test('cancel marks the banner stopping, then reports the run cancelled',
      () async {
    final repo = FakeCoverRepository(
      started: const CoverArchiveStarted(
          jobId: 'job-1', total: 5, alreadyRunning: false),
      statuses: [
        _status(
          total: 5,
          done: 2,
          archived: 2,
          status: 'cancelled',
          cancelRequested: true,
          finished: true,
        ),
      ],
    );
    final container = _container(repo);
    final controller =
        container.read(coverArchiveControllerProvider.notifier);

    await controller.start();
    await controller.cancel();
    expect(repo.cancels, 1);
    // Downloads in flight are still draining, so the banner says so.
    expect(container.read(coverArchiveControllerProvider).cancelling, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final state = container.read(coverArchiveControllerProvider);
    expect(state.isDone, isTrue);
    expect(state.cancelled, isTrue);
    expect(state.cancelling, isFalse);
    expect(state.archived, 2);
  });

  test('dismiss returns a finished banner to idle', () async {
    final repo = FakeCoverRepository(
      started: const CoverArchiveStarted(
          jobId: 'job-1', total: 0, alreadyRunning: false),
      statuses: const [],
    );
    final container = _container(repo);
    final controller =
        container.read(coverArchiveControllerProvider.notifier);

    await controller.start();
    expect(container.read(coverArchiveControllerProvider).isDone, isTrue);
    controller.dismiss();
    expect(
      container.read(coverArchiveControllerProvider).phase,
      CoverArchivePhase.idle,
    );
  });
}

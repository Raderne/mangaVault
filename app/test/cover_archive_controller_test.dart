import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/data/covers/cover_models.dart';
import 'package:mangavault/data/covers/cover_repository.dart';
import 'package:mangavault/data/library/library_models.dart';
import 'package:mangavault/data/library/library_repository.dart';
import 'package:mangavault/features/covers/cover_archive_controller.dart';

/// Fake cover repo returning scripted job statuses, one per poll.
class FakeCoverRepository extends CoverRepository {
  FakeCoverRepository({required this.started, required this.statuses})
      : super(Dio());

  final CoverArchiveStarted started;
  final List<CoverJobStatus> statuses;
  int polls = 0;

  @override
  Future<CoverArchiveStarted> archiveMissing() async => started;

  @override
  Future<CoverJobStatus> jobStatus(String jobId) async {
    final i = polls < statuses.length ? polls : statuses.length - 1;
    polls++;
    return statuses[i];
  }
}

/// Minimal library repo so the controller's in-place reload has something to do.
class FakeLibraryRepository extends LibraryRepository {
  FakeLibraryRepository() : super(Dio());

  @override
  Future<LibraryPage> query({
    String text = '',
    List<String> status = const [],
    List<String> categoryIds = const [],
    List<String> sourceIds = const [],
    bool? favorite,
    String sortBy = 'title',
    String sortDir = 'asc',
    int offset = 0,
    int limit = 40,
  }) async =>
      const LibraryPage(items: [], total: 0, offset: 0, limit: 40);

  @override
  Future<List<Category>> categories() async => const [];
}

CoverJobStatus _status({
  required int total,
  required int done,
  required int archived,
  required bool finished,
}) =>
    CoverJobStatus(
      jobId: 'job-1',
      total: total,
      done: done,
      archived: archived,
      failed: 0,
      skipped: 0,
      finished: finished,
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

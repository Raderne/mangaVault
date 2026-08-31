import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/data/sources/source_models.dart';
import 'package:mangavault/data/sources/source_repository.dart';
import 'package:mangavault/features/sources/source_health_controller.dart';

SourceHealthJob _job({
  required int total,
  required int done,
  int ok = 0,
  int degraded = 0,
  int unhealthy = 0,
  bool finished = false,
  String status = 'running',
  bool cancelRequested = false,
}) =>
    SourceHealthJob(
      jobId: 'job-1',
      status: status,
      total: total,
      done: done,
      ok: ok,
      degraded: degraded,
      unhealthy: unhealthy,
      finished: finished,
      cancelRequested: cancelRequested,
    );

/// Fake source repo returning scripted job statuses, one per poll.
class FakeSourceRepository extends SourceRepository {
  FakeSourceRepository({
    required this.started,
    this.statuses = const [],
    this.active,
  }) : super(Dio());

  final SourceHealthJob started;
  final List<SourceHealthJob> statuses;

  /// What `GET /sources/health-jobs/active` reports.
  final SourceHealthJob? active;
  int polls = 0;
  int cancels = 0;

  @override
  Future<SourceHealthJob> checkHealth() async => started;

  @override
  Future<SourceHealthJob> healthJob(String jobId) async {
    final i = polls < statuses.length ? polls : statuses.length - 1;
    polls++;
    return statuses[i];
  }

  @override
  Future<SourceHealthJob?> activeHealthJob() async => active;

  @override
  Future<SourceHealthJob> cancelHealthJob(String jobId) async {
    cancels++;
    return statuses.isEmpty ? started : statuses.last;
  }
}

ProviderContainer _containerFor(SourceRepository repo) {
  final container = ProviderContainer(
    overrides: [sourceRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

/// Poll until [test] holds or the budget runs out, so the test never depends on
/// the controller's exact one-second cadence.
Future<void> _until(
  ProviderContainer container,
  bool Function(SourceHealthState) test,
) async {
  for (var i = 0; i < 40; i++) {
    if (test(container.read(sourceHealthControllerProvider))) return;
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  fail('condition never held: '
      '${container.read(sourceHealthControllerProvider).phase}');
}

void main() {
  test('a run with nothing to check finishes without polling', () async {
    final repo = FakeSourceRepository(
      started: _job(total: 0, done: 0, finished: true),
    );
    final container = _containerFor(repo);

    await container.read(sourceHealthControllerProvider.notifier).start();

    final state = container.read(sourceHealthControllerProvider);
    expect(state.phase, SourceHealthPhase.done);
    expect(repo.polls, 0);
  });

  test('polls to completion and folds the verdict counts', () async {
    final repo = FakeSourceRepository(
      started: _job(total: 3, done: 0),
      statuses: [
        _job(total: 3, done: 1, ok: 1),
        _job(total: 3, done: 2, ok: 1, degraded: 1),
        _job(
          total: 3,
          done: 3,
          ok: 1,
          degraded: 1,
          unhealthy: 1,
          finished: true,
          status: 'finished',
        ),
      ],
    );
    final container = _containerFor(repo);

    await container.read(sourceHealthControllerProvider.notifier).start();
    await _until(container, (s) => s.isDone);

    final state = container.read(sourceHealthControllerProvider);
    expect(state.done, 3);
    expect(state.ok, 1);
    expect(state.degraded, 1);
    expect(state.unhealthy, 1);
    expect(state.fraction, 1.0);
  });

  test('adopts a run this client never started', () async {
    final repo = FakeSourceRepository(
      started: _job(total: 0, done: 0, finished: true),
      active: _job(total: 5, done: 2, ok: 2),
      statuses: [
        _job(total: 5, done: 5, ok: 5, finished: true, status: 'finished'),
      ],
    );
    final container = _containerFor(repo);

    await container.read(sourceHealthControllerProvider.notifier).adopt();

    // Progress from the server's run shows immediately, before any poll.
    expect(container.read(sourceHealthControllerProvider).isRunning, isTrue);
    expect(container.read(sourceHealthControllerProvider).done, 2);

    await _until(container, (s) => s.isDone);
    expect(container.read(sourceHealthControllerProvider).ok, 5);
  });

  test('adopting nothing leaves the screen idle', () async {
    final repo = FakeSourceRepository(
      started: _job(total: 0, done: 0, finished: true),
    );
    final container = _containerFor(repo);

    await container.read(sourceHealthControllerProvider.notifier).adopt();

    expect(
      container.read(sourceHealthControllerProvider).phase,
      SourceHealthPhase.idle,
    );
  });

  test('a cancelled run reports as cancelled, not failed', () async {
    final repo = FakeSourceRepository(
      started: _job(total: 4, done: 0),
      statuses: [
        _job(total: 4, done: 1, cancelRequested: true),
        _job(
          total: 4,
          done: 2,
          ok: 2,
          finished: true,
          status: 'cancelled',
          cancelRequested: true,
        ),
      ],
    );
    final container = _containerFor(repo);

    await container.read(sourceHealthControllerProvider.notifier).start();
    await container.read(sourceHealthControllerProvider.notifier).cancel();
    await _until(container, (s) => s.isDone);

    final state = container.read(sourceHealthControllerProvider);
    expect(repo.cancels, 1);
    expect(state.cancelled, isTrue);
    expect(state.cancelling, isFalse);
    expect(state.phase, SourceHealthPhase.done);
  });

  test('dismiss clears a finished run but never a live one', () async {
    final repo = FakeSourceRepository(
      started: _job(total: 0, done: 0, finished: true),
    );
    final container = _containerFor(repo);
    final controller =
        container.read(sourceHealthControllerProvider.notifier);

    await controller.start();
    expect(container.read(sourceHealthControllerProvider).isDone, isTrue);

    controller.dismiss();
    expect(
      container.read(sourceHealthControllerProvider).phase,
      SourceHealthPhase.idle,
    );
  });
}

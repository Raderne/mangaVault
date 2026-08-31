import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangavault/data/sources/migration_models.dart';
import 'package:mangavault/data/sources/source_repository.dart';
import 'package:mangavault/features/sources/migration_plan_controller.dart';

MigrationItem _item({
  required String id,
  required String title,
  MigrationItemState state = MigrationItemState.matched,
  double? score,
  String? method,
}) =>
    MigrationItem(
      id: 'item-$id',
      mangaId: id,
      title: title,
      state: state,
      toSourceId: state == MigrationItemState.matched ? '999' : null,
      toSourceName: state == MigrationItemState.matched ? 'MangaDex' : null,
      toMangaUrl: state == MigrationItemState.matched ? '/manga/$id' : null,
      toTitle: state == MigrationItemState.matched ? title : null,
      score: score,
      method: method,
    );

MigrationPlan _plan({
  required List<MigrationItem> items,
  String status = 'ready',
  double autoAccept = 0.85,
}) =>
    MigrationPlan(
      job: MigrationJob(
        jobId: 'job-1',
        status: status,
        fromSourceId: '111',
        fromSourceName: 'KaliScan.io',
        total: items.length,
        planned: items.length,
        matched: items.where((i) => i.hasMatch).length,
        applied: 0,
        skipped: 0,
        failed: 0,
        finished: status != 'planning',
      ),
      items: items,
      autoAcceptScore: autoAccept,
    );

class FakeSourceRepository extends SourceRepository {
  FakeSourceRepository(this.plans) : super(Dio());

  /// One plan per `plan()` call; the last one repeats.
  final List<MigrationPlan> plans;
  int reads = 0;
  List<String>? appliedIds;

  @override
  Future<MigrationPlan> plan(String jobId) async {
    final i = reads < plans.length ? reads : plans.length - 1;
    reads++;
    return plans[i];
  }

  @override
  Future<MigrationApplyResult> apply({
    required String jobId,
    required List<String> mangaIds,
  }) async {
    appliedIds = mangaIds;
    return MigrationApplyResult(
      applied: mangaIds.length,
      conflicts: 0,
      failed: 0,
    );
  }

  @override
  Future<MigrationItem> skipItem({
    required String jobId,
    required String mangaId,
  }) async =>
      _item(id: mangaId, title: 'x', state: MigrationItemState.skipped);
}

ProviderContainer _containerFor(SourceRepository repo) {
  final container = ProviderContainer(
    overrides: [sourceRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('pre-ticks only matches at or above the auto-accept bar', () async {
    final repo = FakeSourceRepository([
      _plan(
        items: [
          _item(id: 'a', title: 'Confident', score: 0.98),
          _item(id: 'b', title: 'Exactly at the bar', score: 0.85),
          _item(id: 'c', title: 'Plausible but unsure', score: 0.69),
          _item(
            id: 'd',
            title: 'Nothing found',
            state: MigrationItemState.unmatched,
          ),
        ],
      ),
    ]);
    final container = _containerFor(repo);

    await container
        .read(migrationPlanControllerProvider.notifier)
        .open('job-1');

    // The 0.69 is the whole reason the review screen exists: it is offered,
    // but never ticked on the user's behalf.
    expect(
      container.read(migrationPlanControllerProvider).selected,
      {'a', 'b'},
    );
  });

  test('a hand-entered address counts as confident', () async {
    final repo = FakeSourceRepository([
      _plan(
        items: [
          _item(id: 'a', title: 'By hand', score: null, method: 'manual'),
          _item(id: 'b', title: 'Weak guess', score: 0.5),
        ],
      ),
    ]);
    final container = _containerFor(repo);

    await container
        .read(migrationPlanControllerProvider.notifier)
        .open('job-1');

    expect(container.read(migrationPlanControllerProvider).selected, {'a'});
  });

  test('apply sends exactly what is ticked, not every match', () async {
    final repo = FakeSourceRepository([
      _plan(
        items: [
          _item(id: 'a', title: 'One', score: 0.99),
          _item(id: 'b', title: 'Two', score: 0.90),
          _item(id: 'c', title: 'Three', score: 0.60),
        ],
      ),
    ]);
    final container = _containerFor(repo);
    final controller =
        container.read(migrationPlanControllerProvider.notifier);

    await controller.open('job-1');
    // Untick a confident one, tick the uncertain one — the user's call.
    controller.toggle('b');
    controller.toggle('c');

    await controller.apply();

    expect(repo.appliedIds, isNotNull);
    expect(repo.appliedIds!.toSet(), {'a', 'c'});
    expect(container.read(migrationPlanControllerProvider).result?.applied, 2);
  });

  test('apply does nothing when nothing is ticked', () async {
    final repo = FakeSourceRepository([
      _plan(
        items: [_item(id: 'a', title: 'Unsure', score: 0.5)],
      ),
    ]);
    final container = _containerFor(repo);
    final controller =
        container.read(migrationPlanControllerProvider.notifier);

    await controller.open('job-1');
    expect(container.read(migrationPlanControllerProvider).selected, isEmpty);

    await controller.apply();
    expect(repo.appliedIds, isNull);
  });

  test('select all takes every match, including uncertain ones', () async {
    final repo = FakeSourceRepository([
      _plan(
        items: [
          _item(id: 'a', title: 'One', score: 0.99),
          _item(id: 'b', title: 'Two', score: 0.5),
          _item(
            id: 'c',
            title: 'Nothing found',
            state: MigrationItemState.unmatched,
          ),
        ],
      ),
    ]);
    final container = _containerFor(repo);
    final controller =
        container.read(migrationPlanControllerProvider.notifier);

    await controller.open('job-1');
    controller.selectAllMatched();

    // An unmatched title has nowhere to go, so it is never selectable.
    expect(container.read(migrationPlanControllerProvider).selected, {'a', 'b'});

    controller.selectNone();
    expect(container.read(migrationPlanControllerProvider).selected, isEmpty);
  });

  test('skipping a title unticks it', () async {
    final repo = FakeSourceRepository([
      _plan(items: [_item(id: 'a', title: 'One', score: 0.99)]),
      _plan(
        items: [
          _item(
            id: 'a',
            title: 'One',
            state: MigrationItemState.skipped,
          ),
        ],
      ),
    ]);
    final container = _containerFor(repo);
    final controller =
        container.read(migrationPlanControllerProvider.notifier);

    await controller.open('job-1');
    expect(container.read(migrationPlanControllerProvider).selected, {'a'});

    await controller.skip('a');
    expect(container.read(migrationPlanControllerProvider).selected, isEmpty);
  });

  test('re-opening the plan already loaded does not reload it', () async {
    final repo = FakeSourceRepository([
      _plan(items: [_item(id: 'a', title: 'One', score: 0.99)]),
    ]);
    final container = _containerFor(repo);
    final controller =
        container.read(migrationPlanControllerProvider.notifier);

    await controller.open('job-1');
    final reads = repo.reads;
    await controller.open('job-1');

    expect(repo.reads, reads);
  });
}

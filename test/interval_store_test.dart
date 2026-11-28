import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/cardio.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/interval_store.dart';
import 'package:timburr/data/intervals.dart';
import 'package:timburr/data/recorder.dart';
import 'package:timburr/data/track.dart';

final t0 = DateTime.utc(2026, 11, 27, 7);
DateTime at(num sec) => t0.add(Duration(milliseconds: (sec * 1000).round()));
PositionSample fix(int sec, double meters) => PositionSample(time: at(sec), lat: 32.0 + meters / 111195, lon: 34.8, accuracy: 5);

void feed(Recorder r, int from, int to, {double speed = 3, double startM = 0}) {
  for (var s = from; s <= to; s++) {
    r.position(fix(s, startM + (s - from) * speed));
    r.tick(at(s));
  }
}

final twoBy300 = IntervalPlan.basic(name: '2 × 300', reps: 2, rep: StepTarget.meters(300), recovery: StepTarget.time(30));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDb db;
  late CardioStore store;
  setUp(() {
    db = AppDb(NativeDatabase.memory());
    store = CardioStore(db);
  });
  tearDown(() => db.close());

  /// Records a planned Interval run starting [day] days after t0 and saves it through ingest. [speed] m/s.
  Future<String> intervalRun(String? planId, {int day = 0, double speed = 3, IntervalPlan? plan}) async {
    final start = t0.add(Duration(days: day));
    final r = Recorder.start('interval', start, 's$day$planId', plan: planId == null ? null : plan ?? twoBy300, planId: planId);
    for (var s = 0; s <= 280; s++) {
      r.position(PositionSample(time: start.add(Duration(seconds: s)), lat: 32.0 + s * speed / 111195, lon: 34.8, accuracy: 5));
      r.tick(start.add(Duration(seconds: s)));
      if (planId == null && (s == 60 || s == 160)) r.next(start.add(Duration(seconds: s)));
    }
    return (await store.ingest(r.finish(start.add(const Duration(seconds: 280))))).id!;
  }

  group('Interval plans', () {
    test('are added, listed by name, edited and deleted', () async {
      final b = await store.intervals.add(twoBy300);
      final a = await store.intervals.add(twoBy300.named('A ladder'));
      expect([for (final p in await store.intervals.watchPlans().first) p.plan.name], ['2 × 300', 'A ladder']);
      await store.intervals.update(b, twoBy300.named('2 × 300 fast'));
      expect((await store.intervals.watchPlans().first).first.plan.name, '2 × 300 fast');
      await store.intervals.delete(a);
      expect([for (final p in await store.intervals.watchPlans().first) p.id], [b]);
    });

    test('an Interval run keeps the plan it was run to and a copy of it, even after the plan is edited or deleted', () async {
      final p = await store.intervals.add(twoBy300);
      final id = await intervalRun(p);
      await store.intervals.update(p, twoBy300.named('Renamed'));
      await store.intervals.delete(p);
      final run = await store.watch(id).first;
      expect((run.type, run.intervalPlanId), ('interval', p));
      expect(planOf(run), twoBy300);
      expect((await store.watchTrack(id).first)!.steps, hasLength(5));
    });

    test('the plan last run is picked next time; Free after a free Interval run, or with no plan run yet', () async {
      expect(await store.intervals.lastUsed(), isNull);
      final a = await store.intervals.add(twoBy300), b = await store.intervals.add(twoBy300.named('B'));
      await intervalRun(a, day: 1);
      await intervalRun(b, day: 2);
      expect(await store.intervals.lastUsed(), b);
      await intervalRun(null, day: 3);
      expect(await store.intervals.lastUsed(), isNull);
      await intervalRun(a, day: 4);
      await store.intervals.delete(a);
      expect(await store.intervals.lastUsed(), isNull); // a deleted plan is not offered
    });
  });

  group('Plan history', () {
    test('lists the plan\'s Interval runs newest first, with their reps summed up', () async {
      final p = await store.intervals.add(twoBy300);
      final older = await intervalRun(p, day: 1, speed: 3);
      final newer = await intervalRun(p, day: 2, speed: 4);
      await intervalRun(null, day: 3); // free: not in the plan's history
      final h = await store.intervals.watchHistory(p).first;
      expect([for (final e in h) e.run.id], [newer, older]);
      expect(h.last.summary!.avgPaceSecPerKm, closeTo(1000 / 3, 1));
      expect(h.first.summary!.avgPaceSecPerKm, closeTo(1000 / 4, 1));
    });

    test('Last time is each Step\'s pace in the newest Run of the plan', () async {
      final p = await store.intervals.add(twoBy300);
      await intervalRun(p, day: 1, speed: 3);
      await intervalRun(p, day: 2, speed: 4);
      final last = await store.intervals.lastTimesOf(p);
      expect(last.keys, unorderedEquals(['rep', 'recovery']));
      expect(last['rep']!.paceSecPerKm, closeTo(1000 / 4, 1));
      expect(await store.intervals.lastTimesOf('none'), isEmpty);
    });

    test('Save as plan makes a plan of a free Interval run, and the Run joins its history', () async {
      final id = await intervalRun(null);
      final p = await store.intervals.saveAsPlan(id, 'Free one');
      final plan = (await store.intervals.watchPlans().first).single.plan;
      expect((plan.name, plan.describe()), ('Free one', '1:00 warm-up · 1 × (300 m / 1:00) · 2:00 cool-down'));
      expect((await store.watch(id).first).intervalPlanId, p);
      expect([for (final e in await store.intervals.watchHistory(p).first) e.run.id], [id]);
    });
  });

  group('No more treadmill Runs', () {
    test('old treadmill Runs and their tracks are soft-deleted, once; other Runs stay', () async {
      await db.save(db.cardio, {'id': 'tm', 'type': 'treadmill', 'started_at': t0, 'distance_km': 5.0, 'duration_sec': 1800});
      await db.save(db.cardioTracks, {'id': trackRowId('tm'), 'cardio_id': 'tm', 'points': Track(time: [0, 10], hr: [120, 130]).encode()});
      await store.save(type: 'run', startedAt: t0.add(const Duration(days: 1)), distanceKm: 5, durationSec: 1500);
      expect(await store.dropTreadmillRuns(), 1);
      expect(await store.dropTreadmillRuns(), 0);
      expect([for (final c in await store.watchAll().first) c.type], ['run']);
      final tm = await store.watch('tm').first;
      expect((tm.deletedAt != null, tm.dirty), (true, 1)); // syncs as deleted
      expect(await store.watchTrack('tm').first, isNull);
    });
  });
}

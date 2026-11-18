import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/catalog.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/routines.dart';
import 'package:timburr/data/workouts.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDb db;
  late WorkoutStore store;
  var synced = 0;
  setUp(() {
    db = AppDb(NativeDatabase.memory());
    synced = 0;
    store = WorkoutStore(db, onFinished: () async => synced++);
  });
  tearDown(() => db.close());

  CatalogEntry lib(String id) => CatalogEntry(name: id, libraryId: id, loadType: 'weighted');
  Future<List<String>> order(String w) async => [for (final e in await store.watchExercises(w).first) e.exerciseId];

  test('start from a routine copies its exercises in order', () async {
    final routines = RoutineStore(db);
    final r = await routines.create('Push');
    for (final id in ['A', 'B', 'C']) {
      await routines.add(r, lib(id));
    }
    final items = await routines.watchExercises(r).first;
    await routines.remove(items[1].id);

    final w = await store.start(routineId: r);
    expect(await order(w), [libraryRowId('A'), libraryRowId('C')]);
    expect((await store.watchWorkout(w).first).routineId, r);
  });

  test('add, reorder and remove exercises keep positions contiguous', () async {
    final w = await store.start();
    for (final id in ['A', 'B', 'C']) {
      await store.addExercise(w, lib(id));
    }
    var items = await store.watchExercises(w).first;
    await store.move(items[2].id, -1);
    expect(await order(w), [for (final id in ['A', 'C', 'B']) libraryRowId(id)]);
    await store.move(items[0].id, -1); // already first: no-op
    await store.remove(items[0].id);
    items = await store.watchExercises(w).first;
    expect([for (final e in items) e.exerciseId], [libraryRowId('C'), libraryRowId('B')]);
    expect([for (final e in items) e.position], [0, 1]);
  });

  test('a new set copies the previous set, else last time, else is empty', () async {
    final w1 = await store.start();
    await store.addExercise(w1, lib('A'));
    final we1 = (await store.watchExercises(w1).first).single;
    final first = await store.addSet(we1.id);
    expect((first.weightKg, first.reps, first.durationSec, first.setNumber), (null, null, null, 1));
    await store.updateSet(first.copyWith(weightKg: const Value(60), reps: const Value(8), done: true));
    final second = await store.addSet(we1.id);
    expect((second.weightKg, second.reps, second.done, second.setNumber), (60.0, 8, false, 2));
    await store.updateSet(second.copyWith(weightKg: const Value(70), reps: const Value(5)));
    await store.finish(w1);

    final w2 = await store.start();
    await store.addExercise(w2, lib('A'));
    final we2 = (await store.watchExercises(w2).first).single;
    final a = await store.addSet(we2.id);
    expect((a.weightKg, a.reps), (60.0, 8)); // last time's set 1
    await store.updateSet(a.copyWith(weightKg: const Value(65)));
    final b = await store.addSet(we2.id);
    expect((b.weightKg, b.reps), (65.0, 8)); // previous set in this session wins
  });

  test('removing a set renumbers the rest', () async {
    final w = await store.start();
    await store.addExercise(w, lib('A'));
    final we = (await store.watchExercises(w).first).single;
    final s1 = await store.addSet(we.id);
    await store.addSet(we.id);
    await store.removeSet(s1);
    expect([for (final s in await store.watchSets(we.id).first) s.setNumber], [1]);
  });

  test('last time is the latest other, non-discarded session', () async {
    Future<String> session(DateTime at, double kg) async {
      final w = await store.start();
      await store.setStartedAt(w, at);
      await store.addExercise(w, lib('A'));
      final we = (await store.watchExercises(w).first).single;
      final s = await store.addSet(we.id);
      await store.updateSet(s.copyWith(weightKg: Value(kg), reps: const Value(5)));
      return w;
    }

    final old = await session(DateTime(2026, 1, 1), 50);
    await store.finish(old);
    final discarded = await session(DateTime(2026, 1, 3), 99);
    await store.discard(discarded);
    final current = await session(DateTime(2026, 1, 5), 77);

    final last = await store.lastTime(libraryRowId('A'), excludeWorkoutId: current);
    expect([for (final s in last) s.weightKg], [50.0]);

    await session(DateTime(2026, 1, 9), 120); // later than current: not "previous"
    await session(DateTime(2026, 1, 2), 60);
    final prev = await store.previousSessions(libraryRowId('A'), excludeWorkoutId: current);
    expect([for (final sets in prev) sets.single.weightKg], [60.0, 50.0]);
  });

  test('finished sessions and logged sets are oldest first, finished and live only', () async {
    Future<String> session(DateTime at, double kg) async {
      final w = await store.start();
      await store.setStartedAt(w, at);
      await store.addExercise(w, lib('A'));
      final we = (await store.watchExercises(w).first).single;
      final s = await store.addSet(we.id);
      await store.updateSet(s.copyWith(weightKg: Value(kg), reps: const Value(5), done: true));
      return w;
    }

    await store.finish(await session(DateTime(2026, 1, 5), 70));
    await store.finish(await session(DateTime(2026, 1, 1), 50));
    final gone = await session(DateTime(2026, 1, 3), 99);
    await store.finish(gone);
    await store.discard(gone);
    await session(DateTime(2026, 1, 9), 120); // unfinished
    final out = await store.finishedSessions(libraryRowId('A'));
    expect([for (final (at, sets) in out) (at, sets.single.weightKg)],
        [(DateTime(2026, 1, 1), 50.0), (DateTime(2026, 1, 5), 70.0)]);
    final logged = await store.watchLogged().first;
    expect([for (final r in logged) r.set.weightKg], [50.0, 70.0]);
  });

  test('finish stamps finished_at, triggers sync, and ends the active workout', () async {
    final w = await store.start();
    expect((await store.active())?.id, w);
    await store.finish(w);
    expect((await store.watchWorkout(w).first).finishedAt, isNotNull);
    expect(synced, 1);
    expect(await store.active(), isNull);
  });

  test('discard soft-deletes and is not resumable', () async {
    final w = await store.start();
    await store.discard(w);
    expect(await store.active(), isNull);
    final row = await db.select(db.workouts).getSingle();
    expect(row.deletedAt, isNotNull);
    expect(row.dirty, 1);
  });

  test('resume finds the in-progress workout from a fresh store', () async {
    final done = await store.start();
    await store.finish(done);
    final w = await store.start();
    await store.setNotes(w, 'felt good');
    final a = await WorkoutStore(db).active();
    expect((a?.id, a?.notes), (w, 'felt good'));
  });

  test('steppers never go below 0', () {
    expect(stepped(2.5, -2.5), 0);
    expect(stepped(1, -2.5), 0);
    expect(stepped(null, -1), 0);
    expect(stepped(null, 5), 5);
    expect(stepped(60, 2.5), 62.5);
  });

  test('history lists finished, non-deleted workouts newest first', () async {
    Future<String> at(int day, {bool finish = true}) async {
      final w = await store.start();
      await store.setStartedAt(w, DateTime(2026, 1, day));
      if (finish) await store.finish(w);
      return w;
    }

    final old = await at(1), newest = await at(3), mid = await at(2);
    await at(4, finish: false); // in progress
    await store.discard(await at(5));
    expect([for (final w in await store.watchHistory().first) w.id], [newest, mid, old]);
  });

  test('discard soft-deletes the workout exercises and sets too', () async {
    final w = await store.start();
    await store.addExercise(w, lib('A'));
    final we = (await store.watchExercises(w).first).single;
    await store.addSet(we.id);
    await store.discard(w);
    expect(await (db.select(db.workoutExercises)..where((e) => e.deletedAt.isNull())).get(), isEmpty);
    expect(await (db.select(db.workoutSets)..where((s) => s.deletedAt.isNull())).get(), isEmpty);
    expect((await db.select(db.workoutSets).getSingle()).dirty, 1);
  });

  test('set patches touch only their column, stack, and mark the row dirty', () async {
    final w = await store.start();
    await store.addExercise(w, lib('A'));
    final we = (await store.watchExercises(w).first).single;
    final s = await store.addSet(we.id);
    await db.update(db.workoutSets).write(WorkoutSetsCompanion(dirty: const Value(0), updatedAt: Value(DateTime(2000))));
    // Stale row snapshot on purpose: each call must not depend on a re-read.
    await store.patchSet(s.id, weightKg: const Value(60));
    await store.patchSet(s.id, reps: const Value(8));
    await store.stepSet(s.id, SetField.weightKg, kgStep);
    await store.stepSet(s.id, SetField.weightKg, kgStep);
    await store.patchSet(s.id, done: true);
    final got = (await store.watchSets(we.id).first).single;
    expect([got.weightKg, got.reps, got.done, got.dirty], [65.0, 8, true, 1]);
    expect(got.updatedAt.isAfter(DateTime(2000)), true);
  });

  test('stepSet clamps to 0..9999', () async {
    final w = await store.start();
    await store.addExercise(w, lib('A'));
    final we = (await store.watchExercises(w).first).single;
    final s = await store.addSet(we.id);
    await store.patchSet(s.id, reps: const Value(9998), durationSec: const Value(1));
    await store.stepSet(s.id, SetField.reps, 5);
    await store.stepSet(s.id, SetField.durationSec, -5);
    final got = (await store.watchSets(we.id).first).single;
    expect([got.reps, got.durationSec], [9999, 0]);
  });

  test('edits to a finished workout mark it dirty for sync', () async {
    final w = await store.start();
    await store.finish(w);
    await db.update(db.workouts).write(const WorkoutsCompanion(dirty: Value(0)));
    await store.setNotes(w, 'later');
    expect((await store.watchWorkout(w).first).dirty, 1);
  });

  test('moving the start time of a finished workout keeps its duration', () async {
    final w = await store.start();
    await store.finish(w);
    final before = await store.watchWorkout(w).first;
    final at = before.startedAt.subtract(const Duration(hours: 2));
    await store.setStartedAt(w, at);
    final after = await store.watchWorkout(w).first;
    expect(after.startedAt, at);
    expect(after.finishedAt!.difference(after.startedAt), before.finishedAt!.difference(before.startedAt));
  });

  test('remove and move never leave a dangling superset link', () async {
    final w = await store.start();
    for (final id in ['A', 'B', 'C', 'D']) {
      await store.addExercise(w, lib(id));
    }
    Future<List<bool>> links() async => [for (final e in await store.watchExercises(w).first) e.supersetWithNext];
    for (final e in (await store.watchExercises(w).first).take(3)) {
      await store.saveExercise(e.copyWith(supersetWithNext: true)); // A-B-C-D superset
    }
    var items = await store.watchExercises(w).first;
    await store.remove(items[1].id); // B: A must not join C
    expect(await links(), [false, true, false]);
    items = await store.watchExercises(w).first;
    await store.move(items[1].id, 1); // C to last: the C+D group stays as D+C
    expect(await links(), [false, true, false]);
  });

  test('a set added to a finished workout is done', () async {
    final w = await store.start();
    await store.addExercise(w, lib('A'));
    final e = (await store.watchExercises(w).first).single;
    expect((await store.addSet(e.id)).done, false);
    await store.finish(w);
    expect((await store.addSet(e.id)).done, true);
  });

  group('from a saved workout', () {
    late RoutineStore routines;
    setUp(() => routines = RoutineStore(db));

    Future<List<(double?, int?, bool)>> sets(String w) async => [
          for (final e in await store.watchExercises(w).first)
            for (final s in await store.watchSets(e.id).first) (s.weightKg, s.reps, s.done)
        ];

    test('start prefills planned sets; missing weight falls back to last session', () async {
      final r = await routines.create('Push');
      final a = await routines.add(r, lib('A'));
      await routines.saveSets(a, [(weightKg: null, reps: 5, durationSec: null), (weightKg: 70, reps: 5, durationSec: null)]);
      final first = await store.start(routineId: r);
      expect(await sets(first), [(null, 5, false), (70.0, 5, false)]);
      final e = (await store.watchExercises(first).first).single;
      final s1 = (await store.watchSets(e.id).first).first;
      await store.updateSet(s1.copyWith(weightKg: const Value(65), done: true));
      await store.finish(first);
      final second = await store.start(routineId: r);
      expect(await sets(second), [(65.0, 5, false), (70.0, 5, false)]);
    });

    test('last session beats a planned weight, even after "Keep" (Lower B, 11 Nov)', () async {
      final r = await routines.create('Lower B');
      final a = await routines.add(r, lib('A'));
      await routines.saveSets(a, [for (final kg in [100.0, 110.0, 110.0, 115.0]) (weightKg: kg, reps: 5, durationSec: null)]);
      final w1 = await store.start(routineId: r);
      final e = (await store.watchExercises(w1).first).single;
      for (final (i, s) in (await store.watchSets(e.id).first).indexed) {
        await store.updateSet(s.copyWith(weightKg: Value([110.0, 115.0, 120.0, 120.0][i]), done: true));
      }
      await store.finish(w1); // routine not updated
      final w2 = await store.start(routineId: r);
      expect(await sets(w2), [for (final kg in [110.0, 115.0, 120.0, 120.0]) (kg, 5, false)]);
    });

    test('logDone saves a finished workout at the given time with every set done', () async {
      final r = await routines.create('Push');
      await routines.add(r, lib('A'));
      final at = DateTime(2026, 10, 20, 18);
      final w = await store.start(routineId: r, at: at, done: true);
      final row = await store.watchWorkout(w).first;
      expect(row.startedAt, at);
      expect(row.finishedAt, at.add(estimateDuration(3)));
      expect(await sets(w), everyElement(isA<(double?, int?, bool)>().having((s) => s.$3, 'done', true)));
      expect(await store.active(), isNull);
    });

    test('estimateDuration is 3 min per set, at least 10 min', () {
      expect(estimateDuration(1), const Duration(minutes: 10));
      expect(estimateDuration(12), const Duration(minutes: 36));
    });

    test('templateChanged and updateTemplate', () async {
      final r = await routines.create('Push');
      await routines.add(r, lib('A'));
      final w = await store.start(routineId: r);
      expect(await store.templateChanged(w), isFalse);
      final e = (await store.watchExercises(w).first).single;
      final s1 = (await store.watchSets(e.id).first).first;
      await store.updateSet(s1.copyWith(weightKg: const Value(50)));
      await store.addExercise(w, lib('B'));
      expect(await store.templateChanged(w), isTrue);
      await store.updateTemplate(w);
      expect(await store.templateChanged(w), isFalse);
      final plan = await routines.plan(r);
      expect([for (final p in plan) p.exerciseId], [libraryRowId('A'), libraryRowId('B')]);
      expect(plan.first.sets.first.weightKg, isNull);
      expect(plan.last.sets, isEmpty);
    });

    test('a prefilled last-session weight does not count as a change', () async {
      final r = await routines.create('Push');
      await routines.add(r, lib('A'));
      final w1 = await store.start(routineId: r);
      final e = (await store.watchExercises(w1).first).single;
      for (final s in await store.watchSets(e.id).first) {
        await store.updateSet(s.copyWith(weightKg: const Value(60), done: true));
      }
      await store.finish(w1);
      final w2 = await store.start(routineId: r);
      expect(await store.templateChanged(w2), isFalse);
    });

    test('drop sets stay out of the plan and of prefill', () async {
      final r = await routines.create('Push');
      final a = await routines.add(r, lib('A'));
      await routines.saveSets(a, [for (var i = 0; i < 3; i++) (weightKg: null, reps: 5, durationSec: null)]);
      final w1 = await store.start(routineId: r);
      final e = (await store.watchExercises(w1).first).single;
      for (final s in await store.watchSets(e.id).first) {
        await store.updateSet(s.copyWith(weightKg: const Value(100), done: true));
      }
      await store.addDrop((await store.watchSets(e.id).first).first);
      final drop = (await store.watchSets(e.id).first)[1];
      await store.updateSet(drop.copyWith(weightKg: const Value(80), reps: const Value(8), done: true));
      expect(await store.templateChanged(w1), isFalse);
      await store.updateTemplate(w1);
      expect((await routines.plan(r)).single.sets.length, 3);
      await store.finish(w1);
      final w2 = await store.start(routineId: r);
      expect(await sets(w2), [(100.0, 5, false), (100.0, 5, false), (100.0, 5, false)]);
    });

    test('updateTemplate saves no weights; weight alone is no change', () async {
      final r = await routines.create('Push');
      final a = await routines.add(r, lib('A'));
      await routines.saveSets(a, [
        (weightKg: null, reps: 5, durationSec: null),
        (weightKg: 70, reps: 5, durationSec: null),
      ]);
      final w = await store.start(routineId: r);
      final e = (await store.watchExercises(w).first).single;
      final s1 = (await store.watchSets(e.id).first).first;
      await store.updateSet(s1.copyWith(weightKg: const Value(90)));
      expect(await store.templateChanged(w), isFalse);
      await store.addSet(e.id);
      await store.updateTemplate(w);
      expect([for (final s in (await routines.plan(r)).single.sets) s.weightKg], [null, null, null]);
    });

    test('deleting a routine soft-deletes its exercises and sets', () async {
      final r = await routines.create('Push');
      await routines.add(r, lib('A'));
      await routines.delete(r);
      expect((await db.select(db.routineExercises).get()).every((e) => e.deletedAt != null), isTrue);
      expect((await db.select(db.routineSets).get()).every((s) => s.deletedAt != null), isTrue);
    });

    test('templateChanged is false for a deleted or missing template', () async {
      final r = await routines.create('Draft');
      await routines.add(r, lib('A'));
      final w = await store.start(routineId: r);
      await store.addExercise(w, lib('B'));
      await routines.delete(r);
      expect(await store.templateChanged(w), isFalse);
      expect(await store.templateChanged(await store.start()), isFalse);
    });
  });

  test('a drop set goes right after its set at about 80% weight, and renumbers the rest', () async {
    final w = await store.start();
    await store.addExercise(w, lib('A'));
    final we = (await store.watchExercises(w).first).single;
    final s1 = await store.addSet(we.id);
    await store.updateSet(s1.copyWith(weightKg: const Value(50), reps: const Value(8), done: true));
    await store.addSet(we.id);
    await store.addDrop((await store.watchSets(we.id).first).first);
    expect([for (final s in await store.watchSets(we.id).first) (s.setNumber, s.weightKg, s.reps, s.isDrop, s.done)],
        [(1, 50.0, 8, false, true), (2, 40.0, 8, true, false), (3, 50.0, 8, false, false)]);
  });

  test('alternatives come from the routine; a swap trades places and takes last weights', () async {
    final routines = RoutineStore(db);
    final r = await routines.create('Lower A');
    final re = await routines.add(r, lib('Ext down'));
    await routines.addAlternatives(re, [lib('Ext up'), lib('Ext down'), lib('Ext gym'), lib('Ext up')]);
    expect((await routines.watchExercises(r).first).single.alternativeIds, [libraryRowId('Ext up'), libraryRowId('Ext gym')]);

    // Last time on the upstairs machine: 35 kg.
    final old = await store.start();
    await store.addExercise(old, lib('Ext up'));
    final oe = (await store.watchExercises(old).first).single;
    await store.updateSet((await store.addSet(oe.id)).copyWith(weightKg: const Value(35), reps: const Value(10), done: true));
    await store.finish(old);

    final w = await store.start(routineId: r);
    var e = (await store.watchExercises(w).first).single;
    final first = (await store.watchSets(e.id).first).first;
    await store.updateSet(first.copyWith(weightKg: const Value(50), done: true));
    await store.swap(e, libraryRowId('Ext up'));
    e = (await store.watchExercises(w).first).single;
    expect(e.exerciseId, libraryRowId('Ext up'));
    expect(e.alternativeIds, [libraryRowId('Ext down'), libraryRowId('Ext gym')]);
    // A done set keeps its weight; the rest take the upstairs machine's.
    expect([for (final s in await store.watchSets(e.id).first) s.weightKg], [50.0, 35.0, 35.0]);

    await routines.removeAlternative(re, libraryRowId('Ext up'));
    expect((await routines.watchExercises(r).first).single.alternativeIds, [libraryRowId('Ext gym')]);
  });

  test('a skipped exercise counts nowhere and stays in the routine', () async {
    final routines = RoutineStore(db);
    final r = await routines.create('Lower A');
    await routines.add(r, lib('Squat'));
    await routines.add(r, lib('Hip thrust'));
    final w = await store.start(routineId: r);
    for (final e in await store.watchExercises(w).first) {
      for (final s in await store.watchSets(e.id).first) {
        await store.updateSet(s.copyWith(weightKg: const Value(60), done: true));
      }
    }
    final hips = (await store.watchExercises(w).first).last;
    await store.setSkipped(hips, true);
    await store.finish(w);

    expect({for (final l in await store.watchLogged().first) l.exerciseId}, {libraryRowId('Squat')});
    expect(await store.finishedSessions(libraryRowId('Hip thrust')), isEmpty);
    final next = await store.start();
    expect(await store.lastTime(libraryRowId('Hip thrust'), excludeWorkoutId: next), isEmpty);
    await store.updateTemplate(w);
    expect([for (final e in await routines.watchExercises(r).first) e.exerciseId], [libraryRowId('Squat'), libraryRowId('Hip thrust')]);

    await store.setSkipped((await store.watchExercises(w).first).last, false);
    expect(await store.finishedSessions(libraryRowId('Hip thrust')), hasLength(1));
  });

  test('health stats save on the workout', () async {
    final w = await store.start();
    await store.setHealth(w, (avgHr: 91, calories: 255, activeSec: 3689, effort: 5, cardioLoad: 5));
    final row = await store.watchWorkout(w).first;
    expect((row.avgHr, row.calories, row.activeSec, row.effort, row.cardioLoad, row.dirty), (91, 255, 3689, 5, 5, 1));
  });
}

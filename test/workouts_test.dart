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

  test('edits to a finished workout mark it dirty for sync', () async {
    final w = await store.start();
    await store.finish(w);
    await db.update(db.workouts).write(const WorkoutsCompanion(dirty: Value(0)));
    await store.setNotes(w, 'later');
    expect((await store.watchWorkout(w).first).dirty, 1);
  });
}

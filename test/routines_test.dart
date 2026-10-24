import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/catalog.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/routines.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDb db;
  late RoutineStore store;
  setUp(() {
    db = AppDb(NativeDatabase.memory());
    store = RoutineStore(db);
  });
  tearDown(() => db.close());

  CatalogEntry lib(String id) => CatalogEntry(name: id, libraryId: id, loadType: 'weighted', muscles: ['chest']);
  Future<List<String>> order(String r) async => [for (final i in await store.watchExercises(r).first) i.exerciseId];

  test('create, edit and list routines by name', () async {
    final b = await store.create('Push');
    await store.create('Legs');
    await store.update(b, name: 'Pull', stickyNote: 'grip');
    final list = await store.watchRoutines().first;
    expect([for (final r in list) r.name], ['Legs', 'Pull']);
    expect(list.last.stickyNote, 'grip');
  });

  test('adding a library exercise get-or-creates one row with a uuidv5 id', () async {
    final r = await store.create('Push');
    await store.add(r, lib('Pushups'));
    await store.add(r, lib('Pushups'));
    final rows = await db.select(db.exercises).get();
    expect(rows, hasLength(1));
    expect(rows.single.id, libraryRowId('Pushups'));
    expect(rows.single.libraryId, 'Pushups');
    expect([for (final i in await store.watchExercises(r).first) i.position], [0, 1]);
  });

  test('add uses an existing custom row as is', () async {
    await db.save(db.exercises, {'id': 'c1', 'name': 'Sled', 'load_type': 'weighted'});
    final r = await store.create('X');
    await store.add(r, CatalogEntry(name: 'Sled', rowId: 'c1'));
    expect(await order(r), ['c1']);
    expect(await db.select(db.exercises).get(), hasLength(1));
  });

  test('reorder and remove keep positions contiguous', () async {
    final r = await store.create('Push');
    for (final id in ['A', 'B', 'C']) {
      await store.add(r, lib(id));
    }
    final [a, b, c] = [for (final id in ['A', 'B', 'C']) libraryRowId(id)];

    var items = await store.watchExercises(r).first;
    await store.move(items[2].id, -1);
    expect(await order(r), [a, c, b]);
    items = await store.watchExercises(r).first;
    await store.move(items[0].id, -1); // already first: no-op
    expect(await order(r), [a, c, b]);

    await store.remove(items[0].id);
    items = await store.watchExercises(r).first;
    expect([for (final i in items) i.exerciseId], [c, b]);
    expect([for (final i in items) i.position], [0, 1]);
  });

  test('soft-deleting a routine hides it and its exercises but keeps rows', () async {
    final r = await store.create('Push');
    await store.add(r, lib('A'));
    await store.delete(r);
    expect(await store.watchRoutines().first, isEmpty);
    expect(await store.watchExercises(r).first, isEmpty);
    final row = await db.select(db.routines).getSingle();
    expect(row.deletedAt, isNotNull);
    expect(row.dirty, 1);
  });

  test('deleted custom exercises do not appear in the picker catalog', () async {
    await db.save(db.exercises, {'id': 'c1', 'name': 'Sled', 'load_type': 'weighted'});
    await db.save(db.exercises, {'id': 'c1', 'deleted_at': DateTime.now()});
    expect(await Catalog(db, () async => '[]').list(), isEmpty);
  });

  group('planned sets', () {
    test('a new exercise gets 3 x 10 reps; timed gets 3 x 30 s', () async {
      final r = await store.create('Push');
      final a = await store.add(r, lib('A'));
      final t = await store.add(r, CatalogEntry(name: 'Plank', libraryId: 'Plank', loadType: 'timed'));
      expect([for (final s in await store.watchSets(a).first) (s.setNumber, s.reps, s.durationSec)],
          [(1, 10, null), (2, 10, null), (3, 10, null)]);
      expect([for (final s in await store.watchSets(t).first) s.durationSec], [30, 30, 30]);
    });

    test('saveSets reuses rows by number and soft-deletes extras', () async {
      final r = await store.create('Push');
      final a = await store.add(r, lib('A'));
      final before = {for (final s in await store.watchSets(a).first) s.id};
      await store.saveSets(a, [(weightKg: 60, reps: 5, durationSec: null), (weightKg: 60, reps: 5, durationSec: null)]);
      final after = await store.watchSets(a).first;
      expect([for (final s in after) (s.weightKg, s.reps)], [(60.0, 5), (60.0, 5)]);
      expect(before.containsAll({for (final s in after) s.id}), isTrue);
      expect(await db.select(db.routineSets).get(), hasLength(3)); // third one soft-deleted
    });

    test('reorder moves to an index and renumbers', () async {
      final r = await store.create('Push');
      final ids = [for (final x in ['A', 'B', 'C']) await store.add(r, lib(x))];
      await store.reorder(ids[2], 0);
      expect(await order(r), [libraryRowId('C'), libraryRowId('A'), libraryRowId('B')]);
    });

    test('duplicate copies exercises and sets under a new name', () async {
      final r = await store.create('Push');
      final a = await store.add(r, lib('A'));
      await store.saveSets(a, [(weightKg: 40, reps: 8, durationSec: null)]);
      final copy = await store.duplicate(r);
      expect((await store.watchRoutines().first).map((x) => x.name), containsAll(['Push', 'Push copy']));
      final items = await store.watchExercises(copy).first;
      expect(items.single.exerciseId, libraryRowId('A'));
      expect([for (final s in await store.watchSets(items.single.id).first) (s.weightKg, s.reps)], [(40.0, 8)]);
    });

    test('deleting an exercise hides its sets with it', () async {
      final r = await store.create('Push');
      final a = await store.add(r, lib('A'));
      await store.remove(a);
      expect(await store.plan(r), isEmpty);
    });
  });

  test('planSummary', () {
    RoutineSet s({int? reps, int? sec, double? kg}) => RoutineSet(
        id: 'x', createdAt: DateTime(2026), updatedAt: DateTime(2026), dirty: 0,
        routineExerciseId: 'e', setNumber: 1, reps: reps, durationSec: sec, weightKg: kg);
    expect(planSummary([s(reps: 10), s(reps: 10), s(reps: 10)]), '3 sets • 10 reps');
    expect(planSummary([s(reps: 5, kg: 62.5)]), '1 set • 5 reps • 62.5 kg');
    expect(planSummary([s(sec: 30), s(sec: 30)]), '2 sets • 30 s');
    expect(planSummary([]), 'No sets');
  });
}

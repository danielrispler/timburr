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
    expect(rows.single.id, libraryExerciseId('Pushups'));
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
    final [a, b, c] = [for (final id in ['A', 'B', 'C']) libraryExerciseId(id)];

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
}

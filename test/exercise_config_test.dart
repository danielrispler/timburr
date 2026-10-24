import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/catalog.dart';
import 'package:timburr/data/db.dart';

const _library = [
  {
    'id': 'Pushups', 'name': 'Pushups', 'category': 'strength', 'equipment': 'body only',
    'primaryMuscles': ['chest'], 'secondaryMuscles': [], 'instructions': [],
  },
];

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDb db;
  late Catalog catalog;
  setUp(() {
    db = AppDb(NativeDatabase.memory());
    catalog = Catalog(db, () async => jsonEncode(_library));
  });
  tearDown(() => db.close());

  test('same library_id yields the same id in two fresh stores', () async {
    final other = AppDb(NativeDatabase.memory());
    final a = await catalog.configureLibrary('Pushups');
    final b = await Catalog(other, () async => jsonEncode(_library)).configureLibrary('Pushups');
    await other.close();
    expect(a, b);
    expect(a, libraryRowId('Pushups'));
    expect(a, isNot(libraryRowId('Squat')));
  });

  test('configuring a library exercise twice keeps one row; override wins over default', () async {
    expect((await catalog.list()).single.loadType, 'bodyweight');
    await catalog.configureLibrary('Pushups', loadType: 'timed');
    await catalog.configureLibrary('Pushups', stickyNote: 'elbows in');
    expect(await db.select(db.exercises).get(), hasLength(1));
    final e = (await catalog.list()).single;
    expect(e.loadType, 'timed');
    expect(e.stickyNote, 'elbows in');
  });

  test('renamed custom shows new name; deleted is hidden but resolvable', () async {
    final id = await catalog.saveCustom(name: 'Sled', loadType: 'weighted', muscles: ['quadriceps'], equipment: 'other');
    await catalog.saveCustom(id: id, name: 'Sled Push', loadType: 'weighted', muscles: ['quadriceps'], equipment: 'other');
    expect([for (final e in await catalog.list()) e.name], contains('Sled Push'));
    expect((await catalog.byId(id))!.name, 'Sled Push');

    await catalog.deleteCustom(id);
    expect([for (final e in await catalog.list()) e.name], ['Pushups']);
    expect((await catalog.byId(id))!.name, 'Sled Push');
  });

  test('last rest is stored per exercise, library or custom, and read back', () async {
    final lib = await catalog.configureLibrary('Pushups');
    final custom = await catalog.saveCustom(name: 'Sled', loadType: 'weighted', muscles: [], equipment: 'other');
    expect((await catalog.byId(lib))!.lastRestSec, isNull);
    await catalog.setLastRest(lib, 90);
    await catalog.setLastRest(custom, 150);
    await catalog.setLastRest(lib, 120);
    expect((await catalog.byId(lib))!.lastRestSec, 120);
    expect((await catalog.byId(custom))!.lastRestSec, 150);
    expect({for (final e in await catalog.list()) e.name: e.lastRestSec}, {'Pushups': 120, 'Sled': 150});
  });

  test('picking a library exercise creates its row once and never re-dirties it', () async {
    final entry = (await catalog.list()).single;
    final id = await catalog.rowIdFor(entry);
    expect(id, libraryRowId('Pushups'));
    await catalog.configureLibrary('Pushups', stickyNote: 'elbows in');
    await db.customStatement('UPDATE exercises SET dirty = 0');
    expect(await catalog.rowIdFor((await catalog.list()).single), id);
    final row = (await db.select(db.exercises).get()).single;
    expect(row.dirty, 0);
    expect(row.stickyNote, 'elbows in');
  });

  test('save updates only the given columns of an existing row', () async {
    await catalog.configureLibrary('Pushups', loadType: 'timed', stickyNote: 'a');
    await db.save(db.exercises, {'id': libraryRowId('Pushups'), 'last_rest_sec': 60});
    final row = (await db.select(db.exercises).get()).single;
    expect((row.loadType, row.stickyNote, row.lastRestSec), ('timed', 'a', 60));
  });
}

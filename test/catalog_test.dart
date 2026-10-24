import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/catalog.dart';
import 'package:timburr/data/db.dart';

const _library = [
  {
    'id': 'Barbell_Squat', 'name': 'Barbell Squat', 'category': 'strength', 'equipment': 'barbell',
    'primaryMuscles': ['quadriceps'], 'secondaryMuscles': ['glutes'], 'instructions': ['Squat down.'],
  },
  {
    'id': 'Pushups', 'name': 'Pushups', 'category': 'strength', 'equipment': 'body only',
    'primaryMuscles': ['chest'], 'secondaryMuscles': ['triceps'], 'instructions': ['Push.'],
  },
  {
    'id': 'Dumbbell_Bench_Press', 'name': 'Dumbbell Bench Press', 'category': 'strength', 'equipment': 'dumbbell',
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

  List<String> names(List<CatalogEntry> l) => [for (final e in l) e.name];

  test('lists the library sorted by name, with dataset load type defaults', () async {
    final all = await catalog.list();
    expect(names(all), ['Barbell Squat', 'Dumbbell Bench Press', 'Pushups']);
    expect(all.last.loadType, 'bodyweight');
    expect(all.first.loadType, 'weighted');
  });

  test('search is case-insensitive', () async {
    expect(names(await catalog.list(query: 'bEnCh')), ['Dumbbell Bench Press']);
  });

  test('muscle filter matches primary or secondary muscles', () async {
    expect(names(await catalog.list(muscle: 'chest')), ['Dumbbell Bench Press', 'Pushups']);
    expect(names(await catalog.list(muscle: 'glutes')), ['Barbell Squat']);
  });

  test('equipment filter', () async {
    expect(names(await catalog.list(equipment: 'body only')), ['Pushups']);
  });

  test('a row merges into its library entry', () async {
    await db.save(db.exercises, {'id': 'r1', 'library_id': 'Pushups', 'load_type': 'weighted', 'sticky_note': 'vest'});
    final p = (await catalog.list(query: 'push')).single;
    expect(p.rowId, 'r1');
    expect(p.loadType, 'weighted');
    expect(p.stickyNote, 'vest');
    expect(p.instructions, ['Push.']);
    expect(await catalog.list(), hasLength(3));
  });

  test('custom exercises are listed and soft-deleted rows are hidden', () async {
    await db.save(db.exercises, {'id': 'c1', 'name': 'Zercher Hold', 'load_type': 'timed', 'muscles': ['abdominals']});
    await db.save(db.exercises, {'id': 'c2', 'name': 'Gone', 'load_type': 'weighted', 'deleted_at': DateTime.now()});
    await db.save(db.exercises, {'id': 'r2', 'library_id': 'Pushups', 'deleted_at': DateTime.now()});
    final all = await catalog.list();
    expect(names(all), ['Barbell Squat', 'Dumbbell Bench Press', 'Pushups', 'Zercher Hold']);
    expect(all.firstWhere((e) => e.name == 'Pushups').rowId, isNull);
    expect(names(await catalog.list(muscle: 'abdominals')), ['Zercher Hold']);
  });

  test('a row whose library_id left the bundle shows a humanized id', () async {
    await db.save(db.exercises, {'id': 'r3', 'library_id': 'Old_Cable_Fly-Low'});
    expect(names(await catalog.list(query: 'fly')), ['Old Cable Fly Low']);
  });

  test('muscle and equipment options come from all entries', () async {
    await catalog.list();
    expect(catalog.muscles, ['chest', 'glutes', 'quadriceps', 'triceps']);
    expect(catalog.equipment, ['barbell', 'body only', 'dumbbell']);
  });

  test('image and video links', () {
    expect(exerciseImageUrl('3_4_Sit-Up', 1).toString(),
        'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/3_4_Sit-Up/1.jpg');
    expect(youtubeSearchUrl('Back Squat').toString(), 'https://www.youtube.com/results?search_query=Back+Squat+exercise');
  });
}

import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/catalog.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/importer.dart';
import 'package:timburr/data/routines.dart';
import 'package:timburr/data/workouts.dart';

const _library = [
  {
    'id': 'Barbell_Squat', 'name': 'Barbell Squat', 'category': 'strength', 'equipment': 'barbell',
    'primaryMuscles': ['quadriceps'], 'secondaryMuscles': [], 'instructions': [],
  },
  {
    'id': 'Pushups', 'name': 'Pushups', 'category': 'strength', 'equipment': 'body only',
    'primaryMuscles': ['chest'], 'secondaryMuscles': [], 'instructions': [],
  },
];

Map<String, dynamic> _doc() => jsonDecode('''
{"version": 1,
 "workouts": [{"date": "2026-10-24T16:13", "routine": "Push A", "notes": "",
   "exercises": [
     {"name": "barbell squat", "notes": "", "supersetWithNext": false,
      "sets": [{"weightKg": 100, "reps": 5}, {"weightKg": 110, "reps": 3}]},
     {"name": "Plank", "sets": [{"weightKg": null, "durationSec": 60}]}
   ]}],
 "cardio": [{"type": "run", "date": "2026-10-23T17:15", "distanceKm": 5.0, "durationSec": 1680,
   "avgHr": 158, "inclinePct": null, "rpe": 7, "notes": ""}]}
''') as Map<String, dynamic>;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDb db;
  late Catalog catalog;
  late Importer importer;
  setUp(() {
    db = AppDb(NativeDatabase.memory());
    catalog = Catalog(db, () async => jsonEncode(_library));
    importer = Importer(db, catalog);
  });
  tearDown(() => db.close());

  test('a valid document has no errors', () {
    expect(validateImport(_doc()), isEmpty);
  });

  test('errors name each bad field by path', () {
    final d = _doc();
    d['version'] = 2;
    final w = d['workouts'][0];
    w['date'] = 'yesterday';
    w['extra'] = 1;
    w['exercises'][0]['name'] = ' ';
    w['exercises'][0]['sets'][0]['reps'] = -1;
    w['exercises'][0]['sets'][1]['durationSec'] = 30; // both reps and durationSec
    w['exercises'][1]['sets'] = [];
    d['cardio'][0]['type'] = 'golf';
    d['cardio'][0]['rpe'] = 11;
    d['cardio'][0]['distanceKm'] = '5';
    expect(validateImport(d), [
      'version: must be 1',
      'workouts[0].extra: unknown field',
      'workouts[0].date: must be a date like 2026-10-24T16:13',
      'workouts[0].exercises[0].name: required',
      'workouts[0].exercises[0].sets[0].reps: must be a whole number >= 0',
      'workouts[0].exercises[0].sets[1]: give reps or durationSec, not both',
      'workouts[0].exercises[1].sets: must be a non-empty list',
      'cardio[0].type: must be one of run, walk, treadmill, bike, swim, padel, tennis, soccer, basketball',
      'cardio[0].distanceKm: must be a number > 0',
      'cardio[0].rpe: must be a whole number 1-10',
    ]);
    expect(validateImport('nope'), ['root: must be an object']);
  });

  test('numbers over the server column limits fail', () {
    final d = _doc();
    d['workouts'][0]['exercises'][0]['sets'][0]['weightKg'] = 10000;
    d['cardio'][0]['distanceKm'] = 10000;
    expect(validateImport(d), [
      'workouts[0].exercises[0].sets[0].weightKg: must be less than 10000',
      'cardio[0].distanceKm: must be less than 10000',
    ]);
    d['workouts'][0]['exercises'][0]['sets'][0]['weightKg'] = 9999.99;
    d['cardio'][0]['distanceKm'] = 9999.999;
    expect(validateImport(d), isEmpty);
  });

  test('sports need no distanceKm', () {
    final d = _doc();
    d['cardio'][0]
      ..['type'] = 'padel'
      ..remove('distanceKm');
    expect(validateImport(d), isEmpty);
  });

  test('a name can match a library alias', () async {
    final c = Catalog(db, () async => jsonEncode([
      {..._library.first, 'aliases': ['Back Squat']},
    ]));
    final d = _doc();
    (d['workouts'] as List).first['exercises'][0]['name'] = 'back squat';
    expect(await Importer(db, c).unknownNames(d), ['Plank']);
  });

  test('names match library and custom exercises case-insensitively; the rest are unknown', () async {
    final d = _doc();
    expect(await importer.unknownNames(d), ['Plank']);
    await catalog.saveCustom(name: 'PLANK', loadType: 'timed');
    expect(await importer.unknownNames(d), isEmpty);
  });

  test('save creates unknowns as custom exercises and the workout counts for last time', () async {
    await importer.save(_doc());
    final plank = (await catalog.list(query: 'plank')).single;
    expect((plank.rowId != null, plank.loadType), (true, 'timed'));
    final workouts = WorkoutStore(db);
    final later = await workouts.start();
    final last = await workouts.lastTime(libraryRowId('Barbell_Squat'), excludeWorkoutId: later);
    expect([for (final s in last) (s.weightKg, s.reps, s.done)], [(100.0, 5, true), (110.0, 3, true)]);
    final w = (await db.select(db.workouts).get()).firstWhere((w) => w.id != later);
    expect((w.startedAt, w.finishedAt), (DateTime(2026, 10, 24, 16, 13), DateTime(2026, 10, 24, 16, 13)));
    final c = await db.select(db.cardio).getSingle();
    expect((c.type, c.distanceKm, c.durationSec, c.avgHr, c.rpe), ('run', 5.0, 1680, 158, 7));
  });

  test('Z dates import as local time and sort among local rows', () async {
    final utc = DateTime.utc(2026, 10, 24, 16, 13);
    final d = _doc();
    d['workouts'][0]['date'] = '2026-10-24T16:13:00Z';
    d['cardio'][0]['date'] = '2026-10-24T16:13:00Z';
    await importer.save(d);
    // A local-time row one minute later, written the way the app writes it.
    final later = _doc()..remove('cardio');
    later['workouts'][0]['date'] = utc.add(const Duration(minutes: 1)).toLocal().toIso8601String();
    await importer.save(later);
    final ws = await (db.select(db.workouts)..orderBy([(w) => OrderingTerm(expression: w.startedAt)])).get();
    expect([for (final w in ws) (w.startedAt.isUtc, w.startedAt)], [(false, utc.toLocal()), (false, utc.add(const Duration(minutes: 1)).toLocal())]);
    final c = await db.select(db.cardio).getSingle();
    expect((c.startedAt.isUtc, c.startedAt), (false, utc.toLocal()));
  });

  test('an unknown name can be mapped to an existing exercise', () async {
    await importer.save(_doc(), mapping: {'plank': (await catalog.list(query: 'pushups')).single});
    expect(await catalog.list(query: 'plank'), isEmpty);
    final ids = [for (final e in await db.select(db.workoutExercises).get()) e.exerciseId];
    expect(ids, containsAll([libraryRowId('Barbell_Squat'), libraryRowId('Pushups')]));
  });

  test('a failed save leaves the store unchanged', () async {
    await expectLater(importer.save(_doc(), mapping: {'plank': CatalogEntry(name: 'Gone', rowId: 'no-such-row')}), throwsA(anything));
    expect(await db.select(db.workouts).get(), isEmpty);
    expect(await db.select(db.exercises).get(), isEmpty);
    expect(await db.select(db.cardio).get(), isEmpty);
    final bad = _doc()..['version'] = 3;
    await expectLater(importer.save(bad), throwsA(isA<FormatException>()));
  });

  test('copy format lists custom and used exercises only', () async {
    await catalog.saveCustom(name: 'Plank', loadType: 'timed');
    final w = WorkoutStore(db);
    await w.addExercise(await w.start(), (await catalog.list(query: 'squat')).single);
    final text = await importer.formatText();
    expect(text, contains('"version": 1'));
    expect(text, contains('- Barbell Squat\n- Plank'));
    expect(text, isNot(contains('Pushups')));
  });

  test('saveRoutines creates a missing routine from the workout, links it, and reuses an existing one', () async {
    final routines = RoutineStore(db);
    await importer.save(_doc(), saveRoutines: true);
    final list = await routines.watchRoutines().first;
    expect(list.map((r) => r.name), ['Push A']);
    final plan = await routines.plan(list.single.id);
    final w = (await db.select(db.workouts).get()).single;
    expect(w.routineId, list.single.id);
    final firstSets = await (db.select(db.workoutSets)..orderBy([(s) => OrderingTerm(expression: s.setNumber)])).get();
    expect(plan, isNotEmpty);
    expect(plan.first.sets.length, greaterThan(0));
    expect(firstSets, isNotEmpty);

    await importer.save(_doc(), saveRoutines: true); // same name again: no second routine, plan untouched
    expect((await routines.watchRoutines().first), hasLength(1));
    expect(await routines.plan(list.single.id), hasLength(plan.length));
  });

  test('without saveRoutines no routine is created', () async {
    await importer.save(_doc());
    expect(await db.select(db.routines).get(), isEmpty);
  });
}

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/cardio.dart';
import 'package:timburr/data/catalog.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/workouts.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('v6 to v7 adds the Run columns, tracks, settings and the best-effort cache, keeping rows', () async {
    final file = File('${Directory.systemTemp.createTempSync().path}/t.db');
    var db = AppDb(NativeDatabase(file));
    await CardioStore(db).save(type: 'run', startedAt: DateTime(2026), distanceKm: 5, durationSec: 1500);
    await _dropV7Schema(db);
    await db.customStatement('pragma user_version = 6');
    await db.close();

    db = AppDb(NativeDatabase(file));
    final run = (await CardioStore(db).watchAll().first).single;
    expect((run.distanceKm, run.durationSec, run.elapsedSec, run.source), (5.0, 1500, null, null));
    expect(run.editedFields, isEmpty);
    await db.save(db.cardioTracks, {'id': 't1', 'cardio_id': run.id, 'points': 'x'});
    await db.save(db.appSettings, {'id': 's1', 'max_hr': 190, 'birth_year': 1990, 'stride_m': 0.9});
    await db.into(db.bestEfforts).insert(BestEffortsCompanion.insert(cardioId: run.id, distanceM: 1000, seconds: 240));
    final idx = await db.customSelect("select name from sqlite_master where type = 'index' and name like '%_dirty'").get();
    expect(idx.map((r) => r.read<String>('name')), containsAll(['cardio_tracks_dirty', 'settings_dirty']));
    await db.close();
  });

  test('v1 to v2 adds routine_sets and makes cardio distance optional, keeping rows', () async {
    final file = File('${Directory.systemTemp.createTempSync().path}/t.db');
    // Build a v1 file: today's schema minus routine_sets, with distance_km NOT NULL again.
    var db = AppDb(NativeDatabase(file));
    await _dropV7Schema(db);
    final ddl = (await db.customSelect("select sql from sqlite_master where name = 'cardio'").getSingle()).read<String>('sql');
    expect(ddl, contains('"distance_km" REAL NULL'));
    await _dropV6Columns(db);
    await _dropV3Columns(db);
    await db.customStatement('drop table routine_sets');
    await db.customStatement('drop table cardio');
    await db.customStatement(ddl.replaceFirst('"distance_km" REAL NULL', '"distance_km" REAL NOT NULL'));
    await CardioStore(db).save(type: 'run', startedAt: DateTime(2026), distanceKm: 5, durationSec: 1500);
    await db.customStatement('pragma user_version = 1');
    await db.close();

    db = AppDb(NativeDatabase(file));
    final store = CardioStore(db);
    await store.save(type: 'padel', startedAt: DateTime(2026, 2), distanceKm: null, durationSec: 3600);
    expect([for (final c in await store.watchAll().first) (c.type, c.distanceKm)], [('padel', null), ('run', 5.0)]);
    expect(await db.select(db.routineSets).get(), isEmpty);
    await db.close();
  });

  test('v2 to v3 adds drop flag, backup exercises and health stats, keeping rows', () async {
    final file = File('${Directory.systemTemp.createTempSync().path}/t.db');
    var db = AppDb(NativeDatabase(file));
    final w = await WorkoutStore(db).start();
    await _dropV7Schema(db);
    await _dropV6Columns(db);
    await _dropV3Columns(db);
    await db.customStatement('pragma user_version = 2');
    await db.close();

    db = AppDb(NativeDatabase(file));
    final row = await WorkoutStore(db).watchWorkout(w).first;
    expect((row.id, row.avgHr), (w, null));
    await db.close();
  });

  test('v4 to v5 adds a dirty index on every synced table, keeping rows', () async {
    final file = File('${Directory.systemTemp.createTempSync().path}/t.db');
    var db = AppDb(NativeDatabase(file));
    final w = await WorkoutStore(db).start();
    final names = [for (final t in db.syncedTables) '${t.actualTableName}_dirty'];
    for (final n in names) {
      await db.customStatement('drop index $n');
    }
    await _dropV7Schema(db);
    await _dropV6Columns(db);
    await db.customStatement('pragma user_version = 4');
    await db.close();

    db = AppDb(NativeDatabase(file));
    expect((await WorkoutStore(db).watchWorkout(w).first).id, w);
    final idx = await db.customSelect("select name from sqlite_master where type = 'index' and name like '%_dirty'").get();
    expect(idx.map((r) => r.read<String>('name')).toSet(), names.toSet());
    await db.close();
  });

  test('v5 to v6 moves each backup exercise into alternatives and adds skipped, keeping rows', () async {
    final file = File('${Directory.systemTemp.createTempSync().path}/t.db');
    var db = AppDb(NativeDatabase(file));
    final w = await WorkoutStore(db).start();
    await WorkoutStore(db).addExercise(w, CatalogEntry(name: 'A', libraryId: 'A', loadType: 'weighted'));
    await db.customStatement("update workout_exercises set backup_exercise_id = '${libraryRowId('A')}'");
    await _dropV7Schema(db);
    await _dropV6Columns(db);
    await db.customStatement('pragma user_version = 5');
    await db.close();

    db = AppDb(NativeDatabase(file));
    final e = (await WorkoutStore(db).watchExercises(w).first).single;
    expect(e.alternativeIds, [libraryRowId('A')]);
    expect(e.skipped, false);
    await db.close();
  });
}

/// Back to the v2 schema: drops the columns v3 added.
Future<void> _dropV3Columns(AppDb db) async {
  for (final (t, c) in [
    ('sets', 'is_drop'),
    ('routine_exercises', 'backup_exercise_id'),
    ('workout_exercises', 'backup_exercise_id'),
    ('workouts', 'avg_hr'),
    ('workouts', 'calories'),
    ('workouts', 'active_sec'),
    ('workouts', 'effort'),
    ('workouts', 'cardio_load'),
  ]) {
    await db.customStatement('alter table $t drop column $c');
  }
}

/// Back to the v6 schema: drops what v7 added.
Future<void> _dropV7Schema(AppDb db) async {
  for (final t in ['cardio_tracks', 'settings', 'best_efforts']) {
    await db.customStatement('drop table $t');
  }
  for (final c in ['elapsed_sec', 'title', 'source', 'external_id', 'elevation_gain_m', 'max_hr', 'avg_cadence', 'calories', 'route', 'edited_fields']) {
    await db.customStatement('alter table cardio drop column $c');
  }
}

/// Back to the v5 schema: drops the columns v6 added.
Future<void> _dropV6Columns(AppDb db) async {
  for (final (t, c) in [('routine_exercises', 'alternative_ids'), ('workout_exercises', 'alternative_ids'), ('workout_exercises', 'skipped')]) {
    await db.customStatement('alter table $t drop column $c');
  }
}

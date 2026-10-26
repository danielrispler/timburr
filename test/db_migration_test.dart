import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/cardio.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/workouts.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('v1 to v2 adds routine_sets and makes cardio distance optional, keeping rows', () async {
    final file = File('${Directory.systemTemp.createTempSync().path}/t.db');
    // Build a v1 file: today's schema minus routine_sets, with distance_km NOT NULL again.
    var db = AppDb(NativeDatabase(file));
    final ddl = (await db.customSelect("select sql from sqlite_master where name = 'cardio'").getSingle()).read<String>('sql');
    expect(ddl, contains('"distance_km" REAL NULL'));
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
    await db.customStatement('pragma user_version = 4');
    await db.close();

    db = AppDb(NativeDatabase(file));
    expect((await WorkoutStore(db).watchWorkout(w).first).id, w);
    final idx = await db.customSelect("select name from sqlite_master where type = 'index' and name like '%_dirty'").get();
    expect(idx.map((r) => r.read<String>('name')).toSet(), names.toSet());
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

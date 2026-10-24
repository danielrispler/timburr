import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/cardio.dart';
import 'package:timburr/data/db.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('v1 to v2 adds routine_sets and makes cardio distance optional, keeping rows', () async {
    final file = File('${Directory.systemTemp.createTempSync().path}/t.db');
    // Build a v1 file: today's schema minus routine_sets, with distance_km NOT NULL again.
    var db = AppDb(NativeDatabase(file));
    final ddl = (await db.customSelect("select sql from sqlite_master where name = 'cardio'").getSingle()).read<String>('sql');
    expect(ddl, contains('"distance_km" REAL NULL'));
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
}

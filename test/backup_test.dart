import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/backup.dart';
import 'package:timburr/data/catalog.dart' show libraryRowId;
import 'package:timburr/data/db.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final dbs = <AppDb>[];
  AppDb newDb() {
    final d = AppDb(NativeDatabase.memory());
    dbs.add(d);
    return d;
  }

  tearDown(() async {
    for (final d in dbs) {
      await d.close();
    }
    dbs.clear();
  });

  Future<void> seed(AppDb d) async {
    await d.save(d.exercises, {'id': 'e1', 'name': 'Curl', 'load_type': 'weighted', 'muscles': ['biceps'], 'user_id': 'u1'});
    await d.save(d.exercises, {'id': libraryRowId('Bench'), 'library_id': 'Bench', 'sticky_note': 'grip', 'user_id': 'u1'});
    await d.save(d.routines, {'id': 'r1', 'name': 'Push'});
    await d.save(d.routineExercises, {'id': 're1', 'routine_id': 'r1', 'exercise_id': 'e1', 'position': 0});
    await d.save(d.workouts, {'id': 'w1', 'started_at': DateTime.utc(2026, 10, 1), 'routine_id': 'r1'});
    await d.save(d.workoutExercises, {'id': 'we1', 'workout_id': 'w1', 'exercise_id': 'e1', 'position': 0, 'superset_with_next': true});
    await d.save(d.workoutSets, {'id': 's1', 'workout_exercise_id': 'we1', 'set_number': 0, 'weight_kg': 20.5, 'reps': 8, 'done': true});
    await d.save(d.workoutSets, {'id': 's2', 'workout_exercise_id': 'we1', 'set_number': 1, 'deleted_at': DateTime.utc(2026, 10, 2)});
    await d.save(d.cardio, {'id': 'c1', 'type': 'run', 'started_at': DateTime.utc(2026, 10, 3), 'distance_km': 5.0, 'duration_sec': 1500});
  }

  /// Every row of every synced table (times as instants), minus the local-only columns restore does not carry over.
  Future<Map<String, List<Map<String, Object?>>>> dump(AppDb d, {Set<String> skip = const {'dirty', 'user_id', 'server_updated_at'}}) async => {
        for (final t in d.syncedTables)
          t.actualTableName: [
            for (final r in await d.customSelect('select * from ${t.actualTableName} order by id').get())
              {for (final e in r.data.entries) if (!skip.contains(e.key)) e.key: e.key.endsWith('_at') && e.value is String ? DateTime.parse(e.value as String).toUtc() : e.value},
          ],
      };

  test('round trip: export, restore into an empty store, compare', () async {
    final a = newDb();
    await seed(a);
    final b = newDb();
    await Backup(b).restore(await Backup(a).export(), replace: false);
    expect(await dump(b), await dump(a));
    final dirty = await b.customSelect('select count(*) as n from sets where dirty = 1').getSingle();
    expect(dirty.read<int>('n'), 2);
  });

  test('export carries every column, soft-deleted rows included', () async {
    final a = newDb();
    await seed(a);
    final json = jsonDecode(await Backup(a).export()) as Map<String, dynamic>;
    expect(json['format'], 'timburr-backup');
    expect(json['version'], 1);
    final sets = (json['tables'] as Map)['sets'] as List;
    expect(sets.map((s) => s['id']), containsAll(['s1', 's2']));
    final s1 = sets.firstWhere((s) => s['id'] == 's1') as Map;
    expect(s1.keys, containsAll(['user_id', 'created_at', 'updated_at', 'deleted_at', 'server_updated_at', 'done']));
    expect(s1['done'], true);
    expect(((json['tables'] as Map)['exercises'] as List).first['muscles'], isA<List>());
  });

  test('replace soft-deletes local rows missing from the backup and restores the rest', () async {
    final a = newDb();
    await seed(a);
    final backup = await Backup(a).export();
    final b = newDb();
    await seed(b);
    await b.save(b.cardio, {'id': 'c2', 'type': 'bike', 'started_at': DateTime.utc(2026, 10, 5), 'distance_km': 10.0, 'duration_sec': 1800});
    await b.save(b.routines, {'id': 'r1', 'name': 'Renamed later'});
    await Backup(b).restore(backup, replace: true);
    final c2 = await b.customSelect("select deleted_at, dirty from cardio where id = 'c2'").getSingle();
    expect(c2.data['deleted_at'], isNotNull);
    expect(c2.data['dirty'], 1);
    final r1 = await b.customSelect("select name from routines where id = 'r1'").getSingle();
    expect(r1.data['name'], 'Push');
    // Stamped now, so the restored state wins against the server on the next sync.
    final s1 = await b.customSelect("select updated_at from sets where id = 's1'").getSingle();
    expect(DateTime.parse(s1.data['updated_at'] as String).isAfter(DateTime.now().subtract(const Duration(minutes: 1))), true);
  });

  test('merge upserts by id, last write wins, and keeps local-only rows', () async {
    final a = newDb();
    await seed(a);
    final b = newDb();
    await seed(b); // b's rows are written after a's, so b wins
    await b.save(b.cardio, {'id': 'c2', 'type': 'bike', 'started_at': DateTime.utc(2026, 10, 5), 'distance_km': 10.0, 'duration_sec': 1800});
    await b.save(b.routines, {'id': 'r1', 'name': 'Local edit'});
    await a.save(a.cardio, {'id': 'c1', 'type': 'run', 'started_at': DateTime.utc(2026, 10, 3), 'distance_km': 6.0, 'duration_sec': 1500});
    await Backup(b).restore(await Backup(a).export(), replace: false);
    final r1 = await b.customSelect("select name from routines where id = 'r1'").getSingle();
    expect(r1.data['name'], 'Local edit');
    final c1 = await b.customSelect("select distance_km from cardio where id = 'c1'").getSingle();
    expect(c1.data['distance_km'], 6.0);
    final c2 = await b.customSelect("select deleted_at from cardio where id = 'c2'").getSingle();
    expect(c2.data['deleted_at'], isNull);
  });

  test('restore under a different user_id keeps the local user_id and makes no duplicate exercises', () async {
    final a = newDb();
    await seed(a);
    final b = newDb();
    await b.save(b.exercises, {'id': libraryRowId('Bench'), 'library_id': 'Bench', 'user_id': 'u2'});
    await Backup(b).restore(await Backup(a).export(), replace: true);
    final rows = await b.customSelect("select user_id, sticky_note from exercises where library_id = 'Bench'").get();
    expect(rows, hasLength(1));
    expect(rows.single.data['user_id'], 'u2');
    expect(rows.single.data['sticky_note'], 'grip');
    final e1 = await b.customSelect("select user_id from exercises where id = 'e1'").getSingle();
    expect(e1.data['user_id'], isNull); // the new project's server default fills it on push
  });

  test('a bad file changes nothing', () async {
    final b = newDb();
    await seed(b);
    final before = await dump(b, skip: const {});
    final bad = jsonDecode(await Backup(b).export()) as Map<String, dynamic>;
    ((bad['tables'] as Map)['sets'] as List).add({'id': 's9', 'workout_exercise_id': 'missing', 'set_number': 0, 'updated_at': '2026-10-01T00:00:00Z'});
    await expectLater(Backup(b).restore(jsonEncode(bad), replace: true), throwsA(anything));
    await expectLater(Backup(b).restore('{"format":"other"}', replace: true), throwsFormatException);
    await expectLater(Backup(b).restore('not json', replace: false), throwsFormatException);
    expect(await dump(b, skip: const {}), before);
  });

  group('reminder', () {
    final now = DateTime.utc(2026, 10, 24, 12);
    test('shows when never exported', () => expect(backupDue(now: now), true));
    test('hidden at exactly 14 days, shown just past', () {
      expect(backupDue(lastExport: now.subtract(const Duration(days: 14)), now: now), false);
      expect(backupDue(lastExport: now.subtract(const Duration(days: 14, seconds: 1)), now: now), true);
    });
    test('dismissing hides it for another 14 days', () {
      final old = now.subtract(const Duration(days: 30));
      expect(backupDue(lastExport: old, dismissedAt: now.subtract(const Duration(days: 13)), now: now), false);
      expect(backupDue(lastExport: old, dismissedAt: now.subtract(const Duration(days: 15)), now: now), true);
    });
  });
}

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/catalog.dart' show libraryRowId;
import 'package:timburr/data/db.dart';
import 'package:timburr/data/sync.dart';

/// In-memory Supabase: last write wins by updated_at and bumps server_updated_at, like touch_row.
class FakeRemote implements Remote {
  final tables = <String, Map<String, Map<String, Object?>>>{};
  final upserts = <String>[];
  final failOn = <String>{};
  final rejectIds = <String>{};
  Future<void> Function(String table)? onPage;
  Future<void> Function(String table)? onUpsert;
  var _clock = DateTime.utc(2026, 10, 24);

  @override
  Future<void> upsert(String table, List<Map<String, Object?>> rows) async {
    if (failOn.contains(table)) throw Exception('boom $table');
    if (rows.any((r) => rejectIds.contains(r['id']))) throw Exception('rejected');
    upserts.add(table);
    await onUpsert?.call(table);
    final t = tables.putIfAbsent(table, () => {});
    for (final r in rows) {
      final old = t[r['id']];
      if (old != null && DateTime.parse(r['updated_at'] as String).isBefore(DateTime.parse(old['updated_at'] as String))) {
        continue;
      }
      _clock = _clock.add(const Duration(milliseconds: 1));
      t[r['id'] as String] = {...?old, ...r, 'user_id': 'u1', 'server_updated_at': _clock.toIso8601String()};
    }
  }

  @override
  Future<List<Map<String, Object?>>> changedSince(String table, DateTime? since, String? afterId, int limit) async {
    if (failOn.contains(table)) throw Exception('boom $table');
    await onPage?.call(table);
    int cmp(Map<String, Object?> r) {
      final c = DateTime.parse(r['server_updated_at'] as String).compareTo(since!);
      return c != 0 ? c : (afterId == null ? 0 : (r['id'] as String).compareTo(afterId));
    }
    final rows = (tables[table]?.values ?? const <Map<String, Object?>>[])
        .where((r) => since == null || (afterId == null ? cmp(r) >= 0 : cmp(r) > 0))
        .toList()
      ..sort((a, b) {
        final c = (a['server_updated_at'] as String).compareTo(b['server_updated_at'] as String);
        return c != 0 ? c : (a['id'] as String).compareTo(b['id'] as String);
      });
    return rows.take(limit).toList();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDb db;
  late FakeRemote remote;
  late SyncEngine engine;
  final dbs = <AppDb>[];
  AppDb newDb() => AppDb(NativeDatabase.memory())..also(dbs.add);

  setUp(() {
    db = newDb();
    remote = FakeRemote();
    engine = SyncEngine(db, remote, pageSize: 2, chunkSize: 2);
  });
  tearDown(() async {
    for (final d in dbs) {
      await d.close();
    }
    dbs.clear();
  });

  Future<void> seedWorkout(AppDb d) async {
    await d.save(d.exercises, {'id': 'e1', 'name': 'Curl', 'load_type': 'weighted', 'muscles': ['biceps']});
    await d.save(d.workouts, {'id': 'w1', 'started_at': DateTime.utc(2026, 10, 24)});
    await d.save(d.workoutExercises, {'id': 'we1', 'workout_id': 'w1', 'exercise_id': 'e1', 'position': 0});
    for (var i = 0; i < 3; i++) {
      await d.save(d.workoutSets, {'id': 's$i', 'workout_exercise_id': 'we1', 'set_number': i, 'weight_kg': 20.5, 'reps': 8, 'done': true});
    }
  }

  test('push sends dirty rows parents first, in chunks, and clears dirty', () async {
    await seedWorkout(db);
    expect(await engine.pending(), 6);
    await engine.sync();
    expect(remote.upserts, ['exercises', 'workouts', 'workout_exercises', 'sets', 'sets']);
    expect(await engine.pending(), 0);
    final set = remote.tables['sets']!['s1']!;
    expect(set['done'], true);
    expect(set['weight_kg'], 20.5);
    expect(remote.tables['exercises']!['e1']!['muscles'], ['biceps']);
    expect(set.containsKey('dirty'), isFalse);
  });

  test('an edit made during the push stays dirty', () async {
    await db.save(db.routines, {'id': 'r1', 'name': 'Push'});
    remote.onUpsert = (_) async {
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await db.save(db.routines, {'id': 'r1', 'name': 'Push day'});
    };
    await engine.sync();
    expect(await engine.pending(), 1);
    remote.onUpsert = null;
    await engine.sync();
    expect(await engine.pending(), 0);
    expect(remote.tables['routines']!['r1']!['name'], 'Push day');
  });

  test('fresh install pulls everything, paged, and soft deletes propagate', () async {
    await seedWorkout(db);
    await db.save(db.workoutSets, {'id': 's2', 'workout_exercise_id': 'we1', 'set_number': 2, 'deleted_at': DateTime.now()}); // shortcut: save needs full rows (#6 gap)
    await engine.sync();

    final other = newDb();
    await SyncEngine(other, remote, pageSize: 2).sync();
    final sets = await other.select(other.workoutSets).get();
    expect(sets, hasLength(3));
    expect(sets.where((s) => s.deletedAt != null).map((s) => s.id), ['s2']);
    expect(sets.first.done, isTrue);
    expect((await other.select(other.exercises).getSingle()).muscles, ['biceps']);
    expect(await SyncEngine(other, remote).pending(), 0);
  });

  test('re-pulling the cursor overlap is a no-op', () async {
    await db.save(db.routines, {'id': 'r1', 'name': 'Push'});
    await engine.sync();
    // Same updated_at as the server copy: the overlap re-delivers it, and it must not be re-applied.
    await db.customStatement("update routines set name = 'local'");
    await engine.sync();
    expect((await db.select(db.routines).getSingle()).name, 'local');
  });

  test('last write wins both ways', () async {
    final b = newDb();
    final engineB = SyncEngine(b, remote);
    await db.save(db.routines, {'id': 'r1', 'name': 'A old'});
    await engine.sync();
    await engineB.sync();

    // B edits later than A; A pushes its older edit last.
    await db.save(db.routines, {'id': 'r1', 'name': 'A'});
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await b.save(b.routines, {'id': 'r1', 'name': 'B'});
    await engineB.sync();
    await engine.sync();
    expect(remote.tables['routines']!['r1']!['name'], 'B');
    expect((await db.select(db.routines).getSingle()).name, 'B');

    // A edits later: B pulls it over its older copy.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await db.save(db.routines, {'id': 'r1', 'name': 'A newest'});
    await engine.sync();
    await engineB.sync();
    expect((await b.select(b.routines).getSingle()).name, 'A newest');
  });

  test('a failing table stops sync, keeps rows dirty, and the next sync retries', () async {
    await seedWorkout(db);
    remote.failOn.add('workouts');
    await engine.sync();
    expect(engine.error.value, contains('boom workouts'));
    expect(remote.upserts, ['exercises', 'workout_exercises', 'sets', 'sets']); // children reach the fake; Postgres FKs would reject them
    expect(await engine.pending(), 1);

    remote.failOn.clear();
    await engine.sync();
    expect(engine.error.value, isNull);
    expect(await engine.pending(), 0);
  });

  test('a rejected row is skipped and reported; the rest sync', () async {
    await seedWorkout(db);
    remote.rejectIds.add('s1');
    await engine.sync();
    expect(remote.tables['sets']!.keys, unorderedEquals(['s0', 's2']));
    expect(remote.tables['workout_exercises']!.keys, ['we1']);
    expect(engine.error.value, allOf(contains('sets'), contains('s1')));
    expect(await engine.pending(), 1);

    remote.rejectIds.clear();
    await engine.sync();
    expect(engine.error.value, isNull);
    expect(await engine.pending(), 0);
  });

  test('a row updated between pull pages is still fetched', () async {
    for (final id in ['r1', 'r2', 'r3', 'r4']) {
      await db.save(db.routines, {'id': id, 'name': id});
    }
    await engine.sync();
    final other = newDb();
    var pages = 0;
    remote.onPage = (table) async {
      // After page one, r1 moves to the end of the order; OFFSET paging would then skip r3.
      if (table == 'routines' && ++pages == 2) {
        await remote.upsert('routines', [{...remote.tables['routines']!['r1']!, 'name': 'r1b', 'updated_at': DateTime.now().toUtc().toIso8601String()}]);
      }
    };
    await SyncEngine(other, remote, pageSize: 2).sync();
    final names = (await other.select(other.routines).get()).map((r) => r.name);
    expect(names, unorderedEquals(['r1b', 'r2', 'r3', 'r4']));
  });

  test('two offline devices configuring the same library exercise end with one row', () async {
    final b = newDb();
    final id = libraryRowId('Barbell_Curl');
    expect(libraryRowId('Barbell_Curl'), id);
    await db.save(db.exercises, {'id': id, 'library_id': 'Barbell_Curl', 'sticky_note': 'A'});
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await b.save(b.exercises, {'id': id, 'library_id': 'Barbell_Curl', 'last_rest_sec': 90});
    await engine.sync();
    await SyncEngine(b, remote).sync();
    await engine.sync();
    expect(remote.tables['exercises'], hasLength(1));
    expect((await db.select(db.exercises).get()).single.lastRestSec, 90);
  });

  test('offline skips sync and wipe clears the local copy', () async {
    await seedWorkout(db);
    final offline = SyncEngine(db, remote, isOnline: () async => false);
    await offline.sync();
    expect(offline.offline.value, isTrue);
    expect(remote.upserts, isEmpty);

    await engine.sync();
    await engine.wipe();
    expect(await db.select(db.workoutSets).get(), isEmpty);
    expect(await db.select(db.syncCursors).get(), isEmpty);
  });
  // Mis-sorted as text only where UTC is behind local time by 3h or more, for example TZ=Asia/Jerusalem.
  test('pulled datetimes sort with local writes by started_at', () async {
    await db.save(db.workouts, {'id': 'local', 'started_at': DateTime(2026, 10, 24, 12)});
    final pulled = rowFromJson(db.workouts, {'id': 'pulled', 'started_at': DateTime(2026, 10, 24, 14).toUtc().toIso8601String()});
    await db.save(db.workouts, pulled);
    final rows = await db.customSelect('select id from workouts order by started_at').get();
    expect(rows.map((r) => r.read<String>('id')), ['local', 'pulled']);
  });

}

extension<T> on T {
  void also(void Function(T) f) => f(this);

}

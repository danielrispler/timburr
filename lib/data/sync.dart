import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'db.dart';

/// Row id of a library exercise: the same on every device, so two offline devices configuring it end with one row.
String libraryRowId(String libraryId) => const Uuid().v5(Namespace.url.value, 'timburr:library:$libraryId');

/// The narrow slice of Supabase sync needs. Rows are JSON maps keyed by SQL column name.
abstract class Remote {
  Future<void> upsert(String table, List<Map<String, Object?>> rows);

  /// Rows with `server_updated_at >= since` (all when null), ordered by `server_updated_at`.
  Future<List<Map<String, Object?>>> changedSince(String table, DateTime? since, int offset, int limit);
}

/// Push then pull, one table at a time in dependency order. See docs/design.md, Sync.
class SyncEngine {
  SyncEngine(this._db, this._remote, {Future<bool> Function()? isOnline, this.pageSize = 1000, this.chunkSize = 500})
      : _isOnline = isOnline ?? (() async => true);

  final AppDb _db;
  final Remote _remote;
  final Future<bool> Function() _isOnline;
  final int pageSize, chunkSize;

  final error = ValueNotifier<String?>(null);
  final offline = ValueNotifier<bool>(false);

  static const overlap = Duration(seconds: 5);

  List<TableInfo> get _tables =>
      [_db.exercises, _db.routines, _db.routineExercises, _db.workouts, _db.workoutExercises, _db.workoutSets, _db.cardio];

  Future<void>? _running;
  bool _again = false;

  /// Runs one sync. A call made while one is running queues exactly one more run.
  Future<void> sync() {
    if (_running != null) {
      _again = true;
      return _running!;
    }
    return _running = () async {
      do {
        _again = false;
        await _once();
      } while (_again);
    }()
        .whenComplete(() => _running = null);
  }

  Future<void> _once() async {
    offline.value = !await _isOnline();
    if (offline.value) return;
    try {
      for (final t in _tables) {
        await _push(t);
      }
      for (final t in _tables) {
        await _pull(t);
      }
      error.value = null;
    } catch (e) {
      error.value = '$e';
    }
  }

  Future<void> _push(TableInfo table) async {
    final name = table.actualTableName;
    final rows = await _db.customSelect('select * from $name where dirty = 1', readsFrom: {table}).get();
    for (var i = 0; i < rows.length; i += chunkSize) {
      final chunk = rows.sublist(i, (i + chunkSize).clamp(0, rows.length));
      await _remote.upsert(name, [for (final r in chunk) _toRemote(table, r.data)]);
      // Only rows untouched since we read them; an edit made mid-push keeps dirty = 1.
      for (final r in chunk) {
        await _db.customUpdate('update $name set dirty = 0 where id = ? and updated_at = ?',
            variables: [Variable(r.data['id']), Variable(r.data['updated_at'])], updates: {table});
      }
    }
  }

  Future<void> _pull(TableInfo table) async {
    final name = table.actualTableName;
    final cursorRow = await (_db.select(_db.syncCursors)..where((c) => c.syncedTable.equals(name))).getSingleOrNull();
    final since = cursorRow?.cursor?.subtract(overlap);
    DateTime? newest = cursorRow?.cursor;
    for (var offset = 0;; offset += pageSize) {
      final page = await _remote.changedSince(name, since, offset, pageSize);
      await _db.transaction(() async {
        for (final r in page) {
          await _apply(table, r);
          final s = DateTime.parse(r['server_updated_at'] as String);
          if (newest == null || s.isAfter(newest!)) newest = s;
        }
      });
      if (page.length < pageSize) break;
    }
    if (newest != null) {
      await _db.into(_db.syncCursors).insertOnConflictUpdate(SyncCursorsCompanion.insert(syncedTable: name, cursor: Value(newest)));
    }
  }

  /// Last write wins: apply only a row that is new here or newer than the local copy.
  Future<void> _apply(TableInfo table, Map<String, Object?> remote) async {
    final name = table.actualTableName;
    final local = await _db.customSelect('select updated_at from $name where id = ?', variables: [Variable(remote['id'])]).getSingleOrNull();
    final remoteAt = DateTime.parse(remote['updated_at'] as String);
    if (local != null && !remoteAt.isAfter(DateTime.parse(local.data['updated_at'] as String))) return;
    final values = <String, Object?>{'dirty': 0};
    for (final c in table.$columns) {
      if (c.name == 'dirty' || !remote.containsKey(c.name)) continue;
      final v = remote[c.name];
      values[c.name] = switch (v) {
        String s when c.type == DriftSqlType.dateTime => DateTime.parse(s),
        List l => jsonEncode(l),
        num n when c.type == DriftSqlType.double => n.toDouble(),
        _ => v,
      };
    }
    final cols = values.keys.join(', ');
    await _db.customInsert(
      'insert into $name ($cols) values (${List.filled(values.length, '?').join(', ')}) '
      'on conflict (id) do update set ${values.keys.map((k) => '$k = excluded.$k').join(', ')}',
      variables: [for (final v in values.values) Variable(v)],
      updates: {table},
    );
  }

  Map<String, Object?> _toRemote(TableInfo table, Map<String, Object?> raw) => {
        for (final c in table.$columns)
          if (c.name != 'dirty' && !(c.name == 'user_id' && raw[c.name] == null) && c.name != 'server_updated_at')
            c.name: switch (raw[c.name]) {
              null => null,
              final v when c.type == DriftSqlType.dateTime => DateTime.parse(v as String).toUtc().toIso8601String(),
              final v when c.type == DriftSqlType.bool => v == 1,
              final String v when c.name == 'muscles' => jsonDecode(v),
              final v => v,
            },
      };

  /// Rows not yet pushed, across all tables.
  Future<int> pending() => watchPending().first;

  Stream<int> watchPending() => _db
      .customSelect(_tables.map((t) => 'select count(*) as n from ${t.actualTableName} where dirty = 1').join(' union all '),
          readsFrom: _tables.toSet())
      .watch()
      .map((rows) => rows.fold(0, (sum, r) => sum + r.read<int>('n')));

  /// Deletes the local copy, children first. Callers check [pending] is 0 first.
  Future<void> wipe() => _db.transaction(() async {
        for (final t in _tables.reversed) {
          await _db.delete(t).go();
        }
        await _db.delete(_db.syncCursors).go();
      });
}

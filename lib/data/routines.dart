import 'dart:async';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'catalog.dart';
import 'db.dart';

const _uuid = Uuid();

/// Routines and their ordered exercise lists. Every write goes through [AppDb.save].
class RoutineStore {
  RoutineStore(this._db);
  final AppDb _db;

  Stream<List<Routine>> watchRoutines() => (_db.select(_db.routines)
        ..where((r) => r.deletedAt.isNull())
        ..orderBy([(r) => OrderingTerm(expression: r.name.lower())]))
      .watch();

  Future<String> create(String name) async {
    final id = _uuid.v4();
    await _db.save(_db.routines, {'id': id, 'name': name});
    return id;
  }

  Future<void> update(String id, {required String name, String? stickyNote}) =>
      _db.save(_db.routines, {'id': id, 'name': name, 'sticky_note': stickyNote});

  Future<void> delete(String id) async {
    final r = await (_db.select(_db.routines)..where((r) => r.id.equals(id))).getSingle();
    await _db.save(_db.routines, {'id': id, 'name': r.name, 'deleted_at': DateTime.now()});
  }

  /// Live exercises of routine [routineId], by position. Hidden once the routine is deleted.
  Stream<List<RoutineExercise>> watchExercises(String routineId) {
    final q = _db.select(_db.routineExercises).join(
        [innerJoin(_db.routines, _db.routines.id.equalsExp(_db.routineExercises.routineId))])
      ..where(_db.routineExercises.routineId.equals(routineId) &
          _db.routineExercises.deletedAt.isNull() &
          _db.routines.deletedAt.isNull())
      ..orderBy([OrderingTerm(expression: _db.routineExercises.position)]);
    return q.map((r) => r.readTable(_db.routineExercises)).watch();
  }

  /// Appends [entry]; a library entry without a row gets one with id [libraryRowId].
  Future<void> add(String routineId, CatalogEntry entry) => _db.transaction(() async {
        final exerciseId = await Catalog(_db).rowIdFor(entry);
        final items = await watchExercises(routineId).first;
        await _db.save(_db.routineExercises,
            {'id': _uuid.v4(), 'routine_id': routineId, 'exercise_id': exerciseId, 'position': items.length});
      });

  /// Swaps routine exercise [id] with its neighbour [delta] (-1 up, +1 down). No-op at the ends.
  Future<void> move(String id, int delta) => _edit(id, (items, i) {
        final j = i + delta;
        if (j < 0 || j >= items.length) return;
        items.insert(j, items.removeAt(i));
      });

  /// Soft-deletes routine exercise [id] and closes the gap.
  Future<void> remove(String id) => _edit(id, (items, i) async {
        final e = items.removeAt(i);
        await _save(e, e.position, deleted: true);
      });

  Future<void> _edit(String id, FutureOr<void> Function(List<RoutineExercise>, int) change) =>
      _db.transaction(() async {
        final row = await (_db.select(_db.routineExercises)..where((e) => e.id.equals(id))).getSingle();
        final items = [...await watchExercises(row.routineId).first];
        await change(items, items.indexWhere((e) => e.id == id));
        for (final (i, e) in items.indexed) {
          if (e.position != i) await _save(e, i);
        }
      });

  Future<void> _save(RoutineExercise e, int position, {bool deleted = false}) => _db.save(_db.routineExercises, {
        'id': e.id,
        'routine_id': e.routineId,
        'exercise_id': e.exerciseId,
        'position': position,
        if (deleted) 'deleted_at': DateTime.now(),
      });
}

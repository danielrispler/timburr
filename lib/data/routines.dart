import 'dart:async';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'catalog.dart';
import 'db.dart';

const _uuid = Uuid();

/// One planned set. A null weight means "use last session's".
typedef PlannedSet = ({double? weightKg, int? reps, int? durationSec});

/// A routine's exercises in order, each with its planned sets.
typedef Plan = List<({String exerciseId, String? backupExerciseId, List<PlannedSet> sets})>;

/// What a newly added exercise starts with: 3 x 10 reps, or 3 x 30 s when timed.
List<PlannedSet> defaultSets(String? loadType) =>
    List.filled(3, loadType == 'timed' ? (weightKg: null, reps: null, durationSec: 30) : (weightKg: null, reps: 10, durationSec: null));

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

  /// Copies routine [id] with its exercises and planned sets as "`name` copy". Returns the new id.
  Future<String> duplicate(String id) => _db.transaction(() async {
        final r = await (_db.select(_db.routines)..where((r) => r.id.equals(id))).getSingle();
        final copy = await create('${r.name} copy');
        await update(copy, name: '${r.name} copy', stickyNote: r.stickyNote);
        await _writePlan(copy, await plan(id));
        return copy;
      });

  /// Soft-deletes the routine with its exercises and planned sets.
  Future<void> delete(String id) => _db.transaction(() async {
        await replacePlan(id, const []);
        final r = await (_db.select(_db.routines)..where((r) => r.id.equals(id))).getSingle();
        await _db.save(_db.routines, {'id': id, 'name': r.name, 'deleted_at': DateTime.now()});
      });

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

  /// Appends [entry] with [defaultSets]; a library entry without a row gets one with id [libraryRowId].
  /// Returns the routine exercise id.
  Future<String> add(String routineId, CatalogEntry entry) => _db.transaction(() async {
        final exerciseId = await Catalog(_db).rowIdFor(entry);
        final items = await watchExercises(routineId).first;
        return _append(routineId, exerciseId, items.length, defaultSets(entry.loadType));
      });

  /// Sets or clears ([entry] null) the backup exercise of routine exercise [routineExerciseId].
  Future<void> setBackup(String routineExerciseId, CatalogEntry? entry) => _db.transaction(() async {
        final e = await (_db.select(_db.routineExercises)..where((e) => e.id.equals(routineExerciseId))).getSingle();
        await _db.save(_db.routineExercises, {
          'id': e.id,
          'routine_id': e.routineId,
          'exercise_id': e.exerciseId,
          'position': e.position,
          'backup_exercise_id': entry == null ? null : await Catalog(_db).rowIdFor(entry),
        });
      });

  Future<String> _append(String routineId, String exerciseId, int position, List<PlannedSet> sets,
      {String? backupExerciseId}) async {
    final id = _uuid.v4();
    await _db.save(_db.routineExercises, {
      'id': id,
      'routine_id': routineId,
      'exercise_id': exerciseId,
      'backup_exercise_id': backupExerciseId,
      'position': position,
    });
    await saveSets(id, sets);
    return id;
  }

  /// Live planned sets of routine exercise [routineExerciseId], by number.
  Stream<List<RoutineSet>> watchSets(String routineExerciseId) => (_db.select(_db.routineSets)
        ..where((s) => s.routineExerciseId.equals(routineExerciseId) & s.deletedAt.isNull())
        ..orderBy([(s) => OrderingTerm(expression: s.setNumber)]))
      .watch();

  /// Replaces the planned sets: rows are reused by position, extras soft-deleted.
  Future<void> saveSets(String routineExerciseId, List<PlannedSet> sets) => _db.transaction(() async {
        final old = await watchSets(routineExerciseId).first;
        for (var i = 0; i < sets.length || i < old.length; i++) {
          await _db.save(_db.routineSets, {
            'id': i < old.length ? old[i].id : _uuid.v4(),
            'routine_exercise_id': routineExerciseId,
            'set_number': i + 1,
            if (i < sets.length) ...{
              'weight_kg': sets[i].weightKg,
              'reps': sets[i].reps,
              'duration_sec': sets[i].durationSec,
            } else
              'deleted_at': DateTime.now(),
          });
        }
      });

  /// The routine's live exercises with their planned sets; empty when the routine is deleted.
  Future<Plan> plan(String routineId) async => [
        for (final e in await watchExercises(routineId).first)
          (
            exerciseId: e.exerciseId,
            backupExerciseId: e.backupExerciseId,
            sets: [
              for (final s in await watchSets(e.id).first) (weightKg: s.weightKg, reps: s.reps, durationSec: s.durationSec)
            ],
          ),
      ];

  /// Soft-deletes the routine's exercises and sets, then writes [plan] in their place.
  Future<void> replacePlan(String routineId, Plan plan) => _db.transaction(() async {
        for (final e in await watchExercises(routineId).first) {
          await _save(e, e.position, deleted: true);
        }
        await _writePlan(routineId, plan);
      });

  Future<void> _writePlan(String routineId, Plan plan) async {
    for (final (i, p) in plan.indexed) {
      await _append(routineId, p.exerciseId, i, p.sets, backupExerciseId: p.backupExerciseId);
    }
  }

  /// Moves routine exercise [id] to index [to] (as after removal), renumbering the rest.
  Future<void> reorder(String id, int to) => _edit(id, (items, i) => items.insert(to.clamp(0, items.length - 1), items.removeAt(i)));

  /// Swaps routine exercise [id] with its neighbour [delta] (-1 up, +1 down). No-op at the ends.
  Future<void> move(String id, int delta) => _edit(id, (items, i) {
        final j = i + delta;
        if (j < 0 || j >= items.length) return;
        items.insert(j, items.removeAt(i));
      });

  /// Soft-deletes routine exercise [id] with its sets and closes the gap.
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

  Future<void> _save(RoutineExercise e, int position, {bool deleted = false}) async {
    if (deleted) await saveSets(e.id, const []);
    await _db.save(_db.routineExercises, {
        'id': e.id,
        'routine_id': e.routineId,
        'exercise_id': e.exerciseId,
        'position': position,
        if (deleted) 'deleted_at': DateTime.now(),
      });
  }
}

/// "3 sets • 10 reps • 60 kg" from the first set; seconds for timed sets.
String planSummary(List<RoutineSet> sets) {
  if (sets.isEmpty) return 'No sets';
  final s = sets.first;
  return [
    '${sets.length} ${sets.length == 1 ? 'set' : 'sets'}',
    if (s.durationSec != null) '${s.durationSec} s' else if (s.reps != null) '${s.reps} reps',
    if (s.weightKg != null) '${s.weightKg == s.weightKg!.roundToDouble() ? s.weightKg!.toInt() : s.weightKg} kg',
  ].join(' • ');
}

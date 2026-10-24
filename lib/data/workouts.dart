import 'dart:async';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'catalog.dart';
import 'db.dart';
import 'routines.dart';

const _uuid = Uuid();

/// Step sizes for the set-row steppers.
const kgStep = 2.5, repStep = 1, secStep = 5;

/// [value] moved by [delta], never below 0. An empty field counts as 0.
num stepped(num? value, num delta) {
  final v = (value ?? 0) + delta;
  return v < 0 ? 0 : v;
}

/// A strength workout session: its exercises and sets. Every edit is saved at once through [AppDb.save].
class WorkoutStore {
  WorkoutStore(this._db, {this.onFinished});
  final AppDb _db;

  /// Called after [finish]; main wires it to sync.
  final Future<void> Function()? onFinished;

  /// Starts a workout now; from [routineId], its exercises are copied in order. Returns its id.
  Future<String> start({String? routineId}) => _db.transaction(() async {
        final id = _uuid.v4();
        await _db.save(_db.workouts, {'id': id, 'routine_id': routineId, 'started_at': DateTime.now()});
        if (routineId != null) {
          for (final (i, e) in (await RoutineStore(_db).watchExercises(routineId).first).indexed) {
            await _db.save(_db.workoutExercises,
                {'id': _uuid.v4(), 'workout_id': id, 'exercise_id': e.exerciseId, 'position': i});
          }
        }
        return id;
      });

  /// The in-progress workout to resume, if any (latest started wins).
  Future<Workout?> active() => watchActive().first;

  Stream<Workout?> watchActive() => (_db.select(_db.workouts)
        ..where((w) => w.finishedAt.isNull() & w.deletedAt.isNull())
        ..orderBy([(w) => OrderingTerm.desc(w.startedAt)])
        ..limit(1))
      .watchSingleOrNull();

  Stream<Workout> watchWorkout(String id) =>
      (_db.select(_db.workouts)..where((w) => w.id.equals(id))).watchSingle();

  Future<void> setStartedAt(String id, DateTime at) => _saveWorkout(id, (w) => w.copyWith(startedAt: at));
  Future<void> setNotes(String id, String? notes) => _saveWorkout(id, (w) => w.copyWith(notes: Value(notes)));

  Future<void> finish(String id) async {
    await _saveWorkout(id, (w) => w.copyWith(finishedAt: Value(DateTime.now())));
    await onFinished?.call();
  }

  /// Soft-deletes the workout with its exercises and sets, so each delete syncs.
  Future<void> discard(String id) => _db.transaction(() async {
        final now = DateTime.now();
        for (final e in await watchExercises(id).first) {
          for (final s in await watchSets(e.id).first) {
            await updateSet(s.copyWith(deletedAt: Value(now)));
          }
          await saveExercise(e.copyWith(deletedAt: Value(now)));
        }
        await _saveWorkout(id, (w) => w.copyWith(deletedAt: Value(now)));
      });

  /// Finished, non-deleted workouts, newest first.
  Stream<List<Workout>> watchHistory() => (_db.select(_db.workouts)
        ..where((w) => w.finishedAt.isNotNull() & w.deletedAt.isNull())
        ..orderBy([(w) => OrderingTerm.desc(w.startedAt)]))
      .watch();

  Future<void> _saveWorkout(String id, Workout Function(Workout) change) async {
    final w = change(await (_db.select(_db.workouts)..where((w) => w.id.equals(id))).getSingle());
    await _db.save(_db.workouts, {
      'id': w.id,
      'routine_id': w.routineId,
      'started_at': w.startedAt,
      'finished_at': w.finishedAt,
      'notes': w.notes,
      'deleted_at': w.deletedAt,
    });
  }

  Stream<List<WorkoutExercise>> watchExercises(String workoutId) => (_db.select(_db.workoutExercises)
        ..where((e) => e.workoutId.equals(workoutId) & e.deletedAt.isNull())
        ..orderBy([(e) => OrderingTerm(expression: e.position)]))
      .watch();

  Future<void> addExercise(String workoutId, CatalogEntry entry) => _db.transaction(() async {
        final exerciseId = await exerciseRowId(_db, entry);
        final items = await watchExercises(workoutId).first;
        await _db.save(_db.workoutExercises,
            {'id': _uuid.v4(), 'workout_id': workoutId, 'exercise_id': exerciseId, 'position': items.length});
      });

  /// Swaps workout exercise [id] with its neighbour [delta] (-1 up, +1 down). No-op at the ends.
  Future<void> move(String id, int delta) => _edit(id, (items, i) {
        final j = i + delta;
        if (j < 0 || j >= items.length) return;
        items.insert(j, items.removeAt(i));
      });

  /// Soft-deletes workout exercise [id] and closes the gap.
  Future<void> remove(String id) => _edit(id, (items, i) async {
        final e = items.removeAt(i);
        await saveExercise(e.copyWith(deletedAt: Value(DateTime.now())));
      });

  Future<void> _edit(String id, FutureOr<void> Function(List<WorkoutExercise>, int) change) =>
      _db.transaction(() async {
        final row = await (_db.select(_db.workoutExercises)..where((e) => e.id.equals(id))).getSingle();
        final items = [...await watchExercises(row.workoutId).first];
        await change(items, items.indexWhere((e) => e.id == id));
        for (final (i, e) in items.indexed) {
          if (e.position != i) await saveExercise(e.copyWith(position: i));
        }
      });

  /// Full-row save, for notes and superset edits too.
  Future<void> saveExercise(WorkoutExercise e) => _db.save(_db.workoutExercises, {
        'id': e.id,
        'workout_id': e.workoutId,
        'exercise_id': e.exerciseId,
        'position': e.position,
        'notes': e.notes,
        'superset_with_next': e.supersetWithNext,
        'deleted_at': e.deletedAt,
      });

  Stream<List<WorkoutSet>> watchSets(String workoutExerciseId) => (_db.select(_db.workoutSets)
        ..where((s) => s.workoutExerciseId.equals(workoutExerciseId) & s.deletedAt.isNull())
        ..orderBy([(s) => OrderingTerm(expression: s.setNumber)]))
      .watch();

  /// Appends a set prefilled from the previous set here, else from last time's same-numbered (or last) set.
  Future<WorkoutSet> addSet(String workoutExerciseId) => _db.transaction(() async {
        final sets = await watchSets(workoutExerciseId).first;
        var from = sets.lastOrNull;
        if (from == null) {
          final we = await (_db.select(_db.workoutExercises)..where((e) => e.id.equals(workoutExerciseId))).getSingle();
          from = (await lastTime(we.exerciseId, excludeWorkoutId: we.workoutId)).firstOrNull;
        }
        final s = WorkoutSet(
          id: _uuid.v4(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          dirty: 1,
          workoutExerciseId: workoutExerciseId,
          setNumber: sets.length + 1,
          weightKg: from?.weightKg,
          reps: from?.reps,
          durationSec: from?.durationSec,
          done: false,
        );
        await updateSet(s);
        return s;
      });

  Future<void> updateSet(WorkoutSet s) => _db.save(_db.workoutSets, {
        'id': s.id,
        'workout_exercise_id': s.workoutExerciseId,
        'set_number': s.setNumber,
        'weight_kg': s.weightKg,
        'reps': s.reps,
        'duration_sec': s.durationSec,
        'done': s.done,
        'deleted_at': s.deletedAt,
      });

  /// Soft-deletes [s] and renumbers the sets after it.
  Future<void> removeSet(WorkoutSet s) => _db.transaction(() async {
        await updateSet(s.copyWith(deletedAt: Value(DateTime.now())));
        for (final (i, x) in (await watchSets(s.workoutExerciseId).first).indexed) {
          if (x.setNumber != i + 1) await updateSet(x.copyWith(setNumber: i + 1));
        }
      });

  /// Sets of [exerciseId] in the latest live workout started before [excludeWorkoutId].
  Future<List<WorkoutSet>> lastTime(String exerciseId, {required String excludeWorkoutId}) async =>
      (await previousSessions(exerciseId, excludeWorkoutId: excludeWorkoutId, limit: 1)).firstOrNull ?? [];

  /// [exerciseId]'s sets per live workout started before [excludeWorkoutId], newest first.
  Future<List<List<WorkoutSet>>> previousSessions(String exerciseId,
      {required String excludeWorkoutId, int? limit}) async {
    final current = await (_db.select(_db.workouts)..where((w) => w.id.equals(excludeWorkoutId))).getSingle();
    final we = _db.workoutExercises, w = _db.workouts;
    final rows = await (_db.select(we).join([innerJoin(w, w.id.equalsExp(we.workoutId))])
          ..where(we.exerciseId.equals(exerciseId) &
              we.deletedAt.isNull() &
              w.deletedAt.isNull() &
              w.id.equals(excludeWorkoutId).not() &
              w.startedAt.isSmallerThanValue(current.startedAt))
          ..orderBy([OrderingTerm.desc(w.startedAt)])
          ..limit(limit ?? -1))
        .map((r) => r.readTable(we))
        .get();
    return [for (final e in rows) await watchSets(e.id).first];
  }

  /// [exerciseId]'s sets per finished, live workout with its start time, oldest first.
  Future<List<(DateTime, List<WorkoutSet>)>> finishedSessions(String exerciseId) async {
    final we = _db.workoutExercises, w = _db.workouts;
    final rows = await (_db.select(we).join([innerJoin(w, w.id.equalsExp(we.workoutId))])
          ..where(we.exerciseId.equals(exerciseId) & we.deletedAt.isNull() & w.deletedAt.isNull() & w.finishedAt.isNotNull())
          ..orderBy([OrderingTerm.asc(w.startedAt)]))
        .get();
    return [for (final r in rows) (r.readTable(w).startedAt, await watchSets(r.readTable(we).id).first)];
  }
}

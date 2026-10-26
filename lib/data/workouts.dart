import 'dart:async';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'catalog.dart';
import 'db.dart';
import 'health.dart';
import 'routines.dart';
import 'stats.dart';

const _uuid = Uuid();

/// Step sizes for the set-row steppers.
const kgStep = 2.5, repStep = 1, secStep = 5;

/// [value] moved by [delta], never below 0. An empty field counts as 0.
num stepped(num? value, num delta) {
  final v = (value ?? 0) + delta;
  return v < 0 ? 0 : v;
}

/// Rough length of a logged-after-the-fact workout: 3 min per set, at least 10 min.
Duration estimateDuration(int sets) => Duration(minutes: sets * 3 < 10 ? 10 : sets * 3);

/// Ordered cards split into supersets: a card with `supersetWithNext` joins the card after it. The last card's flag is ignored.
List<List<WorkoutExercise>> supersetGroups(List<WorkoutExercise> items) {
  final groups = <List<WorkoutExercise>>[];
  for (final (i, e) in items.indexed) {
    if (i > 0 && items[i - 1].supersetWithNext) {
      groups.last.add(e);
    } else {
      groups.add([e]);
    }
  }
  return groups;
}

/// One row of a card: [set] of the card's [exercise]-th exercise. [endsRound] marks where rest is offered.
typedef SupersetRow = ({int exercise, WorkoutSet set, bool endsRound});

/// Interleaves the sets of a superset's exercises by round (A1, B1, A2, B2); a drop set stays under its set.
/// For a single exercise each set (with its drops) is a round.
List<SupersetRow> supersetRows(List<List<WorkoutSet>> perExercise) {
  // Each exercise's sets chunked into rounds: a set plus the drop sets after it.
  final rounds = [
    for (final sets in perExercise)
      sets.fold(<List<WorkoutSet>>[], (r, s) => r..add(s.isDrop && r.isNotEmpty ? (r.removeLast()..add(s)) : [s]))
  ];
  final out = <SupersetRow>[];
  for (var n = 0; rounds.any((r) => n < r.length); n++) {
    final round = [
      for (final (i, r) in rounds.indexed)
        if (n < r.length) for (final s in r[n]) (exercise: i, set: s)
    ];
    for (final (k, x) in round.indexed) {
      out.add((exercise: x.exercise, set: x.set, endsRound: k == round.length - 1));
    }
  }
  return out;
}

/// A strength workout session: its exercises and sets. Every edit is saved at once through [AppDb.save].
class WorkoutStore {
  WorkoutStore(this._db, {this.onFinished});
  final AppDb _db;

  /// Called after [finish]; main wires it to sync.
  final Future<void> Function()? onFinished;

  /// Starts a workout at [at] (default now). From [routineId], its exercises and planned sets are copied in order;
  /// a planned set without weight takes last session's. With [done], every set is done and the workout is
  /// finished after [estimateDuration], for logging one after the fact. Returns its id.
  Future<String> start({String? routineId, DateTime? at, bool done = false}) => _db.transaction(() async {
        final id = _uuid.v4();
        final startedAt = at ?? DateTime.now();
        await _db.save(_db.workouts, {'id': id, 'routine_id': routineId, 'started_at': startedAt});
        var count = 0;
        for (final (i, p) in (routineId == null ? const <Never>[] : await RoutineStore(_db).plan(routineId)).indexed) {
          final weId = _uuid.v4();
          await _db.save(_db.workoutExercises, {
            'id': weId,
            'workout_id': id,
            'exercise_id': p.exerciseId,
            'backup_exercise_id': p.backupExerciseId,
            'position': i,
          });
          final last = (await lastTime(p.exerciseId, excludeWorkoutId: id)).where((s) => !s.isDrop).toList();
          for (final (n, s) in p.sets.indexed) {
            await _db.save(_db.workoutSets, {
              'id': _uuid.v4(),
              'workout_exercise_id': weId,
              'set_number': n + 1,
              'weight_kg': s.weightKg ?? (n < last.length ? last[n] : last.lastOrNull)?.weightKg,
              'reps': s.reps,
              'duration_sec': s.durationSec,
              'done': done,
            });
          }
          count += p.sets.length;
        }
        if (done) await _saveWorkout(id, (w) => w.copyWith(finishedAt: Value(startedAt.add(estimateDuration(count)))));
        return id;
      });

  /// True when the workout came from a live routine and its exercises or sets now differ from that routine's plan.
  Future<bool> templateChanged(String workoutId) async {
    final routineId = (await watchWorkout(workoutId).first).routineId;
    if (routineId == null || !await _routineLive(routineId)) return false;
    final a = await RoutineStore(_db).plan(routineId), b = await _plan(workoutId);
    // A planned set without weight was prefilled from last session, so any weight there still matches.
    bool same(PlannedSet p, PlannedSet w) =>
        p.reps == w.reps && p.durationSec == w.durationSec && (p.weightKg == null || p.weightKg == w.weightKg);
    return a.length != b.length ||
        [
          for (final (i, x) in a.indexed)
            x.exerciseId != b[i].exerciseId ||
                x.sets.length != b[i].sets.length ||
                [for (final (j, s) in x.sets.indexed) !same(s, b[i].sets[j])].any((d) => d)
        ].any((d) => d);
  }

  /// Overwrites the workout's routine with what was done in this workout. A planned set without weight
  /// (matched by exercise position and set number) stays without weight, so it keeps taking last session's.
  Future<void> updateTemplate(String workoutId) async {
    final routineId = (await watchWorkout(workoutId).first).routineId;
    if (routineId == null) return;
    final routines = RoutineStore(_db), old = await routines.plan(routineId);
    bool unpinned(int i, int j) => i < old.length && j < old[i].sets.length && old[i].sets[j].weightKg == null;
    await routines.replacePlan(routineId, [
      for (final (i, e) in (await _plan(workoutId)).indexed)
        (
          exerciseId: e.exerciseId,
          backupExerciseId: e.backupExerciseId,
          sets: [
            for (final (j, s) in e.sets.indexed)
              unpinned(i, j) ? (weightKg: null, reps: s.reps, durationSec: s.durationSec) : s
          ],
        ),
    ]);
  }

  Future<bool> _routineLive(String id) async =>
      await (_db.select(_db.routines)..where((r) => r.id.equals(id) & r.deletedAt.isNull())).getSingleOrNull() != null;

  Future<Plan> _plan(String workoutId) async => [
        for (final e in await watchExercises(workoutId).first)
          (
            exerciseId: e.exerciseId,
            backupExerciseId: e.backupExerciseId,
            sets: [
              for (final s in await watchSets(e.id).first)
                if (!s.isDrop) (weightKg: s.weightKg, reps: s.reps, durationSec: s.durationSec)
            ],
          ),
      ];

  /// The in-progress workout to resume, if any (latest started wins).
  Future<Workout?> active() => watchActive().first;

  Stream<Workout?> watchActive() => (_db.select(_db.workouts)
        ..where((w) => w.finishedAt.isNull() & w.deletedAt.isNull())
        ..orderBy([(w) => OrderingTerm.desc(w.startedAt)])
        ..limit(1))
      .watchSingleOrNull();

  Stream<Workout> watchWorkout(String id) =>
      (_db.select(_db.workouts)..where((w) => w.id.equals(id))).watchSingle();

  Future<String?> routineStickyNote(String routineId) async =>
      (await (_db.select(_db.routines)..where((r) => r.id.equals(routineId))).getSingleOrNull())?.stickyNote;

  Future<void> setStartedAt(String id, DateTime at) => _saveWorkout(
      id, (w) => w.copyWith(startedAt: at, finishedAt: Value(w.finishedAt?.add(at.difference(w.startedAt)))));
  Future<void> setNotes(String id, String? notes) => _saveWorkout(id, (w) => w.copyWith(notes: Value(notes)));
  Future<void> setHealth(String id, HealthStats h) => _saveWorkout(
      id,
      (w) => w.copyWith(
          avgHr: Value(h.avgHr),
          calories: Value(h.calories),
          activeSec: Value(h.activeSec),
          effort: Value(h.effort),
          cardioLoad: Value(h.cardioLoad)));

  Future<void> finish(String id) async {
    await _saveWorkout(id, (w) => w.copyWith(finishedAt: Value(DateTime.now())));
    unawaited(onFinished?.call()); // sync in the background
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
      'avg_hr': w.avgHr,
      'calories': w.calories,
      'active_sec': w.activeSec,
      'effort': w.effort,
      'cardio_load': w.cardioLoad,
      'deleted_at': w.deletedAt,
    });
  }

  Stream<List<WorkoutExercise>> watchExercises(String workoutId) => (_db.select(_db.workoutExercises)
        ..where((e) => e.workoutId.equals(workoutId) & e.deletedAt.isNull())
        ..orderBy([(e) => OrderingTerm(expression: e.position)]))
      .watch();

  Future<void> addExercise(String workoutId, CatalogEntry entry) => _db.transaction(() async {
        final exerciseId = await Catalog(_db).rowIdFor(entry);
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
        // A link into the removed card must not join its neighbours.
        if (i > 0 && items[i - 1].supersetWithNext) {
          await saveExercise(items[i - 1] = items[i - 1].copyWith(supersetWithNext: false));
        }
        await saveExercise(e.copyWith(deletedAt: Value(DateTime.now())));
      });

  Future<void> _edit(String id, FutureOr<void> Function(List<WorkoutExercise>, int) change) =>
      _db.transaction(() async {
        final row = await (_db.select(_db.workoutExercises)..where((e) => e.id.equals(id))).getSingle();
        final items = [...await watchExercises(row.workoutId).first];
        await change(items, items.indexWhere((e) => e.id == id));
        for (final (i, e) in items.indexed) {
          final link = e.supersetWithNext && i < items.length - 1; // the last card links to nothing
          if (e.position != i || e.supersetWithNext != link) {
            await saveExercise(e.copyWith(position: i, supersetWithNext: link));
          }
        }
      });

  /// Full-row save, for notes and superset edits too.
  Future<void> saveExercise(WorkoutExercise e) => _db.save(_db.workoutExercises, {
        'id': e.id,
        'workout_id': e.workoutId,
        'exercise_id': e.exerciseId,
        'backup_exercise_id': e.backupExerciseId,
        'position': e.position,
        'notes': e.notes,
        'superset_with_next': e.supersetWithNext,
        'deleted_at': e.deletedAt,
      });

  /// Swaps workout exercise [e] with its backup exercise. No-op without one.
  Future<void> swap(WorkoutExercise e) async {
    final b = e.backupExerciseId;
    if (b != null) await saveExercise(e.copyWith(exerciseId: b, backupExerciseId: Value(e.exerciseId)));
  }

  Stream<List<WorkoutSet>> watchSets(String workoutExerciseId) => (_db.select(_db.workoutSets)
        ..where((s) => s.workoutExerciseId.equals(workoutExerciseId) & s.deletedAt.isNull())
        ..orderBy([(s) => OrderingTerm(expression: s.setNumber)]))
      .watch();

  /// Appends a set prefilled from the previous set here, else from last time's same-numbered (or last) set.
  Future<WorkoutSet> addSet(String workoutExerciseId) => _db.transaction(() async {
        final sets = await watchSets(workoutExerciseId).first;
        final we = await (_db.select(_db.workoutExercises)..where((e) => e.id.equals(workoutExerciseId))).getSingle();
        final finished = (await watchWorkout(we.workoutId).first).finishedAt != null;
        final from = sets.lastOrNull ?? (await lastTime(we.exerciseId, excludeWorkoutId: we.workoutId)).firstOrNull;
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
          done: finished, // sets added to a finished workout count as done
          isDrop: false,
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
        'is_drop': s.isDrop,
        'deleted_at': s.deletedAt,
      });

  /// Inserts a drop set right after [after] at about 80% of its weight, same reps, and renumbers the rest.
  Future<void> addDrop(WorkoutSet after) => _db.transaction(() async {
        for (final x in await watchSets(after.workoutExerciseId).first) {
          if (x.setNumber > after.setNumber) await updateSet(x.copyWith(setNumber: x.setNumber + 1));
        }
        final kg = after.weightKg;
        await updateSet(after.copyWith(
          id: _uuid.v4(),
          setNumber: after.setNumber + 1,
          weightKg: Value(kg == null ? null : (kg * 0.8 / kgStep).round() * kgStep),
          done: false,
          isDrop: true,
        ));
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
    return _setsFor([for (final e in rows) e.id]);
  }

  /// Live sets of each of [ids], in order, loaded in one query.
  Future<List<List<WorkoutSet>>> _setsFor(List<String> ids) async {
    final sets = await (_db.select(_db.workoutSets)
          ..where((s) => s.workoutExerciseId.isIn(ids) & s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm(expression: s.setNumber)]))
        .get();
    final by = <String, List<WorkoutSet>>{for (final id in ids) id: []};
    for (final s in sets) {
      by[s.workoutExerciseId]!.add(s);
    }
    return [for (final id in ids) by[id]!];
  }

  /// Every live set of every finished, live workout, oldest workout first. Feeds the stats screens.
  Stream<List<LoggedSet>> watchLogged() {
    final s = _db.workoutSets, we = _db.workoutExercises, w = _db.workouts;
    return (_db.select(s).join([
      innerJoin(we, we.id.equalsExp(s.workoutExerciseId)),
      innerJoin(w, w.id.equalsExp(we.workoutId)),
    ])
          ..where(s.deletedAt.isNull() & we.deletedAt.isNull() & w.deletedAt.isNull() & w.finishedAt.isNotNull())
          ..orderBy([OrderingTerm.asc(w.startedAt), OrderingTerm.asc(we.position), OrderingTerm.asc(s.setNumber)]))
        .map((r) => (workout: r.readTable(w), exerciseId: r.readTable(we).exerciseId, set: r.readTable(s)))
        .watch();
  }

  /// [exerciseId]'s sets per finished, live workout with its start time, oldest first.
  Future<List<(DateTime, List<WorkoutSet>)>> finishedSessions(String exerciseId) async {
    final we = _db.workoutExercises, w = _db.workouts;
    final rows = await (_db.select(we).join([innerJoin(w, w.id.equalsExp(we.workoutId))])
          ..where(we.exerciseId.equals(exerciseId) & we.deletedAt.isNull() & w.deletedAt.isNull() & w.finishedAt.isNotNull())
          ..orderBy([OrderingTerm.asc(w.startedAt)]))
        .get();
    final sets = await _setsFor([for (final r in rows) r.readTable(we).id]);
    return [for (final (i, r) in rows.indexed) (r.readTable(w).startedAt, sets[i])];
  }
}

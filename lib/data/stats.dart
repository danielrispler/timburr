import 'db.dart';
import 'records.dart';

/// One set of a finished workout, with the workout and exercise it belongs to.
typedef LoggedSet = ({Workout workout, String exerciseId, WorkoutSet set});

/// Estimated best weight for [reps] reps from a 1RM: Epley run backwards.
double repMax(double oneRm, int reps) => reps <= 1 ? oneRm : oneRm / (1 + reps / 30);

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime mondayOf(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

/// Done-set volume per workout id.
Map<String, double> volumeByWorkout(Iterable<LoggedSet> rows) {
  final out = <String, double>{};
  for (final r in rows) {
    out[r.workout.id] = (out[r.workout.id] ?? 0) + sessionVolume([r.set]);
  }
  return out;
}

typedef Week = ({DateTime monday, int workouts, double volume});

/// The last [weeks] weeks up to [now], oldest first, empty weeks included.
List<Week> weekly(List<Workout> workouts, Map<String, double> volumes, DateTime now, {int weeks = 12}) {
  final first = mondayOf(now).subtract(Duration(days: 7 * (weeks - 1)));
  final out = [
    for (var i = 0; i < weeks; i++)
      (monday: DateTime(first.year, first.month, first.day + 7 * i), workouts: 0, volume: 0.0),
  ];
  for (final w in workouts) {
    final i = (dayOf(mondayOf(w.startedAt)).difference(first).inHours / 24 / 7).round();
    if (i < 0 || i >= weeks) continue;
    final o = out[i];
    out[i] = (monday: o.monday, workouts: o.workouts + 1, volume: o.volume + (volumes[w.id] ?? 0));
  }
  return out;
}

/// Weeks in a row with at least one session. The current streak still counts while this week is empty.
({int current, int longest}) weekStreaks(Iterable<DateTime> sessions, DateTime now) {
  final weeks = {for (final d in sessions) mondayOf(d)};
  if (weeks.isEmpty) return (current: 0, longest: 0);
  DateTime prev(DateTime m) => DateTime(m.year, m.month, m.day - 7);
  var longest = 0;
  for (final m in weeks) {
    if (weeks.contains(prev(m))) continue; // not a run start
    var n = 0;
    for (var x = m; weeks.contains(x); x = DateTime(x.year, x.month, x.day + 7)) {
      n++;
    }
    if (n > longest) longest = n;
  }
  var x = mondayOf(now);
  if (!weeks.contains(x)) x = prev(x);
  var current = 0;
  for (; weeks.contains(x); x = prev(x)) {
    current++;
  }
  return (current: current, longest: longest);
}

/// Sessions per calendar day.
Map<DateTime, int> dayCounts(Iterable<DateTime> sessions) {
  final out = <DateTime, int>{};
  for (final d in sessions) {
    out[dayOf(d)] = (out[dayOf(d)] ?? 0) + 1;
  }
  return out;
}

typedef Totals = ({int workouts, double volume, Duration time, double cardioKm, int sets});

Totals totals(List<Workout> workouts, Iterable<LoggedSet> rows, List<CardioData> cardio) => (
  workouts: workouts.length,
  volume: sessionVolume(rows.map((r) => r.set)),
  time:
      workouts.fold(Duration.zero, (t, w) => t + (w.finishedAt ?? w.startedAt).difference(w.startedAt)) +
      Duration(seconds: cardio.fold(0, (t, c) => t + c.durationSec)),
  cardioKm: cardio.fold(0.0, (t, c) => t + (c.distanceKm ?? 0)),
  sets: rows.where((r) => r.set.done).length,
);

/// Exercise ids by done-set count, most first, at most [n].
List<(String, int)> topExercises(Iterable<LoggedSet> rows, {int n = 5}) {
  final count = <String, int>{};
  for (final r in rows.where((r) => r.set.done)) {
    count[r.exerciseId] = (count[r.exerciseId] ?? 0) + 1;
  }
  return (count.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
      .take(n)
      .map((e) => (e.key, e.value))
      .toList();
}

typedef RoutineStat = ({String routineId, int count, DateTime last, Duration avg});

/// Per routine: times done, last start and average duration; most recently done first.
List<RoutineStat> routineStats(List<Workout> workouts) {
  final by = <String, List<Workout>>{};
  for (final w in workouts) {
    if (w.routineId case final id?) (by[id] ??= []).add(w);
  }
  final out = [
    for (final MapEntry(key: id, value: ws) in by.entries)
      (
        routineId: id,
        count: ws.length,
        last: ws.map((w) => w.startedAt).reduce((a, b) => a.isAfter(b) ? a : b),
        avg: ws.fold(Duration.zero, (t, w) => t + (w.finishedAt ?? w.startedAt).difference(w.startedAt)) ~/ ws.length,
      ),
  ];
  return out..sort((a, b) => b.last.compareTo(a.last));
}

/// One exercise's sets grouped per workout, oldest first.
Map<String, List<(Workout, List<WorkoutSet>)>> sessionsByExercise(Iterable<LoggedSet> rows) {
  final out = <String, List<(Workout, List<WorkoutSet>)>>{};
  for (final r in rows) {
    final list = out[r.exerciseId] ??= [];
    if (list.isEmpty || list.last.$1.id != r.workout.id) list.add((r.workout, []));
    list.last.$2.add(r.set);
  }
  return out;
}

typedef PrEvent = ({String exerciseId, Workout workout, double value});

/// Each session whose best set beats every earlier session on the load type's main metric.
/// The first session of an exercise is a baseline, not a PR.
List<PrEvent> prEvents(
  Map<String, List<(Workout, List<WorkoutSet>)>> sessions,
  String Function(String exerciseId) loadType,
) {
  final out = <PrEvent>[];
  for (final MapEntry(key: id, value: list) in sessions.entries) {
    final metric = setMetrics(loadType(id)).values.first;
    double? best;
    for (final (w, sets) in list) {
      final done = sets.where((s) => s.done);
      if (done.isEmpty) continue;
      final v = done.map(metric).reduce((a, b) => a > b ? a : b);
      if (best != null && v > best) out.add((exerciseId: id, workout: w, value: v));
      if (best == null || v > best) best = v;
    }
  }
  return out..sort((a, b) => b.workout.startedAt.compareTo(a.workout.startedAt));
}

/// Best e1RM in the last [weeks] against the [weeks] before, as a fraction (0.05 = +5%).
/// Null when either window has no done set.
double? e1rmTrend(List<(Workout, List<WorkoutSet>)> sessions, DateTime now, {int weeks = 12}) {
  final cut = now.subtract(Duration(days: 7 * weeks)), start = cut.subtract(Duration(days: 7 * weeks));
  double? best(bool Function(DateTime) inWindow) {
    final sets = [
      for (final (w, sets) in sessions)
        if (inWindow(w.startedAt)) ...sets.where((s) => s.done),
    ];
    return sets.isEmpty ? null : sets.map((s) => e1rm(s.weightKg ?? 0, s.reps ?? 0)).reduce((a, b) => a > b ? a : b);
  }

  final recent = best((d) => d.isAfter(cut)), before = best((d) => d.isAfter(start) && !d.isAfter(cut));
  return recent == null || before == null || before == 0 ? null : recent / before - 1;
}

/// Daniel's split, in order. Matched to routine names ignoring case and spaces.
// shortcut: hard-coded by routine name, so a rename drops it from the cycle; move to a routine field if the split changes.
const splitCycle = ['Lower A', 'Upper A', 'Lower B', 'Upper B'];

/// The next [splitCycle] name after the newest workout (newest first) whose routine is in it, else the first,
/// plus the id of the routine with that name, if one exists.
({String name, String? routineId}) nextInCycle(List<Workout> workouts, Map<String, String> routineNames) {
  String key(String s) => s.toLowerCase().replaceAll(' ', '');
  final keys = [for (final c in splitCycle) key(c)];
  var next = splitCycle.first;
  for (final w in workouts) {
    final i = keys.indexOf(key(routineNames[w.routineId] ?? ''));
    if (i >= 0) {
      next = splitCycle[(i + 1) % splitCycle.length];
      break;
    }
  }
  final id = routineNames.entries.where((e) => key(e.value) == key(next)).firstOrNull?.key;
  return (name: next, routineId: id);
}

/// Library ids of the main lifts, in the order Records lists them: squat, bench press, pull-up, shoulder press, deadlift.
// shortcut: hard-coded library ids, so a swap to another variant drops it to the alphabetical rest; move to a setting if that happens.
const mainLifts = ['0043', '0025', '0652', '1456', '0032'];

/// Main lifts first in [mainLifts] order, then the rest by name.
int byMainLiftThenName((String? libraryId, String name) a, (String? libraryId, String name) b) {
  int rank(String? id) => switch (mainLifts.indexOf(id ?? '')) {
    -1 => mainLifts.length,
    final i => i,
  };
  final r = rank(a.$1).compareTo(rank(b.$1));
  return r != 0 ? r : a.$2.compareTo(b.$2);
}

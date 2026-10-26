import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/records.dart';
import 'package:timburr/data/stats.dart';

var _n = 0;
Workout w(DateTime at, {String? routine, int minutes = 60}) => Workout(
  id: 'w${_n++}',
  createdAt: at,
  updatedAt: at,
  dirty: 0,
  routineId: routine,
  startedAt: at,
  finishedAt: at.add(Duration(minutes: minutes)),
);
WorkoutSet s(double kg, int reps, {bool done = true, bool drop = false}) => WorkoutSet(
  isDrop: drop,
  id: 's${_n++}',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  dirty: 0,
  workoutExerciseId: 'we',
  setNumber: 1,
  weightKg: kg,
  reps: reps,
  done: done,
);
List<LoggedSet> rows(Workout wk, String ex, List<WorkoutSet> sets) => [
  for (final x in sets) (workout: wk, exerciseId: ex, set: x),
];

void main() {
  test('repMax inverts Epley', () {
    expect(repMax(120, 1), 120);
    expect(repMax(120, 5), closeTo(102.86, 0.01));
  });

  test('weekly buckets the last weeks with empty ones and volumes', () {
    final now = DateTime(2026, 10, 25); // Sunday
    final a = w(DateTime(2026, 10, 20)), b = w(DateTime(2026, 10, 13)), old = w(DateTime(2026, 1, 1));
    final weeks = weekly([a, b, old], {a.id: 1000, b.id: 500}, now, weeks: 3);
    expect([for (final x in weeks) x.monday], [DateTime(2026, 10, 5), DateTime(2026, 10, 12), DateTime(2026, 10, 19)]);
    expect([for (final x in weeks) x.workouts], [0, 1, 1]);
    expect(weeks.last.volume, 1000);
  });

  test('week streaks: current survives an empty current week; longest finds the best run', () {
    final now = DateTime(2026, 10, 22);
    final days = [
      DateTime(2026, 10, 13),
      DateTime(2026, 10, 6),
      DateTime(2026, 9, 1),
      DateTime(2026, 8, 25),
      DateTime(2026, 8, 18),
      DateTime(2026, 8, 11),
    ];
    expect(weekStreaks(days, now), (current: 2, longest: 4));
    expect(weekStreaks([DateTime(2026, 9, 1)], now).current, 0);
    expect(weekStreaks([], now), (current: 0, longest: 0));
  });

  test('routine stats count, last date and average duration', () {
    final r = routineStats([
      w(DateTime(2026, 1, 1), routine: 'A', minutes: 40),
      w(DateTime(2026, 2, 1), routine: 'A', minutes: 60),
      w(DateTime(2026, 3, 1)),
    ]);
    expect(r.single.count, 2);
    expect(r.single.last, DateTime(2026, 2, 1));
    expect(r.single.avg, const Duration(minutes: 50));
  });

  test('PR events skip the baseline and only count strict improvements', () {
    final w1 = w(DateTime(2026, 1, 1)), w2 = w(DateTime(2026, 1, 8)), w3 = w(DateTime(2026, 1, 15));
    final all = [
      ...rows(w1, 'bench', [s(100, 5)]),
      ...rows(w2, 'bench', [s(100, 5), s(200, 5, done: false)]),
      ...rows(w3, 'bench', [s(105, 5)]),
    ];
    final prs = prEvents(sessionsByExercise(all), (_) => 'weighted');
    expect([for (final p in prs) p.workout.id], [w3.id]);
    expect(topExercises(all), [('bench', 3)]);
    expect(volumeByWorkout(all)[w2.id], 500);
  });

  test('drop sets are never PRs and never count in e1rm trends', () {
    final w1 = w(DateTime(2026, 6, 1)), w2 = w(DateTime(2026, 10, 1));
    final all = [...rows(w1, 'bench', [s(100, 1)]), ...rows(w2, 'bench', [s(100, 1), s(60, 30, drop: true)])];
    expect(prEvents(sessionsByExercise(all), (_) => 'weighted'), isEmpty);
    expect(e1rmTrend(sessionsByExercise(all)['bench']!, DateTime(2026, 10, 25)), 0);
  });

  test('prBadges and prEvents agree on the same history', () {
    final w1 = w(DateTime(2026, 1, 1)), w2 = w(DateTime(2026, 1, 8));
    // more added weight, same reps: not a PR on bodyweight's main metric (reps)
    final cur = s(5, 10);
    final all = [...rows(w1, 'pullup', [s(0, 10)]), ...rows(w2, 'pullup', [cur])];
    expect(prEvents(sessionsByExercise(all), (_) => 'bodyweight'), isEmpty);
    expect(prBadges('bodyweight', [[s(0, 10)]], [cur]), isEmpty);
  });

  test('e1rm trend compares the last window with the one before', () {
    final now = DateTime(2026, 10, 25);
    final sessions = [
      (w(DateTime(2026, 6, 1)), [s(100, 1)]),
      (w(DateTime(2026, 10, 1)), [s(110, 1)]),
    ];
    expect(e1rmTrend(sessions, now), closeTo(0.10, 1e-9));
    expect(e1rmTrend(sessions.sublist(1), now), isNull);
  });

  test('nextInCycle follows the newest cycle workout, wraps and finds the routine', () {
    final names = {'a': 'lower a', 'b': 'UpperB', 'x': 'Arms', 'u': 'Upper A'};
    expect(nextInCycle([], names), (name: 'Lower A', routineId: 'a'));
    expect(nextInCycle([w(DateTime(2026, 10, 3), routine: 'x'), w(DateTime(2026, 10, 2), routine: 'a')], names), (
      name: 'Upper A',
      routineId: 'u',
    ));
    expect(nextInCycle([w(DateTime(2026, 10, 2), routine: 'u')], names), (name: 'Lower B', routineId: null));
    expect(nextInCycle([w(DateTime(2026, 10, 2), routine: 'b')], names).name, 'Lower A');
  });

  test('records order: squat, bench, pull-up, shoulder press, deadlift, then the rest by name', () {
    final list = [
      ('x', 'Zottman Curl'),
      ('0032', 'Barbell Deadlift'),
      (null, 'Arnold Press'),
      ('0043', 'Barbell Full Squat'),
      ('1456', 'Military Press'),
      ('0652', 'Pull-Up'),
      ('0025', 'Barbell Bench Press'),
    ]..sort(byMainLiftThenName);
    expect(
      [for (final e in list) e.$2],
      [
        'Barbell Full Squat',
        'Barbell Bench Press',
        'Pull-Up',
        'Military Press',
        'Barbell Deadlift',
        'Arnold Press',
        'Zottman Curl',
      ],
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/records.dart';

var _n = 0;
WorkoutSet s({double? kg, int? reps, int? sec, bool done = true, bool drop = false}) => WorkoutSet(
    id: 's${_n++}',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    dirty: 0,
    workoutExerciseId: 'we',
    setNumber: 1,
    weightKg: kg,
    reps: reps,
    durationSec: sec,
    done: done,
    isDrop: drop);

void main() {
  test('Epley e1RM; a 1-rep set is its weight', () {
    expect(e1rm(100, 1), 100);
    expect(e1rm(100, 10), closeTo(133.33, 0.01));
    expect(e1rm(100, 0), 0);
  });

  test('session volume sums done weight x reps', () {
    expect(sessionVolume([s(kg: 100, reps: 5), s(kg: 50, reps: 10), s(kg: 200, reps: 5, done: false)]), 1000);
  });

  test('records by load type use done sets only', () {
    final sessions = [
      [s(kg: 100, reps: 5), s(kg: 110, reps: 1)],
      [s(kg: 90, reps: 10), s(kg: 300, reps: 1, done: false)],
    ];
    final w = records('weighted', sessions);
    expect(w['weight'], 110);
    expect(w['e1rm'], closeTo(120, 0.01));
    expect(w['volume'], 900);
    expect(records('bodyweight', [
      [s(kg: 0, reps: 20), s(kg: 20, reps: 5)]
    ]), {'reps': 20, 'added': 20});
    expect(records('timed', [
      [s(sec: 60), s(sec: 90)]
    ]), {'duration': 90});
    expect(records('timed', []), isEmpty);
  });

  group('PR badge', () {
    final prev = [
      [s(kg: 100, reps: 5)]
    ];
    test('none on the first session', () {
      expect(prBadges('weighted', [], [s(kg: 100, reps: 5)]), isEmpty);
    });
    test('ties do not count', () {
      expect(prBadges('weighted', prev, [s(kg: 100, reps: 5)]), isEmpty);
    });
    test('beating a record badges only the best set', () {
      final a = s(kg: 105, reps: 5), b = s(kg: 110, reps: 5), c = s(kg: 90, reps: 5);
      expect(prBadges('weighted', prev, [a, b, c]), {b.id});
    });
    test('undone sets are ignored', () {
      expect(prBadges('weighted', prev, [s(kg: 200, reps: 5, done: false)]), isEmpty);
    });
    test('previous sessions with no done sets count as first time', () {
      expect(prBadges('weighted', [[s(kg: 50, reps: 5, done: false)]], [s(kg: 100, reps: 5)]), isEmpty);
    });
    test('bodyweight: more reps or more added weight', () {
      final p = [
        [s(kg: 0, reps: 10)]
      ];
      final x = s(kg: 0, reps: 11);
      expect(prBadges('bodyweight', p, [s(kg: 0, reps: 10), x]), {x.id});
      final y = s(kg: 5, reps: 3);
      expect(prBadges('bodyweight', p, [y]), {y.id});
    });
    test('timed: longer duration', () {
      final x = s(sec: 61);
      expect(prBadges('timed', [
        [s(sec: 60)]
      ], [s(sec: 60), x]), {x.id});
    });
  });

  test('chart series: one point per session with done sets', () {
    final a = DateTime(2026, 1, 1), b = DateTime(2026, 1, 2), c = DateTime(2026, 1, 3);
    final series = chartSeries([
      (a, [s(kg: 100, reps: 5), s(kg: 110, reps: 1), s(kg: 200, reps: 5, done: false)]),
      (b, [s(kg: 120, reps: 5, done: false)]),
      (c, [s(kg: 90, reps: 10)]),
    ]);
    expect(series.maxWeight, [(a, 110.0), (c, 90.0)]);
    expect([for (final (_, v) in series.e1rm) v.round()], [117, 120]);
    expect(series.volume, [(a, 610.0), (c, 900.0)]);
    expect(chartSeries([]).volume, isEmpty);
  });

  test('drop sets count toward volume but never set a per-set record or badge', () {
    final prev = [[s(kg: 50, reps: 5)]];
    final drop = s(kg: 40, reps: 20, drop: true);
    expect(records('bodyweight', [[drop]]), isEmpty);
    expect(prBadges('bodyweight', prev, [drop]), isEmpty);
    expect(records('weighted', [[s(kg: 100, reps: 5), s(kg: 80, reps: 5, drop: true)]]), {'e1rm': closeTo(116.67, 0.01), 'weight': 100, 'volume': 900});
  });
}

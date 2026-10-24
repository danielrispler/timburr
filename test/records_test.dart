import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/records.dart';

var _n = 0;
WorkoutSet s({double? kg, int? reps, int? sec, bool done = true}) => WorkoutSet(
    id: 's${_n++}',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    dirty: 0,
    workoutExerciseId: 'we',
    setNumber: 1,
    weightKg: kg,
    reps: reps,
    durationSec: sec,
    done: done);

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
}

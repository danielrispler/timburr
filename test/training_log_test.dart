import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/cardio.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/training_log.dart';

CardioData run(DateTime at, double km, {String type = 'run'}) => CardioData(
    id: '$at', createdAt: DateTime(2026), updatedAt: DateTime(2026), dirty: 0, editedFields: const [],
    type: type, startedAt: at, distanceKm: km, durationSec: 1800);

Workout workout(DateTime at, {DateTime? deleted}) => Workout(
    id: '$at', createdAt: DateTime(2026), updatedAt: DateTime(2026), dirty: 0, startedAt: at, deletedAt: deleted);

void main() {
  // Saturday 21 Nov 2026; its week starts Monday 16 Nov.
  final now = DateTime(2026, 11, 21, 9);

  test('a Run stored from a UTC time at 00:30 local reads back on its local day, in the log, totals and streak', () async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    final store = CardioStore(db);
    final at = DateTime(2026, 11, 10, 0, 30);
    await store.save(type: 'run', startedAt: at.toUtc(), distanceKm: 5, durationSec: 1800);
    final runs = await store.watchAll().first;
    expect(monthLog(runs, [], at).keys, [DateTime(2026, 11, 10)]);
    expect(monthWeeks(runs, at).firstWhere((w) => w.count > 0).monday, DateTime(2026, 11, 9));
    expect(weeklyStreak(runs, DateTime(2026, 11, 10, 9)), 1);
  });

  group('month log', () {
    test('puts each Run and Workout on its own day, only for the month shown', () {
      final r1 = run(DateTime(2026, 11, 3, 7), 5), r2 = run(DateTime(2026, 11, 3, 18), 3, type: 'interval');
      final w = workout(DateTime(2026, 11, 3, 12)), w2 = workout(DateTime(2026, 11, 30, 23, 30));
      final log = monthLog([r1, r2, run(DateTime(2026, 10, 31, 23), 9), run(DateTime(2026, 12, 1), 9)],
          [w, w2, workout(DateTime(2026, 11, 5), deleted: now), workout(DateTime(2026, 12, 1))], DateTime(2026, 11, 15));
      expect(log.keys.toSet(), {DateTime(2026, 11, 3), DateTime(2026, 11, 30)});
      expect(log[DateTime(2026, 11, 3)]!.runs, [r1, r2]);
      expect(log[DateTime(2026, 11, 3)]!.workouts, [w]);
      expect(log[DateTime(2026, 11, 30)]!.workouts, [w2]);
    });
  });

  group('month weeks', () {
    test('lists every week touching the month with the month Runs in it', () {
      final weeks = monthWeeks([
        run(DateTime(2026, 11, 2, 7), 5),
        run(DateTime(2026, 11, 4, 7), 3),
        run(DateTime(2026, 11, 20, 7), 10),
        run(DateTime(2026, 10, 31, 7), 50), // same week as 1 Nov, but another month
      ], DateTime(2026, 11, 1));
      // 1 Nov 2026 is a Sunday, so the first week starts Monday 26 Oct; the last starts Monday 30 Nov.
      expect(weeks.map((w) => w.monday), [DateTime(2026, 10, 26), DateTime(2026, 11, 2), DateTime(2026, 11, 9), DateTime(2026, 11, 16), DateTime(2026, 11, 23), DateTime(2026, 11, 30)]);
      expect(weeks.map((w) => w.km), [0, 8, 0, 10, 0, 0]);
      expect(weeks.map((w) => w.count), [0, 2, 0, 1, 0, 0]);
    });
  });

  group('weekly running streak', () {
    test('no Runs is 0', () => expect(weeklyStreak([], now), 0));

    test('counts consecutive weeks with a Run, this week included', () {
      final runs = [run(DateTime(2026, 11, 17), 5), run(DateTime(2026, 11, 10), 5), run(DateTime(2026, 11, 2), 5), run(DateTime(2026, 10, 12), 5)];
      expect(weeklyStreak(runs, now), 3);
    });

    test('an empty current week keeps the streak alive from last week', () {
      expect(weeklyStreak([run(DateTime(2026, 11, 10), 5), run(DateTime(2026, 11, 3), 5)], now), 2);
    });

    test('two empty weeks end it', () {
      expect(weeklyStreak([run(DateTime(2026, 11, 3), 5)], now), 0);
    });

    test('Sunday night and Monday morning fall in different weeks', () {
      expect(weeklyStreak([run(DateTime(2026, 11, 15, 23, 59), 5), run(DateTime(2026, 11, 16, 0, 1), 5)], now), 2);
    });

    test('Interval runs count; Runs after now and other types do not', () {
      expect(weeklyStreak([run(DateTime(2026, 11, 18), 3, type: 'interval')], now), 1);
      expect(weeklyStreak([run(DateTime(2026, 11, 18), 3, type: 'walk'), run(DateTime(2026, 11, 23), 3)], now), 0);
    });
  });

  test('dotSize grows with distance within a fixed range', () {
    expect(dotSize(0), 6);
    expect(dotSize(10), greaterThan(dotSize(5)));
    expect(dotSize(500), dotSize(42.2));
    expect(dotSize(null), 6);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/running.dart';

CardioData run(DateTime at, double km, int sec, {String type = 'run', DateTime? deleted}) => CardioData(
    id: '$at', createdAt: DateTime(2026), updatedAt: DateTime(2026), dirty: 0, editedFields: const [],
    type: type, startedAt: at, distanceKm: km, durationSec: sec, deletedAt: deleted);

void main() {
  // Saturday 21 Nov 2026; its week starts Monday 16 Nov.
  final now = DateTime(2026, 11, 21, 9);

  test('runsOf keeps outdoor and treadmill Runs, not other types or deleted rows', () {
    final all = [run(now, 5, 1500), run(now, 3, 1000, type: 'treadmill'), run(now, 4, 2000, type: 'walk'), run(now, 1, 300, deleted: now)];
    expect(runsOf(all).map((r) => r.type), ['run', 'treadmill']);
  });

  test('summary: week, 12-week average, month, year and all-time, treadmill included', () {
    final runs = [
      run(DateTime(2026, 11, 17, 7), 5, 1500), // this week
      run(DateTime(2026, 11, 18, 7), 3, 1200, type: 'treadmill'), // this week
      run(DateTime(2026, 11, 9, 7), 12, 3600), // last week: in the 12 weeks, this month
      run(DateTime(2026, 8, 24, 7), 24, 7200), // Monday 12 weeks back: in the 12 weeks
      run(DateTime(2026, 8, 23, 7), 100, 100), // the day before: out
      run(DateTime(2025, 3, 1, 7), 10, 3000), // last year
      run(DateTime(2026, 11, 22, 7), 50, 50), // after now: not counted
    ];
    final s = runSummary(runs, now);
    expect(s.week, (km: 8.0, sec: 2700, count: 2));
    expect(s.avgWeekKm12, (12 + 24) / 12);
    expect(s.month, (km: 20.0, sec: 6300, count: 3));
    expect(s.year, (km: 144.0, sec: 13600, count: 5));
    expect(s.all, (km: 154.0, sec: 16600, count: 6));
  });

  test('summary of no Runs is zeros', () {
    final s = runSummary([], now);
    expect((s.week.count, s.avgWeekKm12, s.all.km), (0, 0.0, 0.0));
  });

  group('distanceSeries', () {
    test('weeks are real: empty weeks between Runs are zero rows', () {
      final runs = [run(DateTime(2026, 11, 3), 5, 1), run(DateTime(2026, 11, 4), 2, 1), run(DateTime(2026, 11, 18), 7, 1)];
      final s = distanceSeries(runs, Period.week, now);
      expect(s.map((e) => e.start), [DateTime(2026, 11, 2), DateTime(2026, 11, 9), DateTime(2026, 11, 16)]);
      expect(s.map((e) => e.km), [7.0, 0.0, 7.0]);
    });
    test('last keeps the newest periods; a series with no Runs is the current period alone', () {
      final runs = [run(DateTime(2026, 1, 5), 5, 1)];
      expect(distanceSeries(runs, Period.month, now, last: 3).map((e) => e.start), [DateTime(2026, 9), DateTime(2026, 10), DateTime(2026, 11)]);
      expect(distanceSeries([], Period.year, now).map((e) => (e.start, e.km)), [(DateTime(2026), 0.0)]);
    });
    test('months and years cross year boundaries and include the empty years', () {
      final runs = [run(DateTime(2024, 12, 31), 10, 1), run(DateTime(2026, 1, 1), 4, 1)];
      final m = distanceSeries(runs, Period.month, now);
      expect(m.length, 24);
      expect((m.first.start, m.first.km), (DateTime(2024, 12), 10.0));
      expect((m[1].start, m[1].km), (DateTime(2025, 1), 0.0));
      final y = distanceSeries(runs, Period.year, now);
      expect(y.map((e) => (e.start.year, e.km)), [(2024, 10.0), (2025, 0.0), (2026, 4.0)]);
    });
    test('a Run in the week that began before 1 January belongs to that week', () {
      final s = distanceSeries([run(DateTime(2026, 1, 1), 5, 1)], Period.week, DateTime(2026, 1, 5));
      expect(s.map((e) => e.start), [DateTime(2025, 12, 29), DateTime(2026, 1, 5)]);
    });
  });

  test('parseRoute reads lat,lon pairs and skips junk', () {
    expect(parseRoute('32.08000,34.78000;32.08100,34.78200'), [(32.08, 34.78), (32.081, 34.782)]);
    expect(parseRoute('1,2;bad;3,4'), [(1.0, 2.0), (3.0, 4.0)]);
    expect(parseRoute(null), isEmpty);
  });
}

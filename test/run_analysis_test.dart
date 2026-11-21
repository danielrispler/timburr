import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/run_analysis.dart';
import 'package:timburr/data/track.dart';

/// [n] one-second points at [speed] m/s.
Track steady(int n, {double speed = 3, List<int?>? hr, List<double?>? altitude}) => Track(
      time: [for (var i = 0; i < n; i++) i],
      distance: [for (var i = 0; i < n; i++) i * speed],
      hr: hr,
      altitude: altitude,
    );

/// A track that stands still for [stop] seconds starting at second 20, one point per second, 3 m/s otherwise.
Track withStop(int stop, {int n = 70}) {
  var d = 0.0;
  final dist = <double?>[];
  for (var i = 0; i < n; i++) {
    if (i == 0 || i < 20 || i >= 20 + stop) d += i == 0 ? 0 : 3;
    dist.add(d);
  }
  return Track(time: [for (var i = 0; i < n; i++) i], distance: dist);
}

/// [n] one-second points heading north at 3 m/s, whose distance column says 0 then the Run's total on every point (as some Strava exports do).
Track totalOnEveryPoint(int n) {
  const mPerDegLat = 111194.93; // haversineM's earth radius
  return Track(
    time: [for (var i = 0; i < n; i++) i],
    distance: [for (var i = 0; i < n; i++) i == 0 ? 0 : (n - 1) * 3.0],
    lat: [for (var i = 0; i < n; i++) 32.8 + i * 3 / mPerDegLat],
    lon: [for (var i = 0; i < n; i++) 35.0],
  );
}

void main() {
  test('with GPS positions, splits, chart and Moving time measure distance along the positions, not a broken distance column', () {
    final t = totalOnEveryPoint(1001); // 3000 m
    expect(splitsPerKm(t).map((s) => s.paceSecPerKm.round()), [333, 333, 333]);
    expect(chartSeries(t, RunMetric.pace).last.$1, closeTo(3.0, 0.01));
    expect(autoPauseMovingSec(t), 1000);
  });

  test('a healthy distance column is kept, and GPS distance skips impossible jumps and is scaled to the Run\'s total', () {
    final healthy = Track(time: [0, 100, 200], distance: [0, 300, 600], lat: [32.8, 32.9, 33.0], lon: [35.0, 35.0, 35.0]);
    expect(splitsPerKm(healthy).map((s) => s.distanceM), [600]); // the column, not ~22 km of positions
    const m = 111194.93;
    final lat = [for (var i = 0; i < 1001; i++) 32.8 + i * 3 / m]..[500] = 0; // one stray point at the equator
    final t = Track(time: [for (var i = 0; i < 1001; i++) i], distance: [for (var i = 0; i < 1001; i++) i == 0 ? 0 : 1500.0], lat: lat, lon: [for (var i = 0; i < 1001; i++) 35.0]);
    expect(splitsPerKm(t).map((s) => s.distanceM.round()), [1000, 500]); // scaled to the file's 1500 m
  });

  test('the pace chart is smooth when the file updates its distance only every few seconds', () {
    final stale = Track(time: [for (var i = 0; i < 600; i++) i], distance: [for (var i = 0; i < 600; i++) (i ~/ 10) * 30.0]); // 3 m/s, updated every 10 s
    final paces = chartSeries(stale, RunMetric.pace).map((p) => p.$2);
    expect(paces.every((p) => (p - 333.3).abs() < 1), isTrue);
  });

  group('splitsPerKm', () {
    test('one split per km, with a last split when 100 m or more remain', () {
      final three = splitsPerKm(steady(1001)); // 3000 m
      expect(three.map((s) => s.distanceM), [1000, 1000, 1000]);
      expect(three.first.paceSecPerKm, closeTo(333.33, 0.01));
      final extra = splitsPerKm(steady(701)); // 2100 m
      expect(extra.map((s) => s.distanceM), [1000, 1000, 100]);
      expect(extra.last.paceSecPerKm, closeTo(333.33, 0.01));
      expect(splitsPerKm(steady(681)).map((s) => s.index), [1, 2]); // 40 m left over is dropped
    });

    test('km marks are interpolated between the points around them', () {
      final s = splitsPerKm(Track(time: [0, 100, 250], distance: [0, 600, 1500]));
      expect(s.map((x) => x.distanceM), [1000, 500]);
      expect(s[0].seconds, closeTo(166.67, 0.01));
      expect(s[1].paceSecPerKm, closeTo(166.67, 0.01));
    });

    test('average heart rate is per split', () {
      final s = splitsPerKm(steady(668, hr: [for (var i = 0; i < 668; i++) i <= 333 ? 140 : 160]));
      expect(s.map((x) => x.avgHr), [140, 160]);
      expect(splitsPerKm(steady(1001)).first.avgHr, isNull);
    });

    test('no distance or time, no splits', () {
      expect(splitsPerKm(Track(time: [0, 1])), isEmpty);
      expect(splitsPerKm(Track(distance: [0, 1000])), isEmpty);
    });
  });

  group('elevationGain', () {
    test('a steady climb adds up', () {
      expect(elevationGain(steady(21, altitude: [for (var i = 0; i < 21; i++) 100.0 + i])), closeTo(20, 3));
    });

    test('smoothing takes the jitter on flat ground out', () {
      final jitter = [for (var i = 0; i < 100; i++) i.isEven ? 100.0 : 101.0]; // 50 m of "climb" unsmoothed
      expect(elevationGain(steady(100, altitude: jitter)), lessThan(10));
    });

    test('descent adds nothing, and no altitude is null', () {
      expect(elevationGain(steady(21, altitude: [for (var i = 0; i < 21; i++) 120.0 - i])), 0);
      expect(elevationGain(steady(21)), isNull);
    });
  });

  group('autoPauseMovingSec', () {
    test('a run with no stops is all moving', () => expect(autoPauseMovingSec(steady(60)), 59));

    test('a stop of 5 s or more is taken out', () {
      expect(autoPauseMovingSec(withStop(10)), 69 - 10);
      expect(autoPauseMovingSec(withStop(5)), 69 - 5);
    });

    test('a stop shorter than 5 s counts as moving', () => expect(autoPauseMovingSec(withStop(4)), 69));

    test('slow walking below 0.5 m/s is a pause, 0.5 m/s is not', () {
      expect(autoPauseMovingSec(steady(30, speed: 0.4)), 0);
      expect(autoPauseMovingSec(steady(30, speed: 0.5)), 29);
    });

    test('a long gap between two points without movement is paused', () {
      expect(autoPauseMovingSec(Track(time: [0, 10, 310, 320], distance: [0, 30, 30, 60])), 20);
    });

    test('without time or distance there is no answer', () {
      expect(autoPauseMovingSec(Track(time: [0, 1])), isNull);
      expect(autoPauseMovingSec(Track()), isNull);
    });
  });

  group('chartSeries', () {
    test('pace over distance', () {
      final p = chartSeries(steady(300), RunMetric.pace);
      expect(p.first.$1, closeTo(0.1, 0.01)); // the first point with 100 m behind it
      expect(p.every((e) => (e.$2 - 333.33).abs() < 1), isTrue);
    });

    test('a stop is left out of the pace line', () {
      final p = chartSeries(Track(time: [0, 30, 1000, 1030, 1060], distance: [0, 100, 100, 200, 300]), RunMetric.pace);
      expect(p.map((e) => e.$2.round()), [300, 300]); // 100 m in 30 s; the window over the 970 s standing still is left out, then 100 m in 30 s again
    });

    test('heart rate and elevation over distance', () {
      final t = steady(10, hr: [for (var i = 0; i < 10; i++) i == 3 ? null : 150], altitude: [for (var i = 0; i < 10; i++) 50.0]);
      expect(chartSeries(t, RunMetric.hr), hasLength(9));
      expect(chartSeries(t, RunMetric.hr).last, (0.027, 150.0));
      expect(chartSeries(t, RunMetric.elevation).map((e) => e.$2).toSet(), {50.0});
    });

    test('a metric the track lacks is empty, and long tracks are thinned', () {
      expect(chartSeries(steady(10), RunMetric.hr), isEmpty);
      expect(chartSeries(steady(10), RunMetric.elevation), isEmpty);
      expect(chartSeries(steady(2000, hr: List.filled(2000, 150)), RunMetric.hr), hasLength(300));
    });
  });

  group('runTitle', () {
    String at(int h) => runTitle(DateTime(2026, 11, 10, h));
    test('hour boundaries', () {
      expect([for (final h in [4, 5, 10, 11, 13, 14, 17, 18, 21, 22, 0]) at(h)],
          ['Night run', 'Morning run', 'Morning run', 'Lunch run', 'Lunch run', 'Afternoon run', 'Afternoon run', 'Evening run', 'Evening run', 'Night run', 'Night run']);
    });
    test('treadmill', () => expect(runTitle(DateTime(2026, 1, 1, 7), treadmill: true), 'Morning treadmill run'));
  });
}

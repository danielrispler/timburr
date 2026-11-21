import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/recording.dart';
import 'package:timburr/data/route_match.dart';
import 'package:timburr/data/track.dart';

/// A fixture track: a loop of [radiusM] around ([lat0], [lon0]), [n] points, starting at angle [from] (radians), wobbling by up to [noiseM] (deterministic per [seed]),
/// run [clockwise] or not. Returned as the Run's stored route, the way the app keeps it.
String loop({double lat0 = 32.0, double lon0 = 34.8, double radiusM = 500, int n = 300, double from = 0, double noiseM = 0, int seed = 1, bool clockwise = true, double scale = 1}) {
  final rnd = Random(seed);
  const mPerDegLat = 111195.0;
  final mPerDegLon = mPerDegLat * cos(lat0 * pi / 180);
  final lat = <double>[], lon = <double>[];
  for (var i = 0; i < n; i++) {
    final a = from + (clockwise ? 1 : -1) * 2 * pi * i / (n - 1);
    final dx = radiusM * scale * cos(a) + (rnd.nextDouble() - 0.5) * 2 * noiseM, dy = radiusM * scale * sin(a) + (rnd.nextDouble() - 0.5) * 2 * noiseM;
    lat.add(lat0 + dy / mPerDegLat);
    lon.add(lon0 + dx / mPerDegLon);
  }
  return simplifyRoute(Track(time: [for (var i = 0; i < n; i++) i], lat: lat, lon: lon))!;
}

CardioData run(String id, DateTime at, String? route, {int sec = 1800, String type = 'run', DateTime? deleted}) => CardioData(
    id: id, createdAt: DateTime(2026), updatedAt: DateTime(2026), dirty: 0, editedFields: const [],
    type: type, startedAt: at, distanceKm: 3.1, durationSec: sec, route: route, deletedAt: deleted);

void main() {
  final d = DateTime.utc(2026, 5, 1);

  test('repeats of the same loop, with GPS wobble, form one group, oldest first', () {
    final groups = groupRuns([
      run('c', d.add(const Duration(days: 14)), loop(noiseM: 8, seed: 3)),
      run('a', d, loop(noiseM: 8, seed: 1)),
      run('b', d.add(const Duration(days: 7)), loop(noiseM: 8, seed: 2)),
    ]);
    expect(groups, hasLength(1));
    expect([for (final r in groups.single.runs) r.id], ['a', 'b', 'c']);
  });

  test('a different route stays out of the group', () {
    final groups = groupRuns([
      run('a', d, loop()),
      run('b', d.add(const Duration(days: 1)), loop(noiseM: 5, seed: 2)),
      run('other', d.add(const Duration(days: 2)), loop(lat0: 32.05, lon0: 34.85)), // elsewhere in town
      run('bigger', d.add(const Duration(days: 3)), loop(scale: 1.6)), // same start point, a longer loop
    ]);
    expect(groups, hasLength(1));
    expect([for (final r in groups.single.runs) r.id], ['a', 'b']);
  });

  test('the same streets run the other way are a different route', () {
    final groups = groupRuns([
      run('a', d, loop()),
      run('b', d.add(const Duration(days: 1)), loop()),
      run('rev', d.add(const Duration(days: 2)), loop(clockwise: false)),
      run('rev2', d.add(const Duration(days: 3)), loop(clockwise: false, noiseM: 5, seed: 4)),
    ]);
    expect(groups.map((g) => [for (final r in g.runs) r.id]), [['rev', 'rev2'], ['a', 'b']]);
  });

  test('a single Run, a Run without a route, a Treadmill run and a deleted Run make no group', () {
    final groups = groupRuns([
      run('a', d, loop()),
      run('none', d.add(const Duration(days: 1)), null),
      run('tm', d.add(const Duration(days: 2)), loop(), type: 'treadmill'),
      run('gone', d.add(const Duration(days: 3)), loop(), deleted: d),
    ]);
    expect(groups, isEmpty);
  });

  test('groupOf finds the group holding a Run', () {
    final runs = [run('a', d, loop()), run('b', d.add(const Duration(days: 1)), loop()), run('x', d.add(const Duration(days: 2)), loop(lat0: 33))];
    final groups = groupRuns(runs);
    expect(groupOf(groups, 'b')?.runs.map((r) => r.id), ['a', 'b']);
    expect(groupOf(groups, 'x'), isNull);
  });

  test('bigger groups come first, then the most recently run', () {
    final groups = groupRuns([
      run('p1', d, loop(lat0: 33)),
      run('p2', d.add(const Duration(days: 1)), loop(lat0: 33)),
      run('q1', d.add(const Duration(days: 2)), loop()),
      run('q2', d.add(const Duration(days: 3)), loop()),
      run('q3', d.add(const Duration(days: 4)), loop()),
    ]);
    expect(groups.map((g) => g.runs.length), [3, 2]);
  });
}

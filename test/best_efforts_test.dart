import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/best_efforts.dart';
import 'package:timburr/data/cardio.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/recording.dart';
import 'package:timburr/data/track.dart';

/// A track from (seconds, meters) points.
Track track(List<(int, double)> pts) => Track(time: [for (final p in pts) p.$1], distance: [for (final p in pts) p.$2]);

/// One point per [step] seconds at [speed] m/s for [secs] seconds.
List<(int, double)> steady(double speed, int secs, {int step = 1, int t0 = 0, double d0 = 0}) => [for (var s = 0; s <= secs; s += step) (t0 + s, d0 + s * speed)];

void main() {
  group('findBestEfforts', () {
    test('a steady pace gives that pace at every distance the track covers', () {
      final e = findBestEfforts(track(steady(4, 500)));
      expect(e.keys, [400, 1000, 1609]);
      expect(e[400], closeTo(100, 1e-6));
      expect(e[1000], closeTo(250, 1e-6));
      expect(e[1609], closeTo(1609.344 / 4, 1e-6));
    });

    test('the window edge is interpolated between points', () {
      // points 30 s apart: 1 km is reached at 250 s, between the points at 240 s (960 m) and 270 s (1080 m)
      final e = findBestEfforts(track(steady(4, 600, step: 30)));
      expect(e[1000], closeTo(250, 1e-6));
      expect(e[400], closeTo(100, 1e-6));
    });

    test('the fastest stretch is found wherever it is', () {
      // slow 2 m/s for 600 s, fast 5 m/s for 400 s (2000 m), slow again
      final pts = [...steady(2, 600), ...steady(5, 400, t0: 600, d0: 1200).skip(1), ...steady(2, 600, t0: 1000, d0: 3200).skip(1)];
      expect(findBestEfforts(track(pts))[1000], closeTo(200, 1e-6));
    });

    test('a window that starts at a point and ends between two is found', () {
      // 100 m slow, 150 m fast, then medium: the best 400 m starts at 100 m and ends mid-way in the last segment
      final e = findBestEfforts(track([(0, 0), (30, 100), (46, 250), (70, 480), (100, 740)]));
      expect(e[400], closeTo(70 + 30 * 20 / 260 - 30, 1e-6));
    });

    test('a window spanning a GPS gap over 30 s does not count', () {
      // 3 m/s, then a 60 s hole in which 750 m pass, then 3 m/s again
      final pts = [...steady(3, 450), (510, 2100.0), ...steady(3, 450, t0: 510, d0: 2100).skip(1)];
      final e = findBestEfforts(track(pts));
      expect(e[400], closeTo(400 / 3, 1e-6)); // not the 40 s inside the hole
      expect(e[1000], closeTo(1000 / 3, 1e-6)); // not the 193 s across it
    });

    test('a distance that only updates every 30 s still gives times between the updates', () {
      // 3 m/s, but every point between updates repeats the stale distance
      final pts = [for (var s = 0; s <= 400; s++) (s, (s ~/ 30) * 90.0)];
      final e = findBestEfforts(track(pts));
      expect(e[400], closeTo(400 / 3, 3));
    });

    test('a distance that jumps further than anyone can run does not count', () {
      // the first point is 0, the next carries 7.5 km
      final pts = [(0, 0.0), (2, 7500.0), for (var s = 3; s < 400; s++) (s, 7500.0 + (s - 2) * 3)];
      expect(findBestEfforts(track(pts))[400], closeTo(400 / 3, 1e-6));
    });

    test('with positions the distance comes from them, not from a stale or jumping distance column', () {
      // 3 m/s due north for 500 s; the file's distance is stale in 30 s steps and carries a 280 m jump at 200 s
      const mPerDeg = 111195.0;
      final t = Track(
        time: [for (var s = 0; s <= 500; s++) s],
        distance: [for (var s = 0; s <= 500; s++) (s ~/ 30) * 90.0 + (s >= 200 ? 280 : 0)],
        lat: [for (var s = 0; s <= 500; s++) 32 + s * 3 / mPerDeg],
        lon: [for (var s = 0; s <= 500; s++) 34.8],
      );
      final e = findBestEfforts(t);
      expect(e[400], closeTo(400 / 3, 0.5));
      expect(e[1000], closeTo(1000 / 3, 0.5));
    });

    test('a position that teleports and comes back voids the windows around it', () {
      const mPerDeg = 111195.0;
      final t = Track(
        time: [for (var s = 0; s <= 500; s++) s],
        lat: [for (var s = 0; s <= 500; s++) 32 + (s == 250 ? s * 3 + 300 : s * 3) / mPerDeg],
        lon: [for (var s = 0; s <= 500; s++) 34.8],
      );
      final e = findBestEfforts(t);
      expect(e[400], closeTo(400 / 3, 0.5)); // an honest stretch away from the glitch
      expect(e[1000], isNull); // every 1 km window crosses it
    });

    test('a gap of 30 s or less is fine', () {
      final e = findBestEfforts(track([(0, 0), (30, 300), (60, 600), (90, 900), (120, 1200)]));
      expect(e[1000], closeTo(100, 1e-6));
    });

    test('no distance, one point, or a track shorter than 400 m gives nothing', () {
      expect(findBestEfforts(Track(lat: [1, 2], lon: [1, 2])), isEmpty);
      expect(findBestEfforts(track([(0, 0)])), isEmpty);
      expect(findBestEfforts(track(steady(4, 90))), isEmpty); // 360 m
    });

    test('standing still does not make a window faster', () {
      final pts = [...steady(4, 100), for (var s = 1; s <= 60; s++) (100 + s, 400.0), ...steady(4, 100, t0: 160, d0: 400).skip(1)];
      expect(findBestEfforts(track(pts))[400], closeTo(100, 1e-6));
    });
  });

  test('topEfforts ranks fastest first and the PR is the first', () {
    Effort e(String id, int d, double s, int day) => (cardioId: id, distanceM: d, seconds: s, startedAt: DateTime(2026, 1, day));
    final all = [e('a', 1000, 280, 1), e('b', 1000, 270, 2), e('c', 1000, 270, 1), e('d', 5000, 1500, 3)];
    expect([for (final x in topEfforts(all, 1000)) x.cardioId], ['c', 'b', 'a']);
    expect(topEfforts(all, 1000, n: 2), hasLength(2));
    expect(prAt(all, 1000)!.cardioId, 'c');
    expect(prAt(all, 400), isNull);
  });

  group('cache', () {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    late AppDb db;
    late CardioStore store;
    setUp(() {
      db = AppDb(NativeDatabase.memory());
      store = CardioStore(db);
    });
    tearDown(() => db.close());

    Recording rec(String type, {String id = 'a', int hour = 10}) =>
        Recording(source: 'file', type: type, start: DateTime.utc(2026, 11, 10, hour), elapsedSec: 300, externalId: id, distanceKm: 1.2, track: track(steady(4, 300)));
    Future<List<Effort>> efforts() => db.watchBestEfforts().first;

    test('a Run and an Interval run both get efforts', () async {
      final id = (await store.ingest(rec('run'))).id!;
      final iv = (await store.ingest(rec('interval', id: 'b', hour: 14))).id!;
      final all = await efforts();
      expect({for (final e in all) e.distanceM}, {400, 1000});
      expect({for (final e in all) e.cardioId}, {id, iv});
    });

    test('an old treadmill row gets none, and editing a Run to another type removes its efforts', () async {
      final id = (await store.ingest(rec('run'))).id!;
      await store.edit(id, {'type': 'treadmill'});
      expect(await efforts(), isEmpty);
      await store.edit(id, {'type': 'interval'});
      expect(await efforts(), isNotEmpty);
    });

    test('deleting the Run removes its efforts', () async {
      final id = (await store.ingest(rec('run'))).id!;
      await store.delete(id);
      expect(await efforts(), isEmpty);
    });

    test('a merge that brings a track adds the efforts', () async {
      final id = await store.save(type: 'run', startedAt: DateTime.utc(2026, 11, 10, 10), distanceKm: 1.2, durationSec: 300);
      expect(await efforts(), isEmpty);
      await store.ingest(rec('run'));
      expect({for (final e in await efforts()) e.cardioId}, {id});
    });

    test('rebuilding everything recomputes from the tracks', () async {
      await store.ingest(rec('run'));
      await db.delete(db.bestEfforts).go();
      await db.rebuildBestEfforts();
      expect(await efforts(), isNotEmpty);
    });
  });
}

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/cardio.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/recording.dart';
import 'package:timburr/data/track.dart';

/// A GPS track of [n] one-second points heading north from [lat0].
Track gps(int n, {double lat0 = 32.0, int? hr}) => Track(
      time: [for (var i = 0; i < n; i++) i],
      distance: [for (var i = 0; i < n; i++) i * 3.0],
      lat: [for (var i = 0; i < n; i++) lat0 + i * 0.00003],
      lon: [for (var i = 0; i < n; i++) 34.8],
      hr: hr == null ? null : [for (var i = 0; i < n; i++) hr],
    );

final day = DateTime.utc(2026, 11, 10);
DateTime at(int h, [int m = 0]) => DateTime.utc(2026, 11, 10, h, m);

Recording rec({
  String source = 'file',
  String type = 'run',
  DateTime? start,
  int elapsed = 1800,
  int moving = 1700,
  String? id = 'a',
  double? km = 5.0,
  Track? track,
  int? avgHr,
  String? notes,
}) =>
    Recording(source: source, type: type, start: start ?? at(10), elapsedSec: elapsed, movingSec: moving, externalId: id, distanceKm: km, track: track, avgHr: avgHr, notes: notes);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDb db;
  late CardioStore store;
  setUp(() {
    db = AppDb(NativeDatabase.memory());
    store = CardioStore(db);
  });
  tearDown(() => db.close());

  Future<List<CardioData>> runs() => store.watchAll().first;
  Future<CardioData> only() async {
    final all = await runs();
    expect(all, hasLength(1));
    return all.single;
  }

  group('a recording that matches nothing', () {
    test('becomes a Run with Moving and Elapsed time, its track and a simplified route', () async {
      final result = await store.ingest(rec(track: gps(1000), avgHr: 150));
      expect(result.outcome, IngestOutcome.created);
      final run = await only();
      expect(run.id, result.id);
      expect((run.type, run.distanceKm, run.durationSec, run.elapsedSec), ('run', 5.0, 1700, 1800));
      expect((run.source, run.externalId, run.avgHr), ('file', 'a', 150));
      expect(run.startedAt.toUtc(), at(10));
      expect(run.route!.split(';').length, inInclusiveRange(150, 250));
      expect(run.route!.split(';').first, '32.00000,34.80000');
      final track = (await store.watchTrack(run.id).first)!;
      expect(track.length, 1000);
      expect(track.lat!.last, closeTo(32.02997, 1e-9));
    });

    test('a recording without a route has none, but keeps its track', () async {
      await store.ingest(rec(track: Track(time: [0, 60], distance: [0, 900])));
      final run = await only();
      expect(run.route, isNull);
      expect((await store.watchTrack(run.id).first)!.distance, [0, 900]);
    });

    test('a recording without a track makes a Run with no track', () async {
      await store.ingest(rec());
      expect(await store.watchTrack((await only()).id).first, isNull);
    });
  });

  group('the same recording again', () {
    test('changes nothing', () async {
      await store.ingest(rec(track: gps(100)));
      final before = await only();
      final again = await store.ingest(rec(track: gps(100)));
      expect(again.outcome, IngestOutcome.unchanged);
      expect(again.id, before.id);
      final after = await only();
      expect(after.updatedAt, before.updatedAt);
      expect(after.dirty, before.dirty);
    });

    test('does not bring back a Run Daniel deleted', () async {
      final id = (await store.ingest(rec())).id!;
      await store.delete(id);
      expect((await store.ingest(rec())).outcome, IngestOutcome.unchanged);
      expect(await runs(), isEmpty);
    });

    test('a different external id from the same source is another recording', () async {
      await store.ingest(rec(start: at(7), id: 'a'));
      await store.ingest(rec(start: at(18), id: 'b'));
      expect(await runs(), hasLength(2));
    });
  });

  group('overlap', () {
    test('recordings whose times overlap are one Run, whatever their start times', () async {
      await store.ingest(rec(source: 'recorded', id: 'r', start: at(10), elapsed: 1800));
      final merged = await store.ingest(rec(source: 'health_connect', id: 'h', start: at(10, 20), elapsed: 1500));
      expect(merged.outcome, IngestOutcome.merged);
      expect(await runs(), hasLength(1));
    });

    test('the Run spans the earliest start to the latest end', () async {
      await store.ingest(rec(id: 'a', start: at(10), elapsed: 1800)); // 10:00-10:30
      await store.ingest(rec(source: 'health_connect', id: 'h', start: at(9, 50), elapsed: 2400)); // 9:50-10:30
      await store.ingest(rec(source: 'health_connect', id: 'h2', start: at(10, 20), elapsed: 3000)); // 10:20-11:10
      final run = await only();
      expect(run.startedAt.toUtc(), at(9, 50));
      expect(run.elapsedSec, 4800);
    });

    test('Runs on the same day that do not overlap stay separate, even touching', () async {
      await store.ingest(rec(id: 'a', start: at(10), elapsed: 1800));
      await store.ingest(rec(id: 'b', start: at(10, 30), elapsed: 1800)); // starts the moment the first ends
      await store.ingest(rec(id: 'c', start: at(18), elapsed: 1800));
      expect(await runs(), hasLength(3));
    });

    test('a walk or an old non-Run row never absorbs a recording', () async {
      await store.save(type: 'walk', startedAt: at(10), distanceKm: 2, durationSec: 1800);
      await store.ingest(rec());
      expect(await runs(), hasLength(2));
    });
  });

  group('precedence', () {
    test('outdoor: the phone GPS wins route and distance, and an import fills the rest', () async {
      await store.ingest(rec(id: 'f', km: 4.6, moving: 1650, avgHr: 148));
      await store.ingest(rec(source: 'recorded', id: 'r', km: 5.2, moving: 1740, track: gps(300)));
      final run = await only();
      expect((run.distanceKm, run.durationSec), (5.2, 1740));
      expect(run.avgHr, 148); // the recording has none, so the file's stays
      expect(run.route, isNotNull);
      expect((run.source, run.externalId), ('recorded', 'r'));
      expect((await store.watchTrack(run.id).first)!.length, 300);
    });

    test('outdoor: an import never overwrites what the phone recorded', () async {
      await store.ingest(rec(source: 'recorded', id: 'r', km: 5.2, moving: 1740, track: gps(300)));
      await store.ingest(rec(source: 'health_connect', id: 'h', km: 4.6, moving: 1650, avgHr: 148, track: gps(80, lat0: 33)));
      final run = await only();
      expect((run.distanceKm, run.durationSec, run.avgHr), (5.2, 1740, 148));
      expect((run.source, run.externalId), ('recorded', 'r'));
      expect((await store.watchTrack(run.id).first)!.lat!.first, 32.0);
    });

    test('Interval run: the Fitbit fills the heart rate but never makes it a plain Run', () async {
      await store.ingest(rec(source: 'recorded', id: 'r', type: 'interval', km: 5.1, moving: 1500, elapsed: 1500));
      await store.ingest(rec(source: 'health_connect', id: 'h', type: 'run', km: 4.8, moving: 1400, elapsed: 1400, avgHr: 151));
      final run = await only();
      expect((run.type, run.distanceKm, run.durationSec, run.avgHr), ('interval', 5.1, 1500, 151));
    });

    test('Interval run: a recording over an imported Run makes it an Interval run with the phone\'s distance', () async {
      await store.ingest(rec(id: 'f', type: 'run', km: 4.9, moving: 1400, avgHr: 141));
      await store.ingest(rec(source: 'recorded', id: 'r', type: 'interval', km: 5.1, moving: 1500));
      final run = await only();
      expect((run.type, run.distanceKm, run.durationSec, run.avgHr), ('interval', 5.1, 1500, 141));
    });

    test('two imports: the first one in stays and the second only fills', () async {
      await store.ingest(rec(id: 'f', km: 5.0, moving: 1700));
      await store.ingest(rec(source: 'health_connect', id: 'h', km: 4.8, moving: 1650, avgHr: 150, notes: 'x'));
      final run = await only();
      expect((run.distanceKm, run.durationSec, run.avgHr, run.notes), (5.0, 1700, 150, 'x'));
    });
  });

  group('Daniel\'s edits', () {
    test('always win over a later recording of any source', () async {
      final id = (await store.ingest(rec(km: 5.0))).id!;
      await store.edit(id, {'distance_km': 5.5, 'title': 'Evening run'});
      await store.ingest(rec(source: 'recorded', id: 'r', km: 5.2, moving: 1740, track: gps(300)));
      final run = await only();
      expect((run.distanceKm, run.title), (5.5, 'Evening run'));
      expect(run.durationSec, 1740); // not edited, so the phone still wins it
      expect(run.editedFields, containsAll(['distance_km', 'title']));
    });

    test('an edited start is not moved by an earlier recording', () async {
      final id = (await store.ingest(rec(start: at(10)))).id!;
      await store.edit(id, {'started_at': at(10, 5)});
      await store.ingest(rec(source: 'health_connect', id: 'h', start: at(9, 55), elapsed: 3000)); // 9:55-10:45
      final run = await only();
      expect(run.startedAt.toUtc(), at(10, 5));
      expect(run.elapsedSec, 2400); // still runs to the latest end, 10:45
    });

    test('a hand-typed Run is Daniel\'s too: nothing replaces its values', () async {
      await store.save(type: 'run', startedAt: at(10), distanceKm: 5, durationSec: 1700);
      await store.ingest(rec(source: 'recorded', id: 'r', km: 5.4, moving: 1800, track: gps(300)));
      final run = await only();
      expect((run.distanceKm, run.durationSec), (5, 1700));
    });
  });

  test('24 Oct: a hand-typed Run keeps its 1.15 km and notes, and the overlapping file fills the heart rate', () async {
    await store.save(type: 'run', startedAt: at(17, 15), distanceKm: 1.15, durationSec: 1200, notes: 'Legs felt heavy');
    final result = await store.ingest(rec(
        start: at(17, 17), elapsed: 813, moving: 813, km: 1.07, id: 'strava-24-oct', avgHr: 142, track: Track(time: [0, 400, 813], distance: [0, 500, 1070], hr: [120, 150, 140])));
    expect(result.outcome, IngestOutcome.merged);
    final run = await only();
    expect((run.distanceKm, run.durationSec, run.notes, run.type), (1.15, 1200, 'Legs felt heavy', 'run'));
    expect(run.avgHr, 142);
    expect(run.startedAt.toUtc(), at(17, 15));
    expect((await store.watchTrack(run.id).first)!.hr, [120, 150, 140]);
    // Importing the file again changes nothing.
    expect((await store.ingest(rec(start: at(17, 17), elapsed: 813, moving: 813, km: 1.07, id: 'strava-24-oct', avgHr: 142))).outcome, IngestOutcome.unchanged);
  });

  group('Health Connect', () {
    test('a session that overlaps no Run creates nothing, however often it is checked', () async {
      final h = rec(source: 'health_connect', id: 'h', start: at(10, 15), elapsed: 1500, avgHr: 150);
      expect((await store.ingest(h)).outcome, IngestOutcome.ignored);
      expect((await store.ingest(h)).outcome, IngestOutcome.ignored);
      expect((await store.ingest(h, dryRun: true)).outcome, IngestOutcome.ignored);
      expect(await runs(), isEmpty);
    });

    test('the same session checked again after Daniel records the Run fills it in', () async {
      final h = rec(source: 'health_connect', id: 'h', start: at(10, 15), elapsed: 1500, km: 4.6, avgHr: 150);
      await store.ingest(h);
      await store.ingest(rec(source: 'recorded', id: 'r', start: at(10), elapsed: 2400, moving: 2300, km: 5.2, track: gps(300)));
      expect((await store.ingest(h)).outcome, IngestOutcome.merged);
      final run = await only();
      expect((run.distanceKm, run.durationSec, run.avgHr), (5.2, 2300, 150));
      expect((run.source, run.externalId), ('recorded', 'r'));
      expect(run.startedAt.toUtc(), at(10));
      expect(run.elapsedSec, 2400);
    });

    test('a merged session checked again changes nothing', () async {
      await store.ingest(rec(source: 'recorded', id: 'r', track: gps(300)));
      final h = rec(source: 'health_connect', id: 'h', start: at(10, 10), elapsed: 1500, avgHr: 150, track: Track(time: [0, 60, 120], hr: [140, 150, 160]));
      expect((await store.ingest(h)).outcome, IngestOutcome.merged);
      final before = await only();
      expect((await store.ingest(h)).outcome, IngestOutcome.unchanged);
      expect((await only()).updatedAt, before.updatedAt);
    });

    test('a session on the same day that does not overlap leaves the Run alone', () async {
      await store.ingest(rec(source: 'recorded', id: 'r', start: at(7), elapsed: 1800));
      expect((await store.ingest(rec(source: 'health_connect', id: 'h', start: at(18), avgHr: 150))).outcome, IngestOutcome.ignored);
      expect((await only()).avgHr, isNull);
    });
  });

  group('a dry run', () {
    test('says what ingest would do and writes nothing', () async {
      expect((await store.ingest(rec(), dryRun: true)).outcome, IngestOutcome.created);
      expect(await runs(), isEmpty);
      await store.ingest(rec());
      expect((await store.ingest(rec(), dryRun: true)).outcome, IngestOutcome.unchanged);
      expect((await store.ingest(rec(source: 'health_connect', id: 'h', avgHr: 150), dryRun: true)).outcome, IngestOutcome.merged);
      expect((await only()).avgHr, isNull);
    });
  });

  group('a recorded Run with gaps in its live heart rate', () {
    test('a Health Connect session fills the gaps and keeps the live readings', () async {
      final live = gps(60);
      final liveHr = Track(time: live.time, distance: live.distance, lat: live.lat, lon: live.lon, hr: [for (var i = 0; i < 60; i++) i >= 20 && i < 40 ? null : 150 + i % 3]);
      final result = await store.ingest(rec(source: 'recorded', id: 's', start: at(10), elapsed: 60, moving: 60, track: liveHr));
      final fromBand = Track(time: [for (var i = 0; i < 60; i++) i], hr: [for (var i = 0; i < 60; i++) 120]);
      await store.ingest(rec(source: 'health_connect', id: 'h', start: at(10), elapsed: 60, moving: 60, track: fromBand));
      final hr = (await store.watchTrack(result.id!).first)!.hr!;
      expect(hr.length, 60);
      expect(hr[10], 150 + 10 % 3); // live readings stay
      expect(hr.sublist(20, 40), everyElement(120)); // the gap is filled
      expect(hr.contains(null), isFalse);
    });
  });

  test('0 km Runs left by old test recordings are removed at start; real Runs stay', () async {
    await store.ingest(rec(id: 'real', start: at(8)));
    await store.ingest(rec(id: 'zero', start: at(10), km: 0.0, track: gps(20)));
    await store.ingest(rec(id: 'tiny', start: at(12), km: 0.0004));
    expect(await runs(), hasLength(3));
    expect(await store.dropUnsyncableRuns(), 2);
    final left = await only();
    expect(left.externalId, 'real');
    expect(await db.select(db.cardioTracks).get(), isEmpty);
    expect(await store.dropUnsyncableRuns(), 0);
  });
}

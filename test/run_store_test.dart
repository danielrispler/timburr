import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/cardio.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/recording.dart';
import 'package:timburr/data/track.dart';

/// 100 one-second points at 3 m/s heading north, with a 10 s stop and a 10 m climb.
Track climb() => Track(
      time: [for (var i = 0; i < 100; i++) i],
      distance: [for (var i = 0; i < 100; i++) (i < 40 ? i : i < 50 ? 40 : i - 10) * 3.0],
      lat: [for (var i = 0; i < 100; i++) 32.0 + i * 0.00003],
      lon: [for (var i = 0; i < 100; i++) 34.8],
      altitude: [for (var i = 0; i < 100; i++) 100.0 + i / 10],
    );

Recording rec({String source = 'file', String id = 'a', int? moving, double? gain, DateTime? start, Track? track}) => Recording(
    source: source, type: 'run', start: start ?? DateTime.utc(2026, 11, 10, 10), elapsedSec: 99, movingSec: moving, externalId: id, distanceKm: 0.3, elevationGainM: gain, track: track ?? climb());

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDb db;
  late CardioStore store;
  setUp(() {
    db = AppDb(NativeDatabase.memory());
    store = CardioStore(db);
  });
  tearDown(() => db.close());

  Future<CardioData> only() async => (await store.watchAll().first).single;

  test('a recording without Moving time or elevation gets both from its track', () async {
    await store.ingest(rec());
    final run = await only();
    expect(run.durationSec, 99 - 10); // the 10 s stop is auto-paused
    expect(run.elevationGainM, closeTo(9.9, 1.5));
  });

  test('the source\'s own Moving time and elevation are kept', () async {
    await store.ingest(rec(moving: 95, gain: 42));
    final run = await only();
    expect((run.durationSec, run.elevationGainM), (95, 42));
  });

  test('a later overlapping recording only fills empty fields, and never what Daniel edited', () async {
    final id = (await store.ingest(rec(track: Track(time: [0, 99], distance: [0, 300])))).id!; // no altitude: no elevation yet
    expect((await only()).elevationGainM, isNull);
    await store.edit(id, {'duration_sec': 1234, 'title': 'My run'});

    await store.ingest(rec(source: 'recorded', id: 'r', moving: 80, start: DateTime.utc(2026, 11, 10, 10, 0, 30)));
    final run = await only();
    expect((run.durationSec, run.title), (1234, 'My run')); // the recording outranks the file but the edit stays
    expect(run.elevationGainM, isNotNull); // filled
    expect(run.editedFields, ['duration_sec', 'title']);
  });

  test('delete soft-deletes the Run and its track', () async {
    final id = (await store.ingest(rec())).id!;
    expect(await store.watchTrack(id).first, isNotNull);
    await store.delete(id);
    expect(await store.watchAll().first, isEmpty);
    expect(await store.watchTrack(id).first, isNull);
    expect((await store.watch(id).first).deletedAt, isNotNull);
    expect((await (db.select(db.cardioTracks)..where((t) => t.cardioId.equals(id))).getSingle()).deletedAt, isNotNull);
    expect((await store.ingest(rec())).outcome, IngestOutcome.unchanged); // and a re-import does not bring it back
  });

  Recording run({required String source, String? id, String type = 'run', double? km, int? moving, int? hr, Track? track, int startSec = 0}) => Recording(
      source: source, type: type, start: DateTime.utc(2026, 11, 10, 10, 0, startSec), elapsedSec: 99, movingSec: moving, externalId: id, distanceKm: km, avgHr: hr, track: track);

  group('per-field preference', () {
    test('outdoor: distance and time follow the phone, heart rate follows the Fitbit, whichever arrives first', () async {
      await store.ingest(run(source: 'health_connect', id: 'h', km: 5.0, moving: 1500, hr: 150));
      await store.ingest(run(source: 'recorded', id: 'r', km: 5.2, moving: 1490, hr: 99));
      var c = await only();
      expect((c.distanceKm, c.durationSec, c.avgHr, c.source, c.externalId), (5.2, 1490, 150, 'recorded', 'r'));

      await db.delete(db.cardio).go();
      await store.ingest(run(source: 'recorded', id: 'r2', km: 5.2, moving: 1490));
      await store.ingest(run(source: 'health_connect', id: 'h2', km: 5.0, moving: 1500, hr: 150));
      c = await only();
      expect((c.distanceKm, c.durationSec, c.avgHr, c.source), (5.2, 1490, 150, 'recorded')); // the Fitbit only filled the heart rate
    });

    test('treadmill: time from the phone, distance and heart rate from the Fitbit until Daniel corrects it', () async {
      await store.ingest(run(source: 'recorded', id: 'r', type: 'treadmill', km: 3.0, moving: 1000));
      await store.ingest(run(source: 'health_connect', id: 'h', type: 'treadmill', km: 3.3, moving: 1010, hr: 150));
      var c = await only();
      expect((c.distanceKm, c.durationSec, c.avgHr), (3.3, 1000, 150));

      await store.edit(c.id, {'distance_km': 3.1});
      await store.ingest(run(source: 'health_connect', id: 'h2', type: 'treadmill', km: 3.4, startSec: 5));
      c = await only();
      expect(c.distanceKm, 3.1);
    });

    test('an import never overwrites what is on a Run, only fills', () async {
      await store.ingest(run(source: 'health_connect', id: 'h', km: 5.0, moving: 1500));
      await store.ingest(run(source: 'file', id: 'f', km: 5.5, moving: 1400, hr: 140));
      final c = await only();
      expect((c.distanceKm, c.durationSec, c.avgHr), (5.0, 1500, 140));
    });

    test('a recording without an external id never blanks the Run\'s', () async {
      await store.ingest(run(source: 'health_connect', id: 'h', km: 5.0, moving: 1500));
      await store.ingest(run(source: 'recorded', km: 5.2, moving: 1490));
      final c = await only();
      expect((c.source, c.externalId), ('health_connect', 'h'));
    });
  });

  group('track merge', () {
    Track fitbit() => Track(time: [for (var i = 0; i < 100; i += 5) i], hr: [for (var i = 0; i < 100; i += 5) 140 + i ~/ 5]);

    test('a winning track keeps the heart rate column the stored one had', () async {
      final id = (await store.ingest(run(source: 'health_connect', id: 'h', km: 0.3, track: fitbit()))).id!;
      await store.ingest(run(source: 'recorded', id: 'r', km: 0.3, track: climb(), startSec: 2));
      final t = (await store.watchTrack(id).first)!;
      expect(t.lat!.where((v) => v != null).length, 100); // the phone's positions are the base
      expect(t.hr, isNotNull);
      expect(t.hr![50], closeTo(150, 1)); // second 52 of the Run: the nearest Fitbit sample is at 50 s
      expect((await only()).route, isNotNull);
    });

    test('a late Fitbit track adds heart rate to the phone\'s positions without touching them', () async {
      final id = (await store.ingest(run(source: 'recorded', id: 'r', km: 0.3, track: climb()))).id!;
      await store.ingest(run(source: 'health_connect', id: 'h', track: fitbit()));
      final t = (await store.watchTrack(id).first)!;
      expect(t.lat, climb().lat);
      expect(t.hr![50], 150);
    });
  });
}

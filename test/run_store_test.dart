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
}

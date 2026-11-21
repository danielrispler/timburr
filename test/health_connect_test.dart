import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/cardio.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/health_connect.dart';
import 'package:timburr/data/recording.dart';
import 'package:timburr/data/track.dart';
import 'package:timburr/data/workouts.dart';

DateTime at(int h, [int m = 0, int s = 0]) => DateTime.utc(2026, 11, 10, h, m, s);

/// A Fitbit session as MainActivity.kt hands it over, with a sample every 30 s at 140 + n bpm.
Map<String, Object?> session({
  String id = 'hc-1',
  int type = hcRunning,
  required DateTime start,
  required DateTime end,
  double? distanceM,
  double? totalKcal,
  double? activeKcal,
  bool hr = true,
}) {
  final times = [for (var t = start; !t.isAfter(end); t = t.add(const Duration(seconds: 30))) t];
  return {
    'id': id,
    'type': type,
    'start': start.millisecondsSinceEpoch,
    'end': end.millisecondsSinceEpoch,
    'distanceM': distanceM,
    'totalKcal': totalKcal,
    'activeKcal': activeKcal,
    'hrTimes': hr ? [for (final t in times) t.millisecondsSinceEpoch] : const <int>[],
    'hrBpm': hr ? [for (var i = 0; i < times.length; i++) 140 + i] : const <int>[],
  };
}

/// A phone GPS track: [n] one-second points heading north.
Track gps(int n) => Track(
      time: [for (var i = 0; i < n; i++) i],
      distance: [for (var i = 0; i < n; i++) i * 3.0],
      lat: [for (var i = 0; i < n; i++) 32.0 + i * 0.00003],
      lon: [for (var i = 0; i < n; i++) 34.8],
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDb db;
  late CardioStore store;
  late WorkoutStore workouts;
  setUp(() {
    db = AppDb(NativeDatabase.memory());
    store = CardioStore(db);
    workouts = WorkoutStore(db);
  });
  tearDown(() => db.close());

  Future<List<CardioData>> runs() => store.watchAll().first;
  Future<HcCheck> apply(List<Map<String, Object?>> sessions) => applySessions(store, workouts, [for (final s in sessions) HcSession.fromMap(s)]);
  Future<String> recorded({String type = 'run', DateTime? start, int elapsed = 1800, double km = 5.2, Track? track}) async =>
      (await store.ingest(Recording(source: 'recorded', type: type, start: start ?? at(10), elapsedSec: elapsed, movingSec: elapsed - 60, externalId: 'r', distanceKm: km, track: track)))
          .id!;

  test('an Auto-detected run that overlaps nothing creates no Run', () async {
    final r = await apply([session(start: at(10, 15), end: at(10, 40), distanceM: 4100)]);
    expect(r.runs, 0);
    expect(await runs(), isEmpty);
  });

  test('a late Auto-detected run fills in the recorded Run: heart rate, max HR and calories; the phone keeps distance, time and span', () async {
    final id = await recorded(track: gps(1800));
    final r = await apply([session(start: at(10, 15), end: at(10, 30), distanceM: 3900, totalKcal: 310.4, activeKcal: 250)]);
    expect(r.runs, 1);
    final run = (await runs()).single;
    expect(run.id, id);
    expect((run.distanceKm, run.durationSec), (5.2, 1740)); // outdoor: the phone's GPS wins
    expect((run.avgHr, run.maxHr, run.calories), (155, 170, 310)); // 31 samples, 140..170; the total calories
    expect((run.source, run.externalId), ('recorded', 'r'));
    expect(run.startedAt.toUtc(), at(10));
    expect(run.elapsedSec, 1800);
    final t = (await store.watchTrack(id).first)!;
    expect(t.lat, gps(1800).lat); // the phone's positions stay
    expect(t.hr![900], 140); // 10:15:00, the first Fitbit sample
    expect(t.hr![0], isNull); // before the Fitbit noticed
    // Checked again: nothing changes.
    final before = (await runs()).single;
    expect((await apply([session(start: at(10, 15), end: at(10, 30), distanceM: 3900, totalKcal: 310.4)])).runs, 0);
    expect((await runs()).single.updatedAt, before.updatedAt);
  });

  test('treadmill: the Fitbit\'s distance replaces the phone\'s estimate, until Daniel corrects it', () async {
    final id = await recorded(type: 'treadmill', km: 2.0);
    await apply([session(type: hcRunning, start: at(10, 12), end: at(10, 30), distanceM: 2437)]);
    var run = (await runs()).single;
    expect((run.type, run.distanceKm, run.durationSec), ('treadmill', 2.437, 1740));

    await store.edit(id, {'distance_km': 2.6});
    await apply([session(id: 'hc-2', type: hcTreadmill, start: at(10, 5), end: at(10, 25), distanceM: 2500)]);
    run = (await runs()).single;
    expect(run.distanceKm, 2.6);
  });

  test('a Fitbit session never replaces what an imported file already has', () async {
    await store.ingest(Recording(source: 'file', type: 'run', start: at(10), elapsedSec: 1800, movingSec: 1700, externalId: 'f', distanceKm: 5.0, avgHr: 150));
    await apply([session(start: at(10, 10), end: at(10, 30), distanceM: 4400, activeKcal: 280)]);
    final run = (await runs()).single;
    expect((run.distanceKm, run.avgHr), (5.0, 150));
    expect((run.maxHr, run.calories), (180, 280)); // empty, so filled; active calories when there is no total
  });

  test('walks, strength sessions and other activities never touch a Run', () async {
    await recorded();
    final r = await apply([
      session(id: 'w', type: 79, start: at(10, 5), end: at(10, 25)), // walking
      session(id: 's', type: 70, start: at(10, 5), end: at(10, 25)), // strength training
    ]);
    expect(r.runs, 0);
    expect((await runs()).single.avgHr, isNull);
  });

  test('a session without heart rate fills only what it has, and keeps the Run\'s track', () async {
    final id = await recorded(track: gps(1800));
    await apply([session(start: at(10, 15), end: at(10, 30), hr: false, totalKcal: 200)]);
    final run = (await runs()).single;
    expect((run.avgHr, run.maxHr, run.calories), (null, null, 200));
    expect((await store.watchTrack(id).first)!.hr, isNull);
  });

  group('the mapping into a recording', () {
    test('a treadmill session is a Treadmill run; distance in km; samples outside the session are dropped', () {
      final m = session(type: hcTreadmill, start: at(10), end: at(10, 1), distanceM: 1234.5678);
      (m['hrTimes'] as List).add(at(10, 5).millisecondsSinceEpoch);
      (m['hrBpm'] as List).add(199);
      final r = runRecording(HcSession.fromMap(m))!;
      expect((r.source, r.type, r.externalId, r.elapsedSec, r.distanceKm), ('health_connect', 'treadmill', 'hc-1', 60, 1.235));
      expect(r.track!.time, [0, 30, 60]);
      expect(r.track!.hr, [140, 141, 142]);
      expect((r.avgHr, r.maxHr), (141, 142));
      expect(r.track!.lat, isNull);
    });

    test('a zero distance is no distance, and other activities are not recordings', () {
      expect(runRecording(HcSession.fromMap(session(start: at(10), end: at(10, 20), distanceM: 0)))!.distanceKm, isNull);
      expect(runRecording(HcSession.fromMap(session(type: 79, start: at(10), end: at(10, 20)))), isNull);
      expect(runRecording(HcSession.fromMap(session(start: at(10), end: at(10)))), isNull);
    });
  });

  group('Workout Health stats', () {
    /// A Workout logged after the fact: 18:00 to 18:10.
    Future<String> workout() => workouts.start(at: at(18), done: true);
    Future<Workout> read(String id) => workouts.watchWorkout(id).first;

    test('an overlapping Fitbit session fills the empty Health stats', () async {
      final id = await workout();
      final r = await apply([session(id: 's', type: 70, start: at(18, 1), end: at(18, 9), totalKcal: 88.6)]);
      expect(r.workouts, 1);
      final w = await read(id);
      expect((w.avgHr, w.calories, w.activeSec), (148, 89, 480)); // 17 samples, 140..156
      expect((w.effort, w.cardioLoad), (null, null));
      expect((await apply([session(id: 's', type: 70, start: at(18, 1), end: at(18, 9), totalKcal: 88.6)])).workouts, 0); // checked again
    });

    test('typed values win: only the empty ones are filled', () async {
      final id = await workout();
      await workouts.setHealth(id, (avgHr: 91, calories: null, activeSec: 3689, effort: 5, cardioLoad: null));
      await apply([session(id: 's', type: 70, start: at(18, 1), end: at(18, 9), totalKcal: 88.6)]);
      final w = await read(id);
      expect((w.avgHr, w.calories, w.activeSec, w.effort), (91, 89, 3689, 5));
    });

    test('a session that does not overlap, or only clips its end, touches no Workout', () async {
      final id = await workout();
      final r = await apply([
        session(id: 'before', type: 70, start: at(16), end: at(17)),
        session(id: 'walk-home', type: 79, start: at(18, 8), end: at(18, 30)), // 2 of its 22 minutes inside
      ]);
      expect(r.workouts, 0);
      expect((await read(id)).avgHr, isNull);
    });

    test('the session that overlaps most wins, and a run session never fills a Workout', () async {
      final id = await workout();
      await apply([
        session(id: 'run', type: hcRunning, start: at(18), end: at(18, 10), totalKcal: 999),
        session(id: 'warmup', type: 79, start: at(17, 59), end: at(18, 2), totalKcal: 20),
        session(id: 'weights', type: 70, start: at(18, 2), end: at(18, 10), totalKcal: 70),
      ]);
      expect((await read(id)).calories, 70);
      expect(await runs(), isEmpty);
    });

    test('a Workout still in progress or deleted is left alone', () async {
      final live = await workouts.start(at: at(18));
      final gone = await workout();
      await workouts.discard(gone);
      expect((await apply([session(id: 's', type: 70, start: at(18, 1), end: at(18, 9))])).workouts, 0);
      expect((await read(live)).avgHr, isNull);
    });
  });
}

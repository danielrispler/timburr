import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/cardio.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/live_recorder.dart';
import 'package:timburr/data/recorder.dart';
import 'package:timburr/data/recording.dart';

final t0 = DateTime.utc(2026, 11, 10, 7);
DateTime at(int sec) => t0.add(Duration(seconds: sec));

/// A fix [sec] seconds after the start, [meters] north of the start point.
PositionSample fix(int sec, double meters, {double? accuracy = 5, double? altitude}) =>
    PositionSample(time: at(sec), lat: 32.0 + meters / 111195, lon: 34.8, accuracy: accuracy, altitude: altitude);

/// Feeds a steady [speed] m/s over seconds [from]..[to] inclusive, starting [startM] meters from the origin.
void feed(Recorder r, int from, int to, {double speed = 3, double startM = 0}) {
  for (var s = from; s <= to; s++) {
    r.position(fix(s, startM + (s - from) * speed));
  }
}

class FakeSource implements PositionSource {
  final _c = StreamController<PositionSample>.broadcast();
  @override
  Stream<PositionSample> positions({required bool background}) => _c.stream;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<PositionPermission> ensurePermission() async => PositionPermission.granted;
  void emit(PositionSample s) => _c.add(s);
}

class FakeService implements RecordingService {
  bool running = false;
  @override
  Future<void> start() async => running = true;
  @override
  Future<void> stop() async => running = false;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('Recorder', () {
    test('adds up the distance of a steady run and reports pace', () {
      final r = Recorder.start('run', at(0), 's1');
      feed(r, 0, 100, speed: 3);
      final s = r.snapshot(at(100));
      expect(s.distanceM, closeTo(300, 1));
      expect(s.elapsedSec, 100);
      expect(s.movingSec, 100);
      expect(s.avgPaceSecPerKm, closeTo(333, 2)); // 3 m/s
      expect(s.currentPaceSecPerKm, closeTo(333, 5));
    });

    test('ignores an inaccurate fix and a jump faster than a runner can go', () {
      final r = Recorder.start('run', at(0), 's1');
      feed(r, 0, 10);
      r.position(fix(11, 33 + 5000)); // 5 km in a second
      r.position(fix(12, 36, accuracy: 120)); // too vague
      r.position(fix(13, 39));
      expect(r.snapshot(at(13)).distanceM, closeTo(39, 1));
    });

    test('stops Moving time while stationary for 5 s or more, and counts no distance', () {
      final r = Recorder.start('run', at(0), 's1');
      feed(r, 0, 10, speed: 3); // 30 m
      for (var s = 11; s <= 20; s++) {
        r.position(fix(s, 30 + (s.isEven ? 0.3 : 0))); // standing at a light, GPS jitter
      }
      expect(r.snapshot(at(20)).autoPaused, isTrue);
      feed(r, 21, 30, speed: 3, startM: 33);
      final s = r.snapshot(at(30));
      expect(s.autoPaused, isFalse);
      expect(s.elapsedSec, 30);
      expect(s.movingSec, closeTo(20, 1)); // stopped from 10 to 21
      expect(s.distanceM, closeTo(60, 1.5));
    });

    test('a stop shorter than 5 s still counts as moving', () {
      final r = Recorder.start('run', at(0), 's1');
      feed(r, 0, 10);
      for (var s = 11; s <= 13; s++) {
        r.position(fix(s, 30));
      }
      feed(r, 14, 20, startM: 33);
      expect(r.snapshot(at(20)).movingSec, 20);
    });

    test('manual pause and resume keep Moving time honest and do not count the walk in between', () {
      final r = Recorder.start('run', at(0), 's1');
      feed(r, 0, 10); // 30 m
      r.pause(at(10));
      expect(r.snapshot(at(40)).paused, isTrue);
      expect(r.snapshot(at(40)).movingSec, 10);
      r.position(fix(30, 500)); // positions while paused are not recorded
      r.resume(at(60));
      feed(r, 60, 70, startM: 400); // resumes 370 m away: no distance for the gap
      final s = r.snapshot(at(70));
      expect(s.paused, isFalse);
      expect(s.elapsedSec, 70);
      expect(s.movingSec, closeTo(20, 1));
      expect(s.distanceM, closeTo(60, 1.5));
    });

    test('finish gives a recorded Recording with the track, Moving time and the session id', () {
      final r = Recorder.start('run', at(0), 'session-1');
      for (var s = 0; s <= 60; s++) {
        r.position(fix(s, s * 3.0, altitude: 10 + s * 0.5));
      }
      final rec = r.finish(at(60));
      expect((rec.source, rec.type, rec.externalId), ('recorded', 'run', 'session-1'));
      expect(rec.start, at(0));
      expect((rec.elapsedSec, rec.moving), (60, 60));
      expect(rec.distanceKm, closeTo(0.18, 0.002));
      expect(rec.track!.length, 61);
      expect(rec.track!.distance!.last, closeTo(180, 1));
      expect(rec.track!.time!.last, 60);
      expect(rec.elevation, isNotNull);
    });

    test('replaying the saved events rebuilds the same state', () {
      final r = Recorder.start('run', at(0), 's1');
      feed(r, 0, 20);
      r.pause(at(20));
      r.resume(at(30));
      feed(r, 30, 40, startM: 60);
      final copy = Recorder.replay(r.events.map((e) => RecorderEvent.fromJson(e.toJson())).toList());
      expect(copy.snapshot(at(40)).distanceM, r.snapshot(at(40)).distanceM);
      expect(copy.snapshot(at(40)).movingSec, r.snapshot(at(40)).movingSec);
      expect(copy.sessionId, 's1');
    });

    test('GPS signal follows the accuracy of the latest fix and goes after 10 s of silence', () {
      expect(gpsSignalOf(null, at(0)), GpsSignal.none);
      expect(gpsSignalOf(fix(0, 0, accuracy: 8), at(2)), GpsSignal.good);
      expect(gpsSignalOf(fix(0, 0, accuracy: 35), at(2)), GpsSignal.weak);
      expect(gpsSignalOf(fix(0, 0, accuracy: 8), at(12)), GpsSignal.none);
    });
  });

  group('LiveRecorder', () {
    late AppDb db;
    late CardioStore cardio;
    late FakeSource source;
    late FakeService service;
    var now = t0;
    LiveRecorder make() => LiveRecorder(source: source, service: service, journal: DbJournal(db), cardio: cardio, now: () => now);

    setUp(() {
      db = AppDb(NativeDatabase.memory());
      cardio = CardioStore(db);
      source = FakeSource();
      service = FakeService();
      now = t0;
    });
    tearDown(() => db.close());

    Future<void> run(int from, int to, {double startM = 0}) async {
      for (var s = from; s <= to; s++) {
        now = at(s);
        source.emit(fix(s, startM + (s - from) * 3.0));
        await pumpEventQueue();
      }
    }

    test('finishing saves a Run through ingest, and a later Fitbit session merges into it', () async {
      final rec = make();
      await rec.open();
      await rec.start('run');
      expect(service.running, isTrue);
      await run(0, 120);
      now = at(120);
      final id = await rec.finish();
      expect(service.running, isFalse);
      expect(rec.snapshot, isNull);
      final runs = await cardio.watchAll().first;
      expect(runs, hasLength(1));
      expect((runs.single.id, runs.single.source, runs.single.type), (id, 'recorded', 'run'));
      expect(runs.single.distanceKm, closeTo(0.36, 0.01));
      final fitbit = Recording(source: 'health_connect', type: 'run', start: at(60), elapsedSec: 1800, movingSec: 1800, externalId: 'hc1', avgHr: 150);
      expect((await cardio.ingest(fitbit)).outcome, IngestOutcome.merged);
      expect(await cardio.watchAll().first, hasLength(1));
    });

    test('discard leaves no Run and no saved recording', () async {
      final rec = make();
      await rec.open();
      await rec.start('run');
      await run(0, 30);
      await rec.discard();
      expect(await cardio.watchAll().first, isEmpty);
      expect(await DbJournal(db).load(), isEmpty);
      expect(service.running, isFalse);
      expect(await make().restore(), isFalse);
    });

    test('after a restart the recording comes back paused with its distance, and finishes as one Run', () async {
      final first = make();
      await first.open();
      await first.start('run');
      await run(0, 60);
      await first.flush();
      // the app is killed here; a new process starts later
      now = at(300);
      final second = make();
      expect(await second.restore(), isTrue);
      final s = second.snapshot!;
      expect(s.paused, isTrue);
      expect(s.distanceM, closeTo(180, 1));
      expect(s.movingSec, 60);
      now = at(330);
      await second.resume();
      await run(330, 360, startM: 200);
      now = at(360);
      await second.finish();
      final runs = await cardio.watchAll().first;
      expect(runs, hasLength(1));
      expect(runs.single.durationSec, closeTo(90, 2));
      expect(runs.single.elapsedSec, 360);
      expect(await DbJournal(db).load(), isEmpty);
    });

    test('fixes before Start only drive the GPS indicator', () async {
      final rec = make();
      await rec.open();
      now = at(1);
      source.emit(fix(1, 0, accuracy: 6));
      await pumpEventQueue();
      expect(rec.gps, GpsSignal.good);
      expect(rec.snapshot, isNull);
      await rec.close();
    });
  });
}

import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/cardio.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/live_recorder.dart';
import 'package:timburr/data/recorder.dart';
import 'package:timburr/data/recording.dart';
import 'package:timburr/data/run_analysis.dart';
import 'package:timburr/data/treadmill.dart';
import 'package:timburr/ui/running/record_screen.dart' show prefillTreadmillRun;
import 'package:timburr/data/track.dart';

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
  Future<void> start({bool gps = true}) async {
    running = true;
    gpsUsed = gps;
  }

  bool gpsUsed = true;
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

  group('Recorder review fixes', () {
    test('a treadmill Run keeps its laps, as durations without a distance, even with no heart rate', () {
      final r = Recorder.start('treadmill', at(0), 's1');
      r.lap(at(300));
      final rec = r.finish(at(600));
      expect(rec.track!.laps, [300]);
      final laps = lapsOf(rec.track!);
      expect(laps.map((l) => l.durationSec), [300, 300]);
      expect(laps.map((l) => l.distanceM), [null, null]);
    });

    test('a treadmill speaks a km cue each time its Moving time at the usual pace completes a kilometer', () {
      final r = Recorder.start('treadmill', at(0), 's1', paceSecPerKm: 300);
      r.tick(at(299));
      expect(r.kmCues, isEmpty);
      r.tick(at(301));
      expect(r.kmCues.map((c) => c.km), [1]);
      r.pause(at(400));
      r.resume(at(1000)); // 600 s paused: 400 s moving so far
      r.tick(at(1100)); // 500 s moving
      expect(r.kmCues, hasLength(1));
      r.tick(at(1205)); // 605 s moving
      expect(r.kmCues.map((c) => c.km), [1, 2]);
      expect(r.kmCues.last.splitSec, 300);
      expect(kmCueText(r.kmCues.last), contains('Pace 5 00 per kilometer'));
    });

    test('the live heart rate gives the Run its average and max', () {
      final r = Recorder.start('run', at(0), 's1');
      for (var s = 0; s <= 20; s++) {
        if (s % 5 == 0) r.heartRate(s == 10 ? 170 : 150, at(s));
        r.position(fix(s, s * 3.0));
      }
      final rec = r.finish(at(20));
      expect((rec.avgHr, rec.maxHr), (155, 170));
    });

    test('a recording without a band leaves the heart rate empty for Health Connect to fill', () async {
      final db = AppDb(NativeDatabase.memory());
      addTearDown(db.close);
      final cardio = CardioStore(db);
      final noBand = Recorder.start('run', at(1000), 'b');
      for (var s = 0; s <= 20; s++) {
        noBand.position(PositionSample(time: at(1000 + s), lat: 32.0 + s * 3 / 111195, lon: 34.8, accuracy: 5));
      }
      final idB = (await cardio.ingest(noBand.finish(at(1020)))).id!;
      expect((await cardio.watch(idB).first).avgHr, isNull);
      await cardio.ingest(Recording(source: 'health_connect', type: 'run', start: at(1000), elapsedSec: 20, externalId: 'hcB', avgHr: 160, maxHr: 180));
      expect(((await cardio.watch(idB).first).avgHr, (await cardio.watch(idB).first).maxHr), (160, 180));
    });

    test('the Treadmill data prefill uses the Fitbit figure when it arrives in time, else the pace estimate', () async {
      final db = AppDb(NativeDatabase.memory());
      addTearDown(db.close);
      final cardio = CardioStore(db);
      final r = Recorder.start('treadmill', at(0), 's1', paceSecPerKm: 300);
      final id = (await cardio.ingest(r.finish(at(1500)))).id!;
      Future<double?> km(Future<Object?> Function() check, {Duration timeout = const Duration(seconds: 4)}) async => (await prefillTreadmillRun(cardio, id, check: check, timeout: timeout)).distanceKm;
      expect(await km(() async => null), 5.0); // estimate: 1500 s at 5:00 per km
      expect(await km(() => Completer<Object?>().future, timeout: const Duration(milliseconds: 20)), 5.0); // too slow
      expect(await km(() => throw StateError('hc')), 5.0);
      expect(
        await km(() async {
          await cardio.ingest(Recording(source: 'health_connect', type: 'treadmill', start: at(0), elapsedSec: 1500, externalId: 'hc', distanceKm: 4.9));
          return null;
        }),
        4.9,
      );
    });
  });

  group('Recorder on a treadmill', () {
    test('distance is Moving time over the pace, with no GPS and no auto-pause', () {
      final r = Recorder.start('treadmill', at(0), 's1', paceSecPerKm: 300);
      r.position(fix(0, 0)); // GPS on a treadmill is noise
      final s = r.snapshot(at(120));
      expect(s.distanceM, closeTo(400, 1e-6));
      expect(s.movingSec, 120);
      expect(s.avgPaceSecPerKm, closeTo(300, 1e-6));
      expect(s.gps, GpsSignal.none);
      expect(r.events.where((e) => e.kind == 'position'), isEmpty);
    });

    test('the default pace is 6:00 per km when none is given', () {
      final r = Recorder.start('treadmill', at(0), 's1');
      expect(r.snapshot(at(360)).distanceM, closeTo(1000, 1e-6));
    });

    test('time paused does not add distance', () {
      final r = Recorder.start('treadmill', at(0), 's1', paceSecPerKm: 300);
      r.pause(at(100));
      r.resume(at(400));
      expect(r.snapshot(at(500)).distanceM, closeTo(1000 * 200 / 300, 1e-6)); // 200 s moving
    });

    test('finish gives a treadmill Recording with the estimate and no track; replay rebuilds it', () {
      final r = Recorder.start('treadmill', at(0), 's1', paceSecPerKm: 300);
      final rec = r.finish(at(600));
      expect((rec.type, rec.source, rec.distanceKm), ('treadmill', 'recorded', 2.0));
      expect(rec.track, isNull);
      final again = Recorder.replay(r.events);
      expect(again.paceSecPerKm, 300);
      expect(again.finish(at(600)).distanceKm, 2.0);
    });

    test('an autosave from the step-counting build replays: steps events are ignored and the stride gives the default pace', () {
      final old = [
        RecorderEvent(EventKind.start, at(0), {'type': 'treadmill', 'id': 's1', 'stride': 0.8}),
        RecorderEvent('steps', at(60), {'n': 1000}),
        RecorderEvent('steps', at(120), {'n': 1200}),
        RecorderEvent(EventKind.pause, at(130)),
      ];
      final r = Recorder.replay(old);
      expect(r.paceSecPerKm, defaultTreadmillPaceSecPerKm);
      expect(r.snapshot(at(130)).movingSec, 130);
    });

    test('ticks are saved at most every 10 s so a killed recording keeps its time', () {
      final r = Recorder.start('treadmill', at(0), 's1');
      for (var s = 1; s <= 25; s++) {
        r.tick(at(s));
      }
      expect(r.events.where((e) => e.kind == EventKind.tick).map((e) => e.at), [at(10), at(20)]);
      final again = Recorder.replay(r.events);
      again.pause(again.lastEventAt);
      expect(again.snapshot(at(60)).movingSec, 20);
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

    test('a treadmill recording estimates distance from Moving time and the usual pace, uses no GPS, and saves a treadmill Run that never sets a best effort', () async {
      final rec = make();
      await rec.start('treadmill', paceSecPerKm: 300);
      expect(service.gpsUsed, isFalse);
      expect(source._c.hasListener, isFalse);
      now = at(1500);
      expect(rec.snapshot!.distanceM, closeTo(5000, 1e-6));
      final id = await rec.finish();
      final c = (await cardio.watchAll().first).single;
      expect((c.id, c.type, c.source), (id, 'treadmill', 'recorded'));
      expect(c.distanceKm, 5.0);
      expect(await cardio.watchBestEfforts().first, isEmpty);
    });

    test('a treadmill Run with a full track still sets no best effort', () async {
      final n = 1000;
      final track = Track(time: [for (var i = 0; i < n; i++) i], distance: [for (var i = 0; i < n; i++) i * 3.0], lat: [for (var i = 0; i < n; i++) 32.0 + i * 3 / 111195], lon: List.filled(n, 34.8));
      await cardio.ingest(Recording(source: 'recorded', type: 'treadmill', start: t0, elapsedSec: n, movingSec: n, externalId: 't', distanceKm: 3.0, track: track));
      await cardio.ingest(Recording(source: 'recorded', type: 'run', start: at(86400), elapsedSec: n, movingSec: n, externalId: 'r', distanceKm: 3.0, track: track));
      final efforts = await cardio.watchBestEfforts().first;
      expect(efforts, isNotEmpty); // the outdoor Run does
      final treadmillId = (await cardio.watchAll().first).firstWhere((c) => c.type == 'treadmill').id;
      expect(efforts.where((e) => e.cardioId == treadmillId), isEmpty);
    });

    test('Treadmill data saves what was typed as edited fields that a later Fitbit session does not replace', () async {
      final rec = make();
      await rec.start('treadmill', paceSecPerKm: 300);
      now = at(1500);
      final id = (await rec.finish())!;
      final before = await cardio.watch(id).first;
      expect(before.distanceKm, 5.0); // the estimate
      // Daniel types distance, incline, steps and calories; the Moving time is left as it was
      final initial = {'distance_km': '5.00', 'duration_sec': '25:00', 'incline_pct': '', 'steps': '', 'calories': ''};
      final edits = treadmillEdits(initial, {...initial, 'distance_km': '4.8', 'incline_pct': '1.5', 'steps': '6100', 'calories': '380'});
      expect(edits, {'distance_km': 4.8, 'incline_pct': 1.5, 'steps': 6100, 'calories': 380});
      await cardio.edit(id, edits);
      final c = await cardio.watch(id).first;
      expect((c.distanceKm, c.inclinePct, c.steps, c.calories, c.durationSec), (4.8, 1.5, 6100, 380, 1500));
      expect(c.editedFields, containsAll(['distance_km', 'incline_pct', 'steps', 'calories']));
      expect(c.editedFields, isNot(contains('duration_sec')));
      await cardio.ingest(Recording(source: 'health_connect', type: 'treadmill', start: c.startedAt, elapsedSec: 1500, externalId: 'hc', distanceKm: 4.9, calories: 420, avgHr: 150));
      final merged = await cardio.watch(id).first;
      expect((merged.distanceKm, merged.calories, merged.avgHr), (4.8, 380, 150)); // his figures stay, the Fitbit fills the rest
    });

    test('Keep estimate (no edits) leaves the Fitbit free to improve the distance', () async {
      final rec = make();
      await rec.start('treadmill', paceSecPerKm: 300);
      now = at(1500);
      final id = (await rec.finish())!;
      await cardio.ingest(Recording(source: 'health_connect', type: 'treadmill', start: t0, elapsedSec: 1500, externalId: 'hc', distanceKm: 4.9));
      expect((await cardio.watch(id).first).distanceKm, 4.9);
    });

    test('a restored treadmill recording keeps the time it had saved and carries on from Resume', () async {
      final rec = make();
      await rec.start('treadmill', paceSecPerKm: 300);
      now = at(65);
      rec.pause(); // any input saves; a tick or two is saved on the way in the app
      await rec.flush();
      final second = make();
      expect(await second.restore(), isTrue);
      final s = second.snapshot!;
      expect((s.paused, s.movingSec), (true, 65));
      now = at(120);
      await second.resume();
      now = at(185);
      expect(second.snapshot!.movingSec, 65 + 65);
      expect(second.snapshot!.distanceM, closeTo(1000 * 130 / 300, 1e-6));
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

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/cardio.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/intervals.dart';
import 'package:timburr/data/live_recorder.dart';
import 'package:timburr/data/recorder.dart';
import 'package:timburr/data/run_analysis.dart';
import 'package:timburr/data/track.dart';

import 'recorder_test.dart' show FakeService, FakeSource, at, feed, fix, t0;

class FakeSpeech implements SpeechService {
  final said = <String>[];
  @override
  Future<void> speak(String text) async => said.add(text);
  @override
  Future<void> beep() async => said.add('beep');
}

class FakeNotification implements RecordingNotification {
  RunSnapshot? last;
  bool cleared = false;
  @override
  void Function(String action)? onAction;
  @override
  Future<void> update(RunSnapshot s) async => last = s;
  @override
  Future<void> clear() async => cleared = true;
  void press(String id) => onAction!(id);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('Recorder laps', () {
    test('a lap press is a logged event, and the finished track carries the lap marks', () {
      final r = Recorder.start('run', at(0), 's1');
      feed(r, 0, 100, speed: 3);
      r.lap(at(100));
      feed(r, 101, 200, speed: 3, startM: 303);
      r.lap(at(200));
      expect(r.laps, [100, 200]);
      expect(r.finish(at(200)).track!.laps, [100, 200]);
      // Replaying the saved events rebuilds them.
      expect(Recorder.replay([for (final e in r.events) RecorderEvent.fromJson(e.toJson())]).laps, [100, 200]);
    });

    test('a lap press while paused is ignored', () {
      final r = Recorder.start('run', at(0), 's1');
      feed(r, 0, 10);
      r.pause(at(10));
      r.lap(at(12));
      expect(r.laps, isEmpty);
    });

    test('marks survive encoding, shifting and a gps-distance rebuild', () {
      final t = Track(time: [0, 100, 200], distance: [0, 300, 600], laps: [100]);
      expect(Track.decode(t.encode()).laps, [100]);
      expect(shiftedBy(t, 5).laps, [105]);
      expect(withGpsDistance(t).laps, [100]);
    });

    test('laps are listed with their time, distance and pace, the last one running to the end', () {
      final t = Track(time: [0, 100, 200, 300], distance: [0, 300, 600, 1000], laps: [100, 200]);
      final laps = lapsOf(t);
      expect(laps.map((l) => l.durationSec), [100, 100, 100]);
      expect(laps.map((l) => l.distanceM!.round()), [300, 300, 400]);
      expect(laps.first.paceSecPerKm, closeTo(333, 1));
    });

    test('no laps without marks', () {
      expect(lapsOf(Track(time: [0, 100], distance: [0, 300])), isEmpty);
    });
  });

  group('Recorder km cues', () {
    test('a cue fires at each km boundary with the split time and pace', () {
      final r = Recorder.start('run', at(0), 's1');
      feed(r, 0, 700, speed: 4); // 4 m/s: 250 s per km
      expect(r.kmCues.map((c) => c.km), [1, 2]);
      expect(r.kmCues[0].splitSec, closeTo(250, 1));
      expect(r.kmCues[1].splitSec, closeTo(250, 1));
      expect(r.kmCues[1].paceSecPerKm, closeTo(250, 1));
    });

    test('pauses do not count in a split', () {
      final r = Recorder.start('run', at(0), 's1');
      feed(r, 0, 100, speed: 4); // 400 m
      r.pause(at(100));
      r.resume(at(400)); // 300 s paused
      feed(r, 400, 600, speed: 4, startM: 400);
      expect(r.kmCues.single.splitSec, closeTo(250, 1));
    });

    test('the cue is spoken as time and pace', () {
      expect(kmCueText(const KmCue(3, 312, 312)), 'Kilometer 3. Time 5 minutes 12 seconds. Pace 5 12 per kilometer.');
    });
  });

  group('LiveRecorder voice and notification', () {
    late AppDb db;
    late FakeSource source;
    late FakeService service;
    late FakeSpeech speech;
    late FakeNotification note;
    var now = t0;
    LiveRecorder make() => LiveRecorder(
        source: source, service: service, journal: DbJournal(db), cardio: CardioStore(db), speech: speech, notification: note, now: () => now);
    setUp(() {
      db = AppDb(NativeDatabase.memory());
      source = FakeSource();
      service = FakeService();
      speech = FakeSpeech();
      note = FakeNotification();
      now = t0;
    });
    tearDown(() => db.close());

    Future<void> run(int from, int to) async {
      for (var s = from; s <= to; s++) {
        now = at(s);
        source.emit(fix(s, (s - from) * 4.0));
        await pumpEventQueue();
      }
    }

    test('an Interval run speaks its steps and beeps its countdown instead of km cues, and saves its steps', () async {
      final rec = make();
      await db.save(db.intervalPlans, {'id': 'p1', 'name': 'One', 'structure': '{}'}); // the plan the Run points at
      await rec.start('interval', plan: const IntervalPlan(name: 'One', reps: 1, rep: StepTarget.meters(200), recovery: StepTarget.time(10)), planId: 'p1');
      await run(0, 300);
      expect(speech.said, [
        'Rep 1 of 1, 200 meters.',
        'Rep 1 done. 50 seconds. Pace 4 10 per kilometer. Recover, 10 seconds.',
        'beep', 'beep', 'beep',
        'Plan done. Cool-down.',
      ]);
      expect(rec.snapshot!.interval!.planDone, isTrue);
      final id = (await rec.finish())!;
      final c = await CardioStore(db).watch(id).first;
      expect((c.type, c.intervalPlanId), ('interval', 'p1'));
      expect([for (final m in (await CardioStore(db).watchTrack(id).first)!.steps!) m.kind], [StepKind.rep, StepKind.recovery, StepKind.cooldown]);
    });

    test('Next ends a step early', () async {
      final rec = make();
      await rec.start('interval', plan: const IntervalPlan(name: 'One', reps: 1, rep: StepTarget.meters(1000), recovery: StepTarget.time(60)));
      await run(0, 20);
      rec.next();
      expect(rec.snapshot!.interval!.kind, StepKind.recovery);
      await rec.discard();
    });

    test('speaks once per km as it is crossed', () async {
      final rec = make();
      await rec.start('run');
      await run(0, 300);
      expect(speech.said, ['Kilometer 1. Time 4 minutes 10 seconds. Pace 4 10 per kilometer.']);
      await rec.finish();
    });

    test('Lap saves with the Run', () async {
      final rec = make();
      await rec.start('run');
      await run(0, 100);
      rec.lap();
      await run(101, 150);
      final id = await rec.finish();
      final track = await CardioStore(db).watchTrack(id!).first;
      expect(track!.laps, [100]);
    });

    test('the notification shows time and distance, and its pause button pauses and resumes', () async {
      final rec = make();
      await rec.start('run');
      await run(0, 30);
      rec.refreshNotification();
      expect(note.last!.movingSec, 30);
      expect(note.last!.distanceM, closeTo(120, 2));
      note.press('pause');
      expect(rec.snapshot!.paused, isTrue);
      expect(note.last!.paused, isTrue);
      note.press('resume');
      await pumpEventQueue();
      expect(rec.snapshot!.paused, isFalse);
      await rec.discard();
      expect(note.cleared, isTrue);
    });
  });
}

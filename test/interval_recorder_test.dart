import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/intervals.dart';
import 'package:timburr/data/recorder.dart';

final t0 = DateTime.utc(2026, 11, 27, 7);
DateTime at(num sec) => t0.add(Duration(milliseconds: (sec * 1000).round()));

/// A fix [sec] seconds after the start, [meters] north of the start point.
PositionSample fix(int sec, double meters) => PositionSample(time: at(sec), lat: 32.0 + meters / 111195, lon: 34.8, accuracy: 5);

/// Feeds a steady [speed] m/s over seconds [from]..[to] inclusive, starting [startM] meters from the origin, and ticks every second as the app does.
void feed(Recorder r, int from, int to, {double speed = 3, double startM = 0}) {
  for (var s = from; s <= to; s++) {
    r.position(fix(s, startM + (s - from) * speed));
    r.tick(at(s));
  }
}

/// The marks as (kind, start, end, sec) and their meters.
List<(StepKind, int, int, int)> shape(List<StepMark> marks) => [for (final m in marks) (m.kind, m.startSec, m.endSec, m.sec)];

List<String> said(Recorder r) => [for (final c in r.voiceCues) c.text ?? 'beep'];

final twoBy300 = IntervalPlan.basic(name: '2 × 300', reps: 2, rep: StepTarget.meters(300), recovery: StepTarget.time(30));

void main() {
  group('Planned Interval run', () {
    test('a distance rep ends where its distance is reached, a time recovery after its seconds, then the rest is cool-down', () {
      final r = Recorder.start('interval', t0, 's1', plan: twoBy300, planId: 'p1');
      feed(r, 0, 280);
      final rec = r.finish(at(280));
      final marks = rec.track!.steps!;
      expect(shape(marks), [
        (StepKind.rep, 0, 100, 100),
        (StepKind.recovery, 100, 130, 30),
        (StepKind.rep, 130, 230, 100),
        (StepKind.recovery, 230, 260, 30),
        (StepKind.cooldown, 260, 280, 20),
      ]);
      expect(marks[0].meters, closeTo(300, 0.5));
      expect(marks[1].meters, closeTo(90, 0.5));
      expect(rec.type, 'interval');
      expect(rec.planId, 'p1');
      expect(rec.plan, twoBy300);
    });

    test('the voice names each step, gives each rep its time and pace, and beeps the last 3 s of a time step', () {
      final r = Recorder.start('interval', t0, 's1', plan: twoBy300);
      feed(r, 0, 280);
      expect(said(r), [
        'Rep 1 of 2, 300 meters.',
        'Rep 1 done. 1 minute 40 seconds. Pace 5 33 per kilometer. Recover, 30 seconds.',
        'beep', 'beep', 'beep',
        'Rep 2 of 2, 300 meters.',
        'Rep 2 done. 1 minute 40 seconds. Pace 5 33 per kilometer. Recover, 30 seconds.',
        'beep', 'beep', 'beep',
        'Plan done. Cool-down.',
      ]);
    });

    test('an Interval run speaks no km cues', () {
      final r = Recorder.start('interval', t0, 's1', plan: twoBy300);
      feed(r, 0, 400);
      expect(r.kmCues, isEmpty);
    });

    test('Next ends the current step early and starts the next one', () {
      final r = Recorder.start('interval', t0, 's1', plan: twoBy300);
      feed(r, 0, 50);
      r.next(at(50));
      feed(r, 51, 60, startM: 153);
      final marks = r.finish(at(60)).track!.steps!;
      expect(shape(marks), [(StepKind.rep, 0, 50, 50), (StepKind.recovery, 50, 60, 10)]);
    });

    test('Pause stops a time step; standing still does not', () {
      final plan = IntervalPlan.basic(name: 't', reps: 1, rep: StepTarget.time(60), recovery: StepTarget.time(60));
      final r = Recorder.start('interval', t0, 's1', plan: plan);
      feed(r, 0, 20);
      r.pause(at(20));
      r.resume(at(50)); // 30 s paused: the rep now ends at 90
      feed(r, 50, 100, startM: 60);
      // the recovery: stand still from 100 on; its clock keeps running, so it ends at 150
      for (var s = 101; s <= 160; s++) {
        r.position(fix(s, 213));
        r.tick(at(s));
      }
      final marks = r.finish(at(160)).track!.steps!;
      expect(shape(marks), [(StepKind.rep, 0, 90, 60), (StepKind.recovery, 90, 150, 60), (StepKind.cooldown, 150, 160, 10)]);
    });

    test('the snapshot shows the step, the rep number and what is left of it', () {
      final r = Recorder.start('interval', t0, 's1', plan: twoBy300);
      feed(r, 0, 40);
      final s = r.snapshot(at(40)).interval!;
      expect(s.kind, StepKind.rep);
      expect(s.rep, 1);
      expect(s.reps, 2);
      expect(s.metersLeft, closeTo(180, 0.5));
      feed(r, 41, 110, startM: 123);
      final rec = r.snapshot(at(110)).interval!;
      expect(rec.kind, StepKind.recovery);
      expect(rec.secondsLeft, 20);
    });

    test('replaying the saved events gives the same steps', () {
      final r = Recorder.start('interval', t0, 's1', plan: twoBy300, planId: 'p1');
      feed(r, 0, 120);
      r.next(at(120));
      feed(r, 121, 200, startM: 363);
      final again = Recorder.replay(r.events);
      expect(shape(again.finish(at(200)).track!.steps!), shape(r.finish(at(200)).track!.steps!));
      expect(again.finish(at(200)).planId, 'p1');
    });
  });

  group('Steps and Repeats', () {
    PlanStep step(String id, StepKind k, StepTarget? t, {int? pace}) => PlanStep(id, k, t, pace: pace);

    test('an open step lasts until Next', () {
      final plan = IntervalPlan(name: 'o', items: [step('w', StepKind.warmup, null), step('r', StepKind.rep, const StepTarget.meters(300))]);
      final r = Recorder.start('interval', t0, 's1', plan: plan);
      feed(r, 0, 200);
      expect(r.snapshot(at(200)).interval!.kind, StepKind.warmup);
      expect(r.snapshot(at(200)).interval!.secondsLeft, isNull);
      r.next(at(200));
      feed(r, 201, 320, startM: 603);
      expect(shape(r.finish(at(320)).track!.steps!).take(2), [(StepKind.warmup, 0, 200, 200), (StepKind.rep, 200, 300, 100)]);
    });

    test('reps are counted across the whole plan, whatever Repeat they are in', () {
      final plan = IntervalPlan(name: 'mix', items: [
        PlanRepeat('x', 2, [step('a', StepKind.rep, const StepTarget.time(10)), step('b', StepKind.recovery, const StepTarget.time(10))]),
        step('c', StepKind.rep, const StepTarget.time(10)),
      ]);
      final r = Recorder.start('interval', t0, 's1', plan: plan);
      feed(r, 0, 45);
      expect(said(r).where((t) => t.contains(' of ')).map((t) => RegExp(r'Rep \d of \d').firstMatch(t)![0]), ['Rep 1 of 3', 'Rep 2 of 3', 'Rep 3 of 3']);
      expect(r.snapshot(at(45)).interval!.step!.id, 'c');
    });

    test('the voice gives a rep\'s Target pace, and its result against it', () {
      final plan = IntervalPlan(name: 'p', items: [step('r', StepKind.rep, const StepTarget.meters(300), pace: 300), step('c', StepKind.cooldown, null)]);
      final r = Recorder.start('interval', t0, 's1', plan: plan);
      feed(r, 0, 110);
      expect(said(r).take(2), ['Rep 1 of 1, 300 meters, at 5 00 per kilometer.', 'Rep 1 done. 1 minute 40 seconds. Pace 5 33 per kilometer. 33 seconds slow. Cool-down.']);
      expect(r.snapshot(at(110)).interval!.step!.pace, isNull);
    });
  });

  group('Free Interval run', () {
    test('starts in warm-up; Switch alternates rep and recovery; the recovery after the last rep is cool-down', () {
      final r = Recorder.start('interval', t0, 's1');
      feed(r, 0, 60);
      r.next(at(60));
      feed(r, 61, 120, startM: 183);
      r.next(at(120));
      feed(r, 121, 150, startM: 363);
      r.next(at(150));
      feed(r, 151, 200, startM: 453);
      r.next(at(200));
      feed(r, 201, 230, startM: 603);
      final rec = r.finish(at(230));
      expect([for (final m in rec.track!.steps!) m.kind], [StepKind.warmup, StepKind.rep, StepKind.recovery, StepKind.rep, StepKind.cooldown]);
      expect(rec.plan, isNull);
      expect(said(r).first, 'Warm-up.');
      expect(said(r)[1], 'Rep 1.');
      expect(said(r)[2], startsWith('Rep 1 done. 1 minute. Pace'));
    });
  });
}

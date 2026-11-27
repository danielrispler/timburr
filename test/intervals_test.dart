import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/intervals.dart';
import 'package:timburr/data/run_analysis.dart';
import 'package:timburr/data/track.dart';

void main() {
  const sixBy400 = IntervalPlan(
    name: '6 × 400',
    warmup: StepTarget.time(600),
    reps: 6,
    rep: StepTarget.meters(400),
    recovery: StepTarget.time(90),
    cooldown: StepTarget.meters(1000),
  );

  group('IntervalPlan', () {
    test('runs as warm-up, then rep and recovery for each rep, then cool-down', () {
      final steps = sixBy400.steps;
      expect(steps.length, 1 + 6 * 2 + 1);
      expect(steps.first.kind, StepKind.warmup);
      expect(steps[1].kind, StepKind.rep);
      expect(steps[1].rep, 1);
      expect(steps[1].target, const StepTarget.meters(400));
      expect(steps[2].kind, StepKind.recovery);
      expect(steps[2].target, const StepTarget.time(90));
      expect(steps[11].rep, 6);
      expect(steps.last.kind, StepKind.cooldown);
    });

    test('warm-up and cool-down are optional', () {
      const plan = IntervalPlan(name: 'Short', reps: 2, rep: StepTarget.time(60), recovery: StepTarget.time(60));
      expect([for (final s in plan.steps) s.kind], [StepKind.rep, StepKind.recovery, StepKind.rep, StepKind.recovery]);
    });

    test('survives a JSON round trip, which is how it is stored and synced', () {
      expect(IntervalPlan.fromJson(sixBy400.toJson()), sixBy400);
      const bare = IntervalPlan(name: 'Bare', reps: 3, rep: StepTarget.time(120), recovery: StepTarget.meters(200));
      expect(IntervalPlan.fromJson(bare.toJson()), bare);
    });

    test('describes itself in one line', () {
      expect(sixBy400.describe(), '10:00 warm-up · 6 × 400 m / 1:30 · 1 km cool-down');
      expect(const IntervalPlan(name: 'x', reps: 5, rep: StepTarget.time(180), recovery: StepTarget.meters(200)).describe(), '5 × 3:00 / 200 m');
    });
  });

  group('A run as it was run', () {
    StepMark m(StepKind k, int start, int end, double meters) => StepMark(k, start, end, end - start, meters);
    final free = [
      m(StepKind.warmup, 0, 598, 1500),
      m(StepKind.rep, 598, 690, 410),
      m(StepKind.recovery, 690, 778, 180),
      m(StepKind.rep, 778, 874, 395),
      m(StepKind.recovery, 874, 966, 170),
      m(StepKind.rep, 966, 1056, 405),
      m(StepKind.cooldown, 1056, 1360, 900),
    ];

    test('Save as plan turns the reps into a distance rounded to 100 m and the rest into times rounded to 5 s', () {
      expect(planFromSteps(free, name: 'Tuesday 400s'), const IntervalPlan(
        name: 'Tuesday 400s',
        warmup: StepTarget.time(600),
        reps: 3,
        rep: StepTarget.meters(400),
        recovery: StepTarget.time(90),
        cooldown: StepTarget.time(305),
      ));
    });

    test('a single rep with no recovery still gives a plan, with a 1:00 recovery', () {
      final plan = planFromSteps([m(StepKind.warmup, 0, 60, 150), m(StepKind.rep, 60, 300, 1000), m(StepKind.cooldown, 300, 400, 200)], name: 'x');
      expect((plan.reps, plan.rep, plan.recovery), (1, const StepTarget.meters(1000), const StepTarget.time(60)));
    });

    test('the summary is the average pace over all reps and the fastest rep', () {
      final s = summarizeReps(free)!;
      expect(s.reps, 3);
      expect(s.avgPaceSecPerKm, closeTo(278 / 1.21, 0.01)); // 92 + 96 + 90 s over 410 + 395 + 405 m
      expect(s.fastest.startSec, 966); // 90 s for 405 m
      expect(summarizeReps([m(StepKind.warmup, 0, 60, 150)]), isNull);
    });
  });

  test('a step\'s heart rate is the average of the readings inside it', () {
    final t = Track(time: [0, 10, 20, 30, 40], hr: [100, 150, 160, null, 120]);
    expect(stepAvgHr(t, const StepMark(StepKind.rep, 10, 30, 20, 100)), 155);
    expect(stepAvgHr(t, const StepMark(StepKind.recovery, 30, 40, 10, 20)), isNull);
    expect(stepAvgHr(Track(time: [0, 10]), const StepMark(StepKind.rep, 0, 10, 10, 30)), isNull);
  });
}

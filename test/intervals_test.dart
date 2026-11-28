import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/intervals.dart';
import 'package:timburr/data/run_analysis.dart';
import 'package:timburr/data/track.dart';

void main() {
  final sixBy400 = IntervalPlan.basic(
    name: '6 × 400',
    warmup: const StepTarget.time(600),
    reps: 6,
    rep: const StepTarget.meters(400),
    recovery: const StepTarget.time(90),
    cooldown: const StepTarget.meters(1000),
  );
  PlanStep step(String id, StepKind k, StepTarget? t, {int? pace}) => PlanStep(id, k, t, pace: pace);
  final mixed = IntervalPlan(name: 'Mixed', items: [
    step('w', StepKind.warmup, null),
    PlanRepeat('a', 2, [step('k', StepKind.rep, const StepTarget.meters(1000), pace: 240), step('r', StepKind.recovery, const StepTarget.time(120))]),
    PlanRepeat('b', 4, [step('s', StepKind.rep, const StepTarget.meters(200))]),
    step('c', StepKind.cooldown, const StepTarget.time(600)),
  ]);

  group('IntervalPlan', () {
    test('the old fixed shape runs as warm-up, then rep and recovery for each rep, then cool-down', () {
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
      expect(sixBy400.reps, 6);
    });

    test('Steps and Repeats run in order, each Repeat written out, the reps counted across the whole plan', () {
      final steps = mixed.steps;
      expect([for (final s in steps) s.step.id], ['w', 'k', 'r', 'k', 'r', 's', 's', 's', 's', 'c']);
      expect([for (final s in steps) s.rep], [null, 1, 1, 2, 2, 3, 4, 5, 6, 6]);
      expect(mixed.reps, 6);
      expect([for (final s in mixed.allSteps) s.id], ['w', 'k', 'r', 's', 'c']);
    });

    test('survives a JSON round trip, which is how it is stored and synced', () {
      expect(IntervalPlan.fromJson(sixBy400.toJson()), sixBy400);
      expect(IntervalPlan.fromJson(mixed.toJson()), mixed);
      expect(IntervalPlan.fromJson(mixed.toJson()).steps[1].step.pace, 240);
      expect(IntervalPlan.fromJson(mixed.toJson()).steps.first.target, isNull);
    });

    test('a plan stored in the old fixed shape reads as that shape, with fixed ids', () {
      final old = IntervalPlan.fromJson({'name': 'Old', 'warmup': {'s': 600}, 'reps': 3, 'rep': {'m': 400}, 'recovery': {'s': 90}});
      expect(old, IntervalPlan.basic(name: 'Old', warmup: const StepTarget.time(600), reps: 3, rep: const StepTarget.meters(400), recovery: const StepTarget.time(90)));
      expect([for (final s in old.allSteps) s.id], ['warmup', 'rep', 'recovery']);
    });

    test('describes itself in one line', () {
      expect(sixBy400.describe(), '10:00 warm-up · 6 × (400 m / 1:30) · 1 km cool-down');
      expect(mixed.describe(), 'open warm-up · 2 × (1 km / 2:00) · 4 × 200 m · 10:00 cool-down');
    });
  });

  group('Last time', () {
    StepMark m(StepKind k, int sec, double meters) => StepMark(k, 0, sec, sec, meters);
    final twoK = IntervalPlan(name: '2 × 1k', items: [
      PlanRepeat('x', 2, [step('k', StepKind.rep, const StepTarget.meters(1000)), step('r', StepKind.recovery, const StepTarget.time(60))]),
      step('c', StepKind.cooldown, null),
    ]);
    final whole = [m(StepKind.rep, 240, 1000), m(StepKind.recovery, 60, 150), m(StepKind.rep, 260, 1000), m(StepKind.recovery, 60, 150), m(StepKind.cooldown, 300, 1000)];

    test('is each Step\'s pace averaged over its rounds; the plan\'s last cool-down counts though it ran until Finish', () {
      final last = lastTimes([(twoK, whole)]);
      expect(last['k']!.paceSecPerKm, 250); // 500 s over 2 km
      expect(last['r']!.paceSecPerKm, 400); // 120 s over 300 m
      expect(last['c']!.paceSecPerKm, 300);
    });

    test('comes from the newest Run that ran the Step; the step a Run was finished in does not count', () {
      final stopped = [m(StepKind.rep, 200, 1000), m(StepKind.recovery, 30, 70)]; // finished during the first recovery
      final last = lastTimes([(twoK, stopped), (twoK, whole)]);
      expect(last['k']!.paceSecPerKm, 200);
      expect(last['r']!.paceSecPerKm, 400);
    });

    test('fits a Step only while its kind and length are the same', () {
      final l = lastTimes([(twoK, whole)])['k']!;
      final k = twoK.allSteps.first;
      expect(l.fits(k), isTrue);
      expect(l.fits(k.copy(pace: () => 230)), isTrue);
      expect(l.fits(k.copy(target: () => const StepTarget.meters(800))), isFalse);
      expect(l.fits(k.copy(kind: StepKind.warmup)), isFalse);
    });

    test('skips marks that do not match the plan\'s step', () {
      final freeSaved = [m(StepKind.rep, 240, 1000), m(StepKind.cooldown, 300, 1000)]; // a free run saved as a plan with a recovery after the rep
      expect(lastTimes([(twoK, freeSaved)]).keys, ['k']);
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
      expect(planFromSteps(free, name: 'Tuesday 400s'), IntervalPlan.basic(
        name: 'Tuesday 400s',
        warmup: const StepTarget.time(600),
        reps: 3,
        rep: const StepTarget.meters(400),
        recovery: const StepTarget.time(90),
        cooldown: const StepTarget.time(305),
      ));
    });

    test('a single rep with no recovery still gives a plan, with a 1:00 recovery', () {
      final plan = planFromSteps([m(StepKind.warmup, 0, 60, 150), m(StepKind.rep, 60, 300, 1000), m(StepKind.cooldown, 300, 400, 200)], name: 'x');
      expect(plan.describe(), '1:00 warm-up · 1 × (1 km / 1:00) · 1:40 cool-down');
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

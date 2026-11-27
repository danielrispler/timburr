/// Interval runs: the plan Daniel runs to and the steps a recording marks. Pure code; the store is in interval_store.dart.
library;

/// The parts of an Interval run, in the words of the glossary.
enum StepKind { warmup, rep, recovery, cooldown }

/// How long a step lasts: a distance in meters or a time in seconds, never both.
class StepTarget {
  const StepTarget.meters(int this.meters) : seconds = null;
  const StepTarget.time(int this.seconds) : meters = null;

  final int? meters;
  final int? seconds;

  bool get isTime => seconds != null;

  Map<String, Object?> toJson() => isTime ? {'s': seconds} : {'m': meters};

  static StepTarget? fromJson(Object? j) => switch (j) {
        {'s': num s} => StepTarget.time(s.round()),
        {'m': num m} => StepTarget.meters(m.round()),
        _ => null,
      };

  /// "400 m", "1.5 km", "1:30".
  String describe() => isTime ? clock(seconds!) : distanceLabel(meters!);

  @override
  bool operator ==(Object other) => other is StepTarget && other.meters == meters && other.seconds == seconds;

  @override
  int get hashCode => Object.hash(meters, seconds);
}

/// "400 m" under a km, else "1 km", "1.5 km".
String distanceLabel(num meters) {
  if (meters < 1000) return '${meters.round()} m';
  final km = meters / 1000;
  return '${km == km.roundToDouble() ? km.toInt() : double.parse(km.toStringAsFixed(2))} km';
}

/// "m:ss".
String clock(int sec) => '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';

/// One step of a plan, in running order. [rep] numbers a rep and the recovery after it, from 1.
class PlannedStep {
  const PlannedStep(this.kind, this.target, {this.rep});
  final StepKind kind;
  final StepTarget target;
  final int? rep;
}

/// A saved, named structure for an Interval run: an optional warm-up, [reps] × ([rep] + [recovery]), an optional cool-down.
class IntervalPlan {
  const IntervalPlan({required this.name, this.warmup, required this.reps, required this.rep, required this.recovery, this.cooldown});

  final String name;
  final StepTarget? warmup, cooldown;
  final int reps;
  final StepTarget rep, recovery;

  List<PlannedStep> get steps => [
        if (warmup != null) PlannedStep(StepKind.warmup, warmup!),
        for (var i = 1; i <= reps; i++) ...[PlannedStep(StepKind.rep, rep, rep: i), PlannedStep(StepKind.recovery, recovery, rep: i)],
        if (cooldown != null) PlannedStep(StepKind.cooldown, cooldown!),
      ];

  /// The shape stored in `interval_plans.structure` and copied to `cardio.interval_plan` (with the name).
  Map<String, Object?> toJson() => {
        'name': name,
        if (warmup != null) 'warmup': warmup!.toJson(),
        'reps': reps,
        'rep': rep.toJson(),
        'recovery': recovery.toJson(),
        if (cooldown != null) 'cooldown': cooldown!.toJson(),
      };

  factory IntervalPlan.fromJson(Map<String, Object?> j) => IntervalPlan(
        name: j['name'] as String? ?? '',
        warmup: StepTarget.fromJson(j['warmup']),
        reps: (j['reps'] as num).round(),
        rep: StepTarget.fromJson(j['rep'])!,
        recovery: StepTarget.fromJson(j['recovery'])!,
        cooldown: StepTarget.fromJson(j['cooldown']),
      );

  IntervalPlan named(String name) => IntervalPlan(name: name, warmup: warmup, reps: reps, rep: rep, recovery: recovery, cooldown: cooldown);

  /// "10:00 warm-up · 6 × 400 m / 1:30 · 1 km cool-down".
  String describe() => [
        if (warmup != null) '${warmup!.describe()} warm-up',
        '$reps × ${rep.describe()} / ${recovery.describe()}',
        if (cooldown != null) '${cooldown!.describe()} cool-down',
      ].join(' · ');

  @override
  bool operator ==(Object other) =>
      other is IntervalPlan && other.name == name && other.warmup == warmup && other.reps == reps && other.rep == rep && other.recovery == recovery && other.cooldown == cooldown;

  @override
  int get hashCode => Object.hash(name, warmup, reps, rep, recovery, cooldown);
}

/// One step as it was run, stored with the Run's track (`Track.steps`). Seconds are from the Run's start; [sec] is the step's clock time without
/// Daniel's pauses, [meters] its GPS distance.
class StepMark {
  const StepMark(this.kind, this.startSec, this.endSec, this.sec, this.meters);

  final StepKind kind;
  final int startSec, endSec, sec;
  final double meters;

  /// Seconds per km, null without distance.
  double? get paceSecPerKm => meters > 0 ? sec / (meters / 1000) : null;

  StepMark shifted(int seconds) => StepMark(kind, startSec + seconds, endSec + seconds, sec, meters);

  StepMark as(StepKind k) => StepMark(k, startSec, endSec, sec, meters);

  List<Object> toJson() => [kind.name, startSec, endSec, sec, meters];

  static StepMark fromJson(List<Object?> j) =>
      StepMark(StepKind.values.byName(j[0] as String), (j[1] as num).round(), (j[2] as num).round(), (j[3] as num).round(), (j[4] as num).toDouble());
}

/// A plan from a Run's [steps] as they were run (Save as plan, for a free Interval run): the reps as their average distance rounded to 100 m, the
/// warm-up, recoveries and cool-down as their average time rounded to 5 s. A Run with no recovery gets a 1:00 one.
IntervalPlan planFromSteps(List<StepMark> steps, {required String name}) {
  List<StepMark> of(StepKind k) => [for (final s in steps) if (s.kind == k) s];
  int round(num v, int to) => (v / to).round() * to;
  StepTarget? time(List<StepMark> ms) {
    if (ms.isEmpty) return null;
    final s = round(ms.map((m) => m.sec).reduce((a, b) => a + b) / ms.length, 5);
    return s > 0 ? StepTarget.time(s) : null;
  }

  final reps = of(StepKind.rep);
  final meters = reps.isEmpty ? 0 : reps.map((m) => m.meters).reduce((a, b) => a + b) / reps.length;
  return IntervalPlan(
    name: name,
    warmup: time(of(StepKind.warmup)),
    reps: reps.isEmpty ? 1 : reps.length,
    rep: StepTarget.meters(round(meters, 100) < 100 ? 100 : round(meters, 100)),
    recovery: time(of(StepKind.recovery)) ?? const StepTarget.time(60),
    cooldown: time(of(StepKind.cooldown)),
  );
}

/// How the reps of one Interval run went: their average pace (all rep time over all rep distance) and the fastest one by pace.
class RepSummary {
  const RepSummary(this.reps, this.avgPaceSecPerKm, this.fastest);
  final int reps;
  final double avgPaceSecPerKm;
  final StepMark fastest;
}

/// Null when [steps] has no rep with distance.
RepSummary? summarizeReps(List<StepMark> steps) {
  final reps = [for (final s in steps) if (s.kind == StepKind.rep && s.paceSecPerKm != null) s];
  if (reps.isEmpty) return null;
  final sec = reps.fold(0, (n, r) => n + r.sec), m = reps.fold(0.0, (n, r) => n + r.meters);
  final fastest = reps.reduce((a, b) => b.paceSecPerKm! < a.paceSecPerKm! ? b : a);
  return RepSummary(reps.length, sec / (m / 1000), fastest);
}

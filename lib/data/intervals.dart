/// Interval runs: the plan Daniel runs to and the steps a recording marks. Pure code; the store is in interval_store.dart.
library;

import 'dart:convert';
import 'dart:math';

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

/// A new id for a Step or Repeat, unique within its plan.
String newPlanItemId() => List.generate(8, (_) => Random().nextInt(16).toRadixString(16)).join();

/// One Step or Repeat of an Interval plan. [id] stays with it through edits, so a Step keeps its Last time when it moves.
sealed class PlanItem {
  const PlanItem(this.id);
  final String id;

  Map<String, Object?> toJson();

  static PlanItem fromJson(Map<String, Object?> j) => j.containsKey('x')
      ? PlanRepeat(j['id'] as String, (j['x'] as num).round(), [for (final s in j['steps'] as List) PlanStep.fromJson((s as Map).cast())])
      : PlanStep.fromJson(j);
}

/// A Step: its kind, its length ([target] null is open: it lasts until Next) and its Target pace in seconds per km.
class PlanStep extends PlanItem {
  const PlanStep(super.id, this.kind, this.target, {this.pace});

  final StepKind kind;
  final StepTarget? target;
  final int? pace;

  PlanStep copy({String? id, StepKind? kind, StepTarget? Function()? target, int? Function()? pace}) =>
      PlanStep(id ?? this.id, kind ?? this.kind, target == null ? this.target : target(), pace: pace == null ? this.pace : pace());

  @override
  Map<String, Object?> toJson() => {'id': id, 'k': kind.name, if (target != null) 't': target!.toJson(), 'p': ?pace};

  factory PlanStep.fromJson(Map<String, Object?> j) =>
      PlanStep(j['id'] as String, StepKind.values.byName(j['k'] as String), StepTarget.fromJson(j['t']), pace: (j['p'] as num?)?.round());
}

/// A Repeat: its [steps] run [times] times in a row.
class PlanRepeat extends PlanItem {
  const PlanRepeat(super.id, this.times, this.steps);

  final int times;
  final List<PlanStep> steps;

  PlanRepeat copy({int? times, List<PlanStep>? steps}) => PlanRepeat(id, times ?? this.times, steps ?? this.steps);

  @override
  Map<String, Object?> toJson() => {'id': id, 'x': times, 'steps': [for (final s in steps) s.toJson()]};
}

/// One step of a plan as it runs, in running order. [rep] counts the reps so far, from 1; [step] is the Step it comes from.
class PlannedStep {
  const PlannedStep(this.step, this.rep);
  final PlanStep step;
  final int? rep;

  StepKind get kind => step.kind;
  StepTarget? get target => step.target;
}

/// A saved, named list of Steps and Repeats for an Interval run.
class IntervalPlan {
  const IntervalPlan({required this.name, required this.items});

  /// The old fixed shape, which every plan had before Repeats: an optional warm-up, [reps] × ([rep] + [recovery]), an optional cool-down.
  /// Its ids are fixed, so an old plan and the old copies kept by its Runs agree on them.
  factory IntervalPlan.basic({required String name, StepTarget? warmup, required int reps, required StepTarget rep, required StepTarget recovery, StepTarget? cooldown}) =>
      IntervalPlan(name: name, items: [
        if (warmup != null) PlanStep('warmup', StepKind.warmup, warmup),
        PlanRepeat('repeat', reps, [PlanStep('rep', StepKind.rep, rep), PlanStep('recovery', StepKind.recovery, recovery)]),
        if (cooldown != null) PlanStep('cooldown', StepKind.cooldown, cooldown),
      ]);

  final String name;
  final List<PlanItem> items;

  /// Every step in running order, each Repeat written out.
  List<PlannedStep> get steps {
    var rep = 0;
    final out = <PlannedStep>[];
    void add(PlanStep s) => out.add(PlannedStep(s, s.kind == StepKind.rep ? ++rep : rep == 0 ? null : rep));
    for (final item in items) {
      switch (item) {
        case PlanStep():
          add(item);
        case PlanRepeat():
          for (var i = 0; i < item.times; i++) {
            item.steps.forEach(add);
          }
      }
    }
    return out;
  }

  /// How many reps the plan runs, counting every round.
  int get reps => steps.where((s) => s.kind == StepKind.rep).length;

  /// The Steps, each once, in the order they first appear.
  List<PlanStep> get allSteps => [for (final i in items) ...switch (i) { PlanStep() => [i], PlanRepeat() => i.steps }];

  /// The shape stored in `interval_plans.structure` and copied to `cardio.interval_plan` (with the name).
  Map<String, Object?> toJson() => {'name': name, 'items': [for (final i in items) i.toJson()]};

  /// Reads both shapes: the list of items, and the old fixed one (see [IntervalPlan.basic]).
  factory IntervalPlan.fromJson(Map<String, Object?> j) {
    final name = j['name'] as String? ?? '';
    if (j['items'] case final List items) return IntervalPlan(name: name, items: [for (final i in items) PlanItem.fromJson((i as Map).cast())]);
    return IntervalPlan.basic(
      name: name,
      warmup: StepTarget.fromJson(j['warmup']),
      reps: (j['reps'] as num).round(),
      rep: StepTarget.fromJson(j['rep'])!,
      recovery: StepTarget.fromJson(j['recovery'])!,
      cooldown: StepTarget.fromJson(j['cooldown']),
    );
  }

  IntervalPlan named(String name) => IntervalPlan(name: name, items: items);

  /// "10:00 warm-up · 6 × (400 m / 1:30) · 1 km cool-down". Inside a Repeat a rep or recovery is just its length.
  String describe() {
    String step(PlanStep s, {bool bare = false}) {
      final size = s.target?.describe() ?? 'open';
      if (bare && (s.kind == StepKind.rep || s.kind == StepKind.recovery)) return size;
      return '$size ${stepWord(s.kind)}';
    }

    return [
      for (final i in items)
        switch (i) {
          PlanStep() => step(i),
          PlanRepeat(steps: [final only]) => '${i.times} × ${step(only, bare: true)}',
          PlanRepeat() => '${i.times} × (${i.steps.map((s) => step(s, bare: true)).join(' / ')})',
        },
    ].join(' · ');
  }

  @override
  bool operator ==(Object other) => other is IntervalPlan && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// "warm-up", "rep", "recovery", "cool-down".
String stepWord(StepKind k) => switch (k) {
      StepKind.warmup => 'warm-up',
      StepKind.rep => 'rep',
      StepKind.recovery => 'recovery',
      StepKind.cooldown => 'cool-down',
    };

/// A Step's Last time: the pace it was run at, and the kind and length it had then.
class LastTime {
  const LastTime(this.kind, this.target, this.paceSecPerKm);
  final StepKind kind;
  final StepTarget? target;
  final double paceSecPerKm;

  /// False once [s] has a different kind or length: the old pace would mislead.
  bool fits(PlanStep s) => s.kind == kind && s.target == target;
}

/// Each Step's Last time, by Step id, from the Interval runs of one plan, newest first: each Run's copy of the plan and its steps as run.
/// A Step's Last time comes from the newest Run that ran it, averaged over its rounds (all its time over all its distance). The step a Run was
/// finished in counts only when it is the plan's last step and a cool-down, which runs until Finish anyway.
Map<String, LastTime> lastTimes(Iterable<(IntervalPlan, List<StepMark>)> newestFirst) {
  final out = <String, LastTime>{};
  for (final (plan, marks) in newestFirst) {
    final planned = plan.steps;
    final sec = <String, int>{}, meters = <String, double>{}, step = <String, PlanStep>{};
    for (var i = 0; i < planned.length && i < marks.length; i++) {
      final s = planned[i].step, m = marks[i];
      final whole = i < marks.length - 1 || (i == planned.length - 1 && s.kind == StepKind.cooldown);
      if (!whole || m.kind != s.kind || out.containsKey(s.id)) continue;
      sec[s.id] = (sec[s.id] ?? 0) + m.sec;
      meters[s.id] = (meters[s.id] ?? 0) + m.meters;
      step[s.id] = s;
    }
    for (final id in sec.keys) {
      if (meters[id]! > 0) out[id] = LastTime(step[id]!.kind, step[id]!.target, sec[id]! / (meters[id]! / 1000));
    }
  }
  return out;
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
/// warm-up, recoveries and cool-down as their average time rounded to 5 s, the reps and recoveries in one Repeat. A Run with no recovery gets a 1:00 one.
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
  return IntervalPlan.basic(
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

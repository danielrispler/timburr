import 'db.dart';

/// Epley estimated 1RM. A 1-rep set is its own weight.
double e1rm(double weightKg, int reps) => reps <= 0 ? 0 : (reps == 1 ? weightKg : weightKg * (1 + reps / 30));

/// Sum of weight × reps over done sets.
double sessionVolume(Iterable<WorkoutSet> sets) =>
    sets.where((s) => s.done).fold(0, (t, s) => t + (s.weightKg ?? 0) * (s.reps ?? 0));

/// Per-set metrics by load type; the first is the one that ranks a session's best set.
Map<String, double Function(WorkoutSet)> setMetrics(String loadType) => switch (loadType) {
      'timed' => {'duration': (s) => (s.durationSec ?? 0).toDouble()},
      'bodyweight' => {'reps': (s) => (s.reps ?? 0).toDouble(), 'added': (s) => s.weightKg ?? 0},
      _ => {'e1rm': (s) => e1rm(s.weightKg ?? 0, s.reps ?? 0), 'weight': (s) => s.weightKg ?? 0},
    };

/// Records over [sessions] (each one exercise's sets in one workout), done sets only.
/// Weighted also gets 'volume' (best session volume). Empty when nothing is done.
Map<String, double> records(String loadType, Iterable<Iterable<WorkoutSet>> sessions) {
  final out = <String, double>{};
  for (final sets in sessions) {
    for (final s in sets.where((s) => s.done)) {
      for (final MapEntry(:key, :value) in setMetrics(loadType).entries) {
        final v = value(s);
        if (v > (out[key] ?? double.negativeInfinity)) out[key] = v;
      }
    }
    if (loadType == 'weighted' && sets.any((s) => s.done)) {
      final v = sessionVolume(sets);
      if (v > (out['volume'] ?? double.negativeInfinity)) out['volume'] = v;
    }
  }
  return out;
}

/// Ids of [current] sets that get the PR badge: at most one, the best done set that strictly
/// beats a per-set record from [previous]. None when [previous] has no done sets.
Set<String> prBadges(String loadType, Iterable<Iterable<WorkoutSet>> previous, Iterable<WorkoutSet> current) {
  final rec = records(loadType, previous);
  if (rec.isEmpty) return {};
  final metrics = setMetrics(loadType);
  final beats = current
      .where((s) => s.done && metrics.entries.any((m) => m.value(s) > (rec[m.key] ?? double.negativeInfinity)))
      .toList();
  if (beats.isEmpty) return {};
  final rank = metrics.values.first;
  return {beats.reduce((a, b) => rank(b) > rank(a) ? b : a).id};
}

typedef Series = List<(DateTime, double)>;

/// Per-session chart points from [sessions] (date, sets), done sets only.
/// Sessions with no done set get no point.
({Series maxWeight, Series e1rm, Series volume}) chartSeries(Iterable<(DateTime, Iterable<WorkoutSet>)> sessions) {
  final Series w = [], e = [], v = [];
  for (final (at, sets) in sessions) {
    final done = sets.where((s) => s.done);
    if (done.isEmpty) continue;
    w.add((at, done.map((s) => s.weightKg ?? 0).reduce((a, b) => a > b ? a : b)));
    e.add((at, done.map((s) => e1rm(s.weightKg ?? 0, s.reps ?? 0)).reduce((a, b) => a > b ? a : b)));
    v.add((at, sessionVolume(done)));
  }
  return (maxWeight: w, e1rm: e, volume: v);
}

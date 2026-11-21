import 'dart:math';

import 'best_efforts.dart';

/// Riegel's formula: the time in seconds to run [d2] meters when [t1] seconds were run over [d1] meters.
double riegel(double t1, double d1, double d2) => t1 * pow(d2 / d1, 1.06);

/// The races predicted, by the key of their Best effort distance.
const predictedDistances = [5000, 10000, 21098];

/// Only Best efforts from this many days back feed a prediction: fitness changes.
const predictionWindowDays = 90;

/// An effort shorter than this (a mile) says too little about a race.
const _minSourceM = 1609;

/// A predicted time over [distanceM], from the Best effort over [fromDistanceM] on [from].
typedef Prediction = ({int distanceM, double seconds, int fromDistanceM, DateTime from});

/// Riegel predictions for 5 km, 10 km and the half marathon from the Best efforts of the last [predictionWindowDays] days before [now].
/// Each race uses the fastest prediction among efforts between a fifth of its distance and twice it (and at least a mile); the effort at the race's own
/// distance predicts itself. A race no effort can predict is left out.
List<Prediction> predictRaces(Iterable<Effort> efforts, DateTime now) {
  final since = now.subtract(const Duration(days: predictionWindowDays));
  final recent = [for (final e in efforts) if (!e.startedAt.isBefore(since) && !e.startedAt.isAfter(now)) e];
  final out = <Prediction>[];
  for (final target in predictedDistances) {
    final meters = effortDistances[target]!;
    Prediction? best;
    for (final e in recent) {
      final d = effortDistances[e.distanceM];
      if (d == null || d < _minSourceM || d < meters / 5 || d > meters * 2) continue;
      final s = e.distanceM == target ? e.seconds : riegel(e.seconds, d, meters);
      if (best == null || s < best.seconds) best = (distanceM: target, seconds: s, fromDistanceM: e.distanceM, from: e.startedAt);
    }
    if (best != null) out.add(best);
  }
  return out;
}

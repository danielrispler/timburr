import 'package:drift/drift.dart';

import 'db.dart';
import 'run_analysis.dart' show timedIndices;
import 'track.dart';

/// The distances Best efforts are kept for, by the key stored in `best_efforts.distance_m`, and their true length in meters.
const effortDistances = <int, double>{400: 400, 1000: 1000, 1609: 1609.344, 5000: 5000, 10000: 10000, 21098: 21097.5};

/// What each distance is called.
const effortLabels = {400: '400 m', 1000: '1 km', 1609: '1 mile', 5000: '5 km', 10000: '10 km', 21098: 'Half marathon'};

/// A window spanning a gap between two points longer than this is a GPS gap and doesn't count.
const maxGapSec = 30;

/// A window spanning two points that imply a faster speed than this (m/s) doesn't count either: the distance jumped, as some exports do between
/// a first point at 0 and the next carrying the Run's total or the first block of distance.
const maxSpeed = 12.0;

/// The fastest time in seconds for each standard distance the track covers, by a sliding window with the edge interpolated between points.
/// Needs time and distance. A window that spans a gap over [maxGapSec] between two points doesn't count.
Map<int, double> findBestEfforts(Track t) {
  // Only points where the distance moved: some exports repeat a stale distance on every point between updates (Strava from a watch, one every ~30 s).
  // A gap is judged on the raw points, so those stale points still show the track was recorded.
  final time = <double>[], dist = <double>[];
  final gaps = <int>[0]; // gaps[k] = unusable segments among the first k (segment k joins kept points k and k+1)
  var rawGap = 0.0, prevTime = 0.0;
  for (final i in timedIndices(t)) {
    final tm = t.time![i]!.toDouble(), d = t.distance![i]!;
    if (time.isNotEmpty) rawGap = rawGap > tm - prevTime ? rawGap : tm - prevTime;
    prevTime = tm;
    if (dist.isNotEmpty && d <= dist.last) continue;
    if (dist.isNotEmpty) {
      final dt = tm - time.last;
      gaps.add(gaps.last + (rawGap > maxGapSec || d - dist.last > maxSpeed * (dt < 1 ? 1 : dt) ? 1 : 0));
    }
    time.add(tm);
    dist.add(d);
    rawGap = 0;
  }
  final n = dist.length;
  if (n < 2) return const {};
  // Index of the last point at or before distance [d] (d is at least dist[0]).
  int lastAtOrBefore(double d) {
    var lo = 0, hi = n - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (dist[mid] <= d) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  // Time at distance [d], between points [i] and the next, where dist[i] <= d < dist[i + 1].
  double timeAt(double d, int i) => time[i] + (time[i + 1] - time[i]) * (d - dist[i]) / (dist[i + 1] - dist[i]);

  final out = <int, double>{};
  for (final MapEntry(key: key, value: w) in effortDistances.entries) {
    double? best;
    void offer(double s) {
      if (s > 0 && (best == null || s < best!)) best = s;
    }

    for (var j = 1; j < n; j++) { // windows ending at a point
      final s = dist[j] - w;
      if (s < dist[0]) continue;
      final i = lastAtOrBefore(s);
      if (i >= j || gaps[j] - gaps[i] > 0) continue;
      offer(time[j] - (s == dist[i] ? time[i] : timeAt(s, i)));
    }
    for (var i = 0; i < n - 1; i++) { // windows starting at a point
      final e = dist[i] + w;
      if (e > dist[n - 1]) break;
      final k = lastAtOrBefore(e);
      if (dist[k] == e) {
        if (k > i && gaps[k] - gaps[i] == 0) offer(time[k] - time[i]);
      } else if (gaps[k + 1] - gaps[i] == 0) {
        offer(timeAt(e, k) - time[i]);
      }
    }
    if (best != null) out[key] = best!;
  }
  return out;
}

/// One Best effort with when its Run started.
typedef Effort = ({String cardioId, int distanceM, double seconds, DateTime startedAt});

/// The [n] fastest efforts over [distanceM], one per Run, fastest first; ties go to the earlier Run.
List<Effort> topEfforts(Iterable<Effort> all, int distanceM, {int n = 5}) =>
    ([for (final e in all) if (e.distanceM == distanceM) e]..sort((a, b) => a.seconds != b.seconds ? a.seconds.compareTo(b.seconds) : a.startedAt.compareTo(b.startedAt))).take(n).toList();

/// The PR (fastest ever) at [distanceM], or null when there is no effort.
Effort? prAt(Iterable<Effort> all, int distanceM) => topEfforts(all, distanceM, n: 1).firstOrNull;

extension BestEffortCache on AppDb {
  /// Recomputes the cached Best efforts of the Runs [ids] (every Run when null) from their tracks. Only live outdoor Runs count; a Treadmill run, a deleted Run or a missing track leaves none.
  Future<void> rebuildBestEfforts([Iterable<String>? ids]) => transaction(() async {
        final wanted = ids?.toSet();
        if (wanted != null && wanted.isEmpty) return;
        final stale = delete(bestEfforts);
        if (wanted != null) stale.where((b) => b.cardioId.isIn(wanted));
        await stale.go();
        final runs = select(cardio)..where((c) => c.deletedAt.isNull() & c.type.equals('run'));
        if (wanted != null) runs.where((c) => c.id.isIn(wanted));
        for (final run in await runs.get()) {
          final row = await (select(cardioTracks)..where((x) => x.cardioId.equals(run.id) & x.deletedAt.isNull())).getSingleOrNull();
          if (row == null) continue;
          final Track decoded;
          try {
            decoded = Track.decode(row.points);
          } on Exception {
            continue; // a damaged track must not block a save, sync or restore; the Run just has no efforts
          }
          for (final MapEntry(:key, :value) in findBestEfforts(decoded).entries) {
            await into(bestEfforts).insert(BestEffortsCompanion.insert(cardioId: run.id, distanceM: key, seconds: value));
          }
        }
      });

  /// Every cached effort of a live Run, with the Run's start.
  Stream<List<Effort>> watchBestEfforts() {
    final q = select(bestEfforts).join([innerJoin(cardio, cardio.id.equalsExp(bestEfforts.cardioId))])..where(cardio.deletedAt.isNull());
    return q.watch().map((rows) => [
          for (final r in rows)
            (cardioId: r.readTable(bestEfforts).cardioId, distanceM: r.readTable(bestEfforts).distanceM, seconds: r.readTable(bestEfforts).seconds, startedAt: r.readTable(cardio).startedAt),
        ]);
  }
}

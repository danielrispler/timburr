import 'intervals.dart';
import 'track.dart';

/// One kilometer of a Run (the last may be shorter): how long it took and the average heart rate over it.
class KmSplit {
  KmSplit(this.index, this.distanceM, this.seconds, this.avgHr);
  final int index; // 1 for the first km
  final double distanceM;
  final double seconds;
  final int? avgHr;

  double get paceSecPerKm => seconds / (distanceM / 1000);
}

/// A final stretch shorter than this is dropped instead of shown as a split (its pace would be noise).
const minLastSplitM = 100.0;

/// Indices of [t] that have both time and distance, with distances that never go backwards.
List<int> timedIndices(Track t) {
  final time = t.time, dist = t.distance;
  if (time == null || dist == null) return const [];
  final idx = <int>[];
  for (var i = 0; i < time.length && i < dist.length; i++) {
    if (time[i] == null || dist[i] == null) continue;
    if (idx.isNotEmpty && dist[i]! < dist[idx.last]!) continue; // a GPS jump backwards
    idx.add(i);
  }
  return idx;
}

/// Splits of [t] per km. Needs time and distance; no splits without them. Km marks are interpolated between the two points around them.
List<KmSplit> splitsPerKm(Track track) {
  final t = withGpsDistance(track);
  final idx = timedIndices(t);
  if (idx.length < 2) return const [];
  final time = t.time!, dist = t.distance!;
  final splits = <KmSplit>[];
  var d0 = dist[idx.first]!, t0 = time[idx.first]!.toDouble(); // where the current split began
  var hrs = <int>[];
  void addHr(int i) {
    final v = t.hr != null && i < t.hr!.length ? t.hr![i] : null;
    if (v != null) hrs.add(v);
  }

  int? avg() => hrs.isEmpty ? null : (hrs.reduce((a, b) => a + b) / hrs.length).round();
  addHr(idx.first);
  for (var k = 1; k < idx.length; k++) {
    final i = idx[k], p = idx[k - 1];
    final di = dist[i]!, ti = time[i]!.toDouble(), dp = dist[p]!, tp = time[p]!.toDouble();
    while (di >= d0 + 1000 && di > dp) {
      final mark = d0 + 1000;
      final tm = tp + (ti - tp) * (mark - dp) / (di - dp);
      splits.add(KmSplit(splits.length + 1, 1000, tm - t0, avg()));
      d0 = mark;
      t0 = tm;
      hrs = [];
    }
    addHr(i);
  }
  final last = idx.last;
  final rest = dist[last]! - d0;
  if (rest >= minLastSplitM && time[last]! > t0) splits.add(KmSplit(splits.length + 1, rest, time[last]! - t0, avg()));
  return splits;
}

/// Altitudes averaged over [window] neighbours (gaps skipped), which takes the GPS and barometer jitter out before climbs are added up.
List<double> smoothAltitude(List<double?> altitude, {int window = 5}) {
  final a = [for (final v in altitude) ?v];
  return [
    for (var i = 0; i < a.length; i++)
      () {
        final lo = (i - window ~/ 2).clamp(0, a.length - 1), hi = (i + window ~/ 2).clamp(0, a.length - 1);
        return a.sublist(lo, hi + 1).reduce((x, y) => x + y) / (hi - lo + 1);
      }(),
  ];
}

/// Total climb in meters over the smoothed altitude, 0.1 m precision; null without altitude.
double? elevationGain(Track t) {
  final alt = t.altitude;
  if (alt == null) return null;
  final s = smoothAltitude(alt);
  if (s.length < 2) return null;
  var gain = 0.0;
  for (var i = 1; i < s.length; i++) {
    if (s[i] > s[i - 1]) gain += s[i] - s[i - 1];
  }
  return double.parse(gain.toStringAsFixed(1));
}

/// Below this speed, for [autoPauseSec] or longer, the runner counts as stopped.
const autoPauseSpeed = 0.5; // m/s
const autoPauseSec = 5;

/// Moving time in seconds: the track's duration minus every stretch slower than [autoPauseSpeed] that lasted [autoPauseSec] or more.
/// Null when the track has no time and distance to judge by.
int? autoPauseMovingSec(Track track) {
  final t = withGpsDistance(track);
  final idx = timedIndices(t);
  if (idx.length < 2) return null;
  final time = t.time!, dist = t.distance!;
  var paused = 0, slow = 0;
  for (var k = 1; k < idx.length; k++) {
    final dt = time[idx[k]]! - time[idx[k - 1]]!;
    if (dt <= 0) continue;
    if ((dist[idx[k]]! - dist[idx[k - 1]]!) / dt < autoPauseSpeed) {
      slow += dt;
    } else {
      if (slow >= autoPauseSec) paused += slow;
      slow = 0;
    }
  }
  if (slow >= autoPauseSec) paused += slow;
  return time[idx.last]! - time[idx.first]! - paused;
}

enum RunMetric { pace, hr, elevation }

/// (km, value) points for the Run page chart: pace as sec/km over the last 100 m (stops left out), heart rate, or smoothed altitude. At most [maxPoints].
List<(double, double)> chartSeries(Track track, RunMetric metric, {int maxPoints = 300}) {
  final t = withGpsDistance(track);
  final dist = t.distance;
  if (dist == null) return const [];
  final out = <(double, double)>[];
  switch (metric) {
    case RunMetric.pace:
      // Only points where the distance moved: files that update it every few seconds (some once a minute) would otherwise saw-tooth
      // between updates. A window spanning a real stop is slower than 20 min/km and left out below, so the line resumes 100 m after it.
      final time = t.time!;
      final idx = <int>[];
      for (final i in timedIndices(t)) {
        if (idx.isEmpty || dist[i]! > dist[idx.last]!) idx.add(i);
      }
      var j = 0;
      for (var k = 0; k < idx.length; k++) {
        while (j + 1 < k && dist[idx[k]]! - dist[idx[j + 1]]! >= 100) {
          j++;
        }
        final dd = dist[idx[k]]! - dist[idx[j]]!, dt = time[idx[k]]! - time[idx[j]]!;
        if (dd >= 100 && dt > 0 && dt / (dd / 1000) <= 1200) out.add((dist[idx[k]]! / 1000, dt / (dd / 1000))); // slower than 20 min/km is a stop, not a pace
      }
    case RunMetric.hr:
      final hr = t.hr;
      if (hr == null) return const [];
      for (var i = 0; i < hr.length && i < dist.length; i++) {
        if (hr[i] != null && dist[i] != null) out.add((dist[i]! / 1000, hr[i]!.toDouble()));
      }
    case RunMetric.elevation:
      final alt = t.altitude;
      if (alt == null) return const [];
      final idx = [for (var i = 0; i < alt.length && i < dist.length; i++) if (alt[i] != null && dist[i] != null) i];
      final s = smoothAltitude(alt);
      for (var k = 0; k < idx.length && k < s.length; k++) {
        out.add((dist[idx[k]]! / 1000, s[k]));
      }
  }
  if (out.length <= maxPoints) return out;
  final step = out.length / maxPoints;
  return [for (var k = 0; k < maxPoints; k++) out[(k * step).floor()]];
}

/// "Morning run", "Lunch run", "Afternoon run", "Evening run" or "Night run" by the hour of [start] (local time):
/// 5-10 Morning, 11-13 Lunch, 14-17 Afternoon, 18-21 Evening, 22-4 Night. An Interval run says "interval run".
String runTitle(DateTime start, {bool interval = false}) {
  final h = start.hour;
  final part = h >= 5 && h < 11 ? 'Morning' : h >= 11 && h < 14 ? 'Lunch' : h >= 14 && h < 18 ? 'Afternoon' : h >= 18 && h < 22 ? 'Evening' : 'Night';
  return '$part ${interval ? 'interval run' : 'run'}';
}

/// One lap of a Run: the stretch between two Lap presses (the first starts at the start, the last runs to the end of the track).
class Lap {
  Lap(this.index, this.durationSec, this.distanceM);
  final int index; // 1 for the first
  final int durationSec;
  final double? distanceM; // null when the track has no distance

  double? get paceSecPerKm => distanceM == null || distanceM! < 10 ? null : durationSec / (distanceM! / 1000);
}

/// The laps of [track], empty when it has no Lap marks or no time and distance to measure them with.
List<Lap> lapsOf(Track track) {
  final marks = track.laps;
  if (marks == null || marks.isEmpty) return const [];
  if (track.distance == null) return _timeOnlyLaps(track, marks);
  final t = withGpsDistance(track);
  final idx = timedIndices(t);
  if (idx.length < 2) return const [];
  final time = t.time!, dist = t.distance!;
  double distAt(num sec) {
    if (sec <= time[idx.first]!) return dist[idx.first]!;
    for (var k = 1; k < idx.length; k++) {
      final i = idx[k], p = idx[k - 1];
      if (time[i]! >= sec) {
        final span = time[i]! - time[p]!;
        return span <= 0 ? dist[i]! : dist[p]! + (dist[i]! - dist[p]!) * (sec - time[p]!) / span;
      }
    }
    return dist[idx.last]!;
  }

  final bounds = [time[idx.first]!, ...marks, time[idx.last]!];
  return [
    for (var k = 0; k + 1 < bounds.length; k++)
      if (bounds[k + 1] > bounds[k]) Lap(k + 1, bounds[k + 1] - bounds[k], distAt(bounds[k + 1]) - distAt(bounds[k])),
  ];
}

/// Laps of a track that has times but no distance: their durations only.
List<Lap> _timeOnlyLaps(Track track, List<int> marks) {
  final time = track.time?.whereType<int>().toList() ?? const <int>[];
  if (time.length < 2) return const [];
  final bounds = [time.first, ...marks, time.last];
  return [
    for (var k = 0; k + 1 < bounds.length; k++)
      if (bounds[k + 1] > bounds[k]) Lap(k + 1, bounds[k + 1] - bounds[k], null),
  ];
}

/// The average heart rate over an Interval run's step [s], from the track's readings inside it; null without readings.
int? stepAvgHr(Track t, StepMark s) {
  final time = t.time, hr = t.hr;
  if (time == null || hr == null) return null;
  var sum = 0, n = 0;
  for (var i = 0; i < time.length && i < hr.length; i++) {
    final at = time[i], bpm = hr[i];
    if (at == null || bpm == null || at < s.startSec || at >= s.endSec) continue;
    sum += bpm;
    n++;
  }
  return n == 0 ? null : (sum / n).round();
}

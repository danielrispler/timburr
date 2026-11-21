import 'db.dart';
import 'hr_zones.dart';
import 'track.dart';

/// Relative Effort: minutes in each HR zone times the zone number (zone 1 counts 1, zone 5 counts 5), summed. Null without zone time.
double? relativeEffort(List<double>? zoneSecs) {
  if (zoneSecs == null) return null;
  var e = 0.0;
  for (var z = 0; z < 5; z++) {
    e += zoneSecs[z] / 60 * (z + 1);
  }
  return e;
}

/// The load of one Run for Fitness & Freshness. [estimated] is true when the Run has no heart rate at all.
///
/// Runs without HR (most of the 83 imported from Strava, and every Run before September 2026) must still count toward training load,
/// or Fitness would sag through months of real training. The rule, in order:
///  1. an HR track: Relative Effort from time in zones;
///  2. only an average HR: the whole Moving time counts in the zone of that average;
///  3. no HR: the whole Moving time counts as an easy Run, zone 2. The Run page shows no Relative Effort for it.
({double effort, bool estimated}) runLoad(CardioData run, Track? track, int maxHr) {
  final fromTrack = track == null ? null : relativeEffort(zoneSeconds(track, maxHr));
  if (fromTrack != null) return (effort: fromTrack, estimated: false);
  final minutes = run.durationSec / 60;
  final avg = run.avgHr;
  if (avg != null) return (effort: minutes * (zoneIndex(avg, maxHr) + 1), estimated: false);
  return (effort: minutes * 2, estimated: true);
}

/// (start, load) of every Run, [tracks] keyed by Run id.
List<(DateTime, double)> dailyLoads(Iterable<CardioData> runs, Map<String, Track> tracks, int maxHr) =>
    [for (final r in runs) (r.startedAt, runLoad(r, tracks[r.id], maxHr).effort)];

typedef LoadPoint = ({DateTime day, double fitness, double fatigue, double form});

const fitnessDays = 42, fatigueDays = 7;

/// Fitness (42-day), Fatigue (7-day) and Form (Fitness minus Fatigue) for each local day from [from] to [to] inclusive.
/// Each is an exponentially weighted average of daily load, `x += (load - x) / days`, so rest days decay it. Loads on the same
/// day add up; the average starts at zero before the first load, so Runs before [from] still count.
List<LoadPoint> fitnessSeries(Iterable<(DateTime, double)> loads, DateTime from, DateTime to) {
  DateTime dayOf(DateTime d) {
    final l = d.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  final perDay = <DateTime, double>{};
  for (final (at, load) in loads) {
    perDay.update(dayOf(at), (v) => v + load, ifAbsent: () => load);
  }
  final start = dayOf(from), end = dayOf(to);
  var first = start;
  for (final d in perDay.keys) {
    if (d.isBefore(first)) first = d;
  }
  var fit = 0.0, fat = 0.0;
  final out = <LoadPoint>[];
  for (var d = first; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
    final load = perDay[d] ?? 0;
    fit += (load - fit) / fitnessDays;
    fat += (load - fat) / fatigueDays;
    if (!d.isBefore(start)) out.add((day: d, fitness: fit, fatigue: fat, form: fit - fat));
  }
  return out;
}

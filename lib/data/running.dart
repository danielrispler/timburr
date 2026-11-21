import 'cardio.dart';
import 'db.dart';
import 'recording.dart' show drawsRoute;
import 'stats.dart' show dayOf, mondayOf;

/// Distance, moving time and Run count over some stretch.
typedef RunTotals = ({double km, int sec, int count});

/// The Runs among [sessions]: outdoor and treadmill. Old rows of other types (walk, padel) and Workouts are not Runs.
List<CardioData> runsOf(Iterable<CardioData> sessions) => [for (final s in sessions) if (s.deletedAt == null && cardioTypes.contains(s.type)) s];

/// Totals of the Runs starting in [from, to).
RunTotals totalsBetween(Iterable<CardioData> runs, DateTime from, DateTime to) {
  var km = 0.0, sec = 0, n = 0;
  for (final r in runs) {
    if (r.startedAt.isBefore(from) || !r.startedAt.isBefore(to)) continue;
    km += r.distanceKm ?? 0;
    sec += r.durationSec;
    n++;
  }
  return (km: km, sec: sec, count: n);
}

/// What the Runs view shows: this week, the average of the 12 weeks before it, then month, year and all-time.
typedef RunSummary = ({RunTotals week, double avgWeekKm12, RunTotals month, RunTotals year, RunTotals all});

RunSummary runSummary(Iterable<CardioData> runs, DateTime now) {
  final monday = mondayOf(now), end = DateTime(now.year, now.month, now.day + 1);
  final twelve = totalsBetween(runs, mondayOf(now, weeksAgo: 12), monday);
  return (
    week: totalsBetween(runs, monday, end),
    avgWeekKm12: twelve.km / 12,
    month: totalsBetween(runs, DateTime(now.year, now.month), end),
    year: totalsBetween(runs, DateTime(now.year), end),
    all: totalsBetween(runs, DateTime(1970), end),
  );
}

enum Period { week, month, year }

/// Start of the [p] period holding [d]: Monday, first of the month, 1 January. Calendar fields, so DST never shifts it.
DateTime periodStart(Period p, DateTime d) {
  final l = dayOf(d);
  return switch (p) {
    Period.week => mondayOf(l),
    Period.month => DateTime(l.year, l.month),
    Period.year => DateTime(l.year),
  };
}

DateTime _next(Period p, DateTime s) => switch (p) {
      Period.week => DateTime(s.year, s.month, s.day + 7),
      Period.month => DateTime(s.year, s.month + 1),
      Period.year => DateTime(s.year + 1),
    };

/// Distance per [p] period, oldest first, ending with the period of [now]. Empty periods are zero rows, so the x axis is real time.
/// [last] keeps only that many periods; null keeps everything from the first Run.
List<({DateTime start, double km})> distanceSeries(Iterable<CardioData> runs, Period p, DateTime now, {int? last}) {
  final km = <DateTime, double>{};
  for (final r in runs) {
    final s = periodStart(p, r.startedAt);
    km[s] = (km[s] ?? 0) + (r.distanceKm ?? 0);
  }
  final end = periodStart(p, now);
  var start = km.isEmpty ? end : km.keys.reduce((a, b) => a.isBefore(b) ? a : b);
  if (start.isAfter(end)) start = end;
  final out = <({DateTime start, double km})>[];
  for (var s = start; !s.isAfter(end); s = _next(p, s)) {
    out.add((start: s, km: km[s] ?? 0));
  }
  return last != null && out.length > last ? out.sublist(out.length - last) : out;
}

/// The points of a stored [CardioData.route] (`lat,lon;lat,lon`), as (lat, lon). Unreadable pairs are skipped.
List<(double, double)> parseRoute(String? route) {
  if (route == null || route.isEmpty) return const [];
  return [
    for (final p in route.split(';'))
      if (p.split(',') case [final a, final b] when double.tryParse(a) != null && double.tryParse(b) != null) (double.parse(a), double.parse(b)),
  ];
}

/// Every outdoor Run's stored (simplified) route as points, for the heatmap. Runs without a drawable route are skipped.
List<List<(double, double)>> heatmapRoutes(Iterable<CardioData> runs) {
  final out = <List<(double, double)>>[];
  for (final r in runsOf(runs)) {
    if (!drawsRoute(r.type)) continue;
    final p = parseRoute(r.route);
    if (p.length >= 2) out.add(p);
  }
  return out;
}

import 'db.dart';
import 'running.dart' show runsOf;
import 'stats.dart' show dayOf, mondayOf;

/// What happened on one calendar day of the Training log.
typedef LogDay = ({List<CardioData> runs, List<Workout> workouts});

/// The Runs and Workouts of the month holding [month], per day (midnight keys). Days with nothing are absent.
/// Deleted rows are left out, and so are rows of types other than run and interval.
Map<DateTime, LogDay> monthLog(Iterable<CardioData> runs, Iterable<Workout> workouts, DateTime month) {
  bool inMonth(DateTime d) => dayOf(d).year == month.year && dayOf(d).month == month.month;
  final out = <DateTime, LogDay>{};
  LogDay at(DateTime d) => out.putIfAbsent(dayOf(d), () => (runs: <CardioData>[], workouts: <Workout>[]));
  for (final r in runsOf(runs)) {
    if (inMonth(r.startedAt)) at(r.startedAt).runs.add(r);
  }
  for (final w in workouts) {
    if (w.deletedAt == null && inMonth(w.startedAt)) at(w.startedAt).workouts.add(w);
  }
  return out;
}

/// One week of a month: its Monday, and the distance and count of the month's Runs in it.
typedef MonthWeek = ({DateTime monday, double km, int count});

/// Every week touching the month holding [month], oldest first. Only Runs inside the month are counted.
List<MonthWeek> monthWeeks(Iterable<CardioData> runs, DateTime month) {
  final first = DateTime(month.year, month.month), last = DateTime(month.year, month.month + 1, 0);
  final km = <DateTime, double>{}, n = <DateTime, int>{};
  for (final r in runsOf(runs)) {
    if (dayOf(r.startedAt).year != month.year || dayOf(r.startedAt).month != month.month) continue;
    final m = mondayOf(r.startedAt);
    km[m] = (km[m] ?? 0) + (r.distanceKm ?? 0);
    n[m] = (n[m] ?? 0) + 1;
  }
  return [
    for (var m = mondayOf(first); !m.isAfter(last); m = DateTime(m.year, m.month, m.day + 7)) (monday: m, km: km[m] ?? 0, count: n[m] ?? 0),
  ];
}

/// Consecutive weeks, Monday to Sunday, with at least one Run, ending this week. An empty current week
/// does not break it yet: the streak then ends last week. Runs after [now] are ignored.
int weeklyStreak(Iterable<CardioData> runs, DateTime now) {
  final weeks = {
    for (final r in runsOf(runs))
      if (!r.startedAt.isAfter(now)) mondayOf(r.startedAt)
  };
  var w = mondayOf(now);
  if (!weeks.contains(w)) w = DateTime(w.year, w.month, w.day - 7);
  var n = 0;
  for (; weeks.contains(w); w = DateTime(w.year, w.month, w.day - 7)) {
    n++;
  }
  return n;
}

/// Dot diameter in logical pixels for a Run of [km]: 6 up to 16, reached at a marathon.
double dotSize(double? km) => 6 + 10 * ((km ?? 0).clamp(0, 42.2) / 42.2);

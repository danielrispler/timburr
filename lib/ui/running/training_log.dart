import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../data/running.dart';
import '../../data/stats.dart' show dayOf;
import '../../data/training_log.dart';
import '../cardio/activity_timer.dart' show activityIcon;
import '../cardio/run_page.dart';
import '../core/theme.dart';
import '../routines/start.dart';
import '../workouts/workout_screen.dart';

const _monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const _cellHeight = 52.0;
const _maxMonthsBack = 240;

String _km(double km) => '${km.toStringAsFixed(km < 100 ? 1 : 0)} km';

String _time(int sec) {
  final h = sec ~/ 3600, m = (sec % 3600) ~/ 60;
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}

/// The Training log on Progress: a month calendar to swipe, then that month's totals and weeks, and the weekly running streak.
/// Each Run is a dot sized by distance (outdoor and treadmill in different colours); each Workout is a small dot.
class TrainingLog extends StatefulWidget {
  const TrainingLog({super.key, required this.stores, required this.runs, this.now});

  final Stores stores;
  final Stream<List<CardioData>> runs;
  final DateTime? now; // for tests

  @override
  State<TrainingLog> createState() => _TrainingLogState();
}

class _TrainingLogState extends State<TrainingLog> {
  late final Stream<List<Workout>> _workouts = widget.stores.workouts.watchHistory();
  late final PageController _pages = PageController();
  int _back = 0; // months before the current one

  DateTime get _now => widget.now ?? DateTime.now();
  DateTime _month(int back) => DateTime(_now.year, _now.month - back);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<CardioData>>(
        stream: widget.runs,
        builder: (context, runSnap) => StreamBuilder<List<Workout>>(
          stream: _workouts,
          builder: (context, workSnap) {
            final runs = runSnap.data, workouts = workSnap.data;
            if (runs == null || workouts == null) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
            final month = _month(_back), t = Theme.of(context);
            final totals = totalsBetween(runs, month, DateTime(month.year, month.month + 1));
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Training log', style: t.textTheme.titleSmall),
              Row(children: [
                IconButton(
                  tooltip: 'Previous month',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _back < _maxMonthsBack ? () => _pages.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut) : null,
                ),
                Expanded(child: Text('${_monthNames[month.month - 1]} ${month.year}', textAlign: TextAlign.center, style: t.textTheme.titleMedium)),
                IconButton(
                  tooltip: 'Next month',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _back > 0 ? () => _pages.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut) : null,
                ),
              ]),
              Row(children: [
                for (final d in _weekdays) Expanded(child: Center(child: Text(d, style: t.textTheme.labelSmall))),
              ]),
              SizedBox(
                height: _cellHeight * 6,
                child: PageView.builder(
                  controller: _pages,
                  reverse: true, // swipe right for earlier months
                  itemCount: _maxMonthsBack + 1,
                  onPageChanged: (i) => setState(() => _back = i),
                  itemBuilder: (_, i) => _MonthGrid(
                    month: _month(i),
                    today: dayOf(_now),
                    log: monthLog(runs, workouts, _month(i)),
                    onDay: (day, log) => _openDay(context, day, log),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Wrap(spacing: 16, children: [
                _Legend(color: t.colorScheme.primary, size: 12, label: 'Run'),
                _Legend(color: t.colorScheme.tertiary, size: 12, label: 'Treadmill'),
                _Legend(color: t.colorScheme.onSurfaceVariant, size: 5, label: 'Workout'),
              ]),
              TileGroup(title: '${_monthNames[month.month - 1]} totals', children: [
                ListTile(
                  title: Text(_km(totals.km), style: t.textTheme.headlineSmall),
                  subtitle: Text('${_time(totals.sec)} · ${totals.count} ${totals.count == 1 ? 'Run' : 'Runs'}'),
                ),
                for (final w in monthWeeks(runs, month))
                  ListTile(
                    dense: true,
                    title: Text('Week of ${w.monday.day} ${_monthNames[w.monday.month - 1].substring(0, 3)}'),
                    trailing: Text(w.count == 0 ? '-' : '${_km(w.km)} · ${w.count}'),
                  ),
              ]),
              TileGroup(children: [
                ListTile(
                  leading: const IconTile(Icons.local_fire_department),
                  title: Text(() {
                    final n = weeklyStreak(runs, _now);
                    return '$n ${n == 1 ? 'week' : 'weeks'} running streak';
                  }()),
                  subtitle: const Text('Weeks in a row with at least one Run'),
                ),
              ]),
            ]);
          },
        ),
      );

  Future<void> _openDay(BuildContext context, DateTime day, LogDay log) async {
    final s = widget.stores;
    void openRunOf(CardioData r) => openRun(context, s.cardio, r.id);
    void openWorkout(Workout w) => Navigator.of(context, rootNavigator: true)
        .push(MaterialPageRoute(builder: (_) => WorkoutScreen(store: s.workouts, catalog: s.catalog, workoutId: w.id)));
    if (log.runs.length + log.workouts.length == 1) {
      return log.runs.isNotEmpty ? openRunOf(log.runs.single) : openWorkout(log.workouts.single);
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final r in log.runs)
            ListTile(
              leading: IconTile(activityIcon(r.type)),
              title: Text(r.distanceKm == null ? 'Run' : '${r.type == 'treadmill' ? 'Treadmill run' : 'Run'} ${_km(r.distanceKm!)}'),
              subtitle: Text(_time(r.durationSec)),
              onTap: () {
                Navigator.pop(sheet);
                openRunOf(r);
              },
            ),
          for (final w in log.workouts)
            ListTile(
              leading: const IconTile(Icons.fitness_center),
              title: const Text('Workout'),
              onTap: () {
                Navigator.pop(sheet);
                openWorkout(w);
              },
            ),
        ]),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.size, required this.label});

  final Color color;
  final double size;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        _Dot(color, size),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ]);
}

class _Dot extends StatelessWidget {
  const _Dot(this.color, this.size);

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.month, required this.today, required this.log, required this.onDay});

  final DateTime month, today;
  final Map<DateTime, LogDay> log;
  final void Function(DateTime day, LogDay log) onDay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lead = DateTime(month.year, month.month).weekday - 1; // blanks before the 1st, Monday first
    final days = DateTime(month.year, month.month + 1, 0).day;
    return Column(children: [
      for (var row = 0; row < 6; row++)
        SizedBox(
          height: _cellHeight,
          child: Row(children: [
            for (var col = 0; col < 7; col++)
              Expanded(child: () {
                final n = row * 7 + col - lead + 1;
                if (n < 1 || n > days) return const SizedBox.shrink();
                final day = DateTime(month.year, month.month, n), entry = log[day];
                final isToday = day == today;
                return InkWell(
                  key: ValueKey('day-$n'),
                  onTap: entry == null ? null : () => onDay(day, entry),
                  child: Container(
                    margin: const EdgeInsets.all(1),
                    decoration: isToday ? BoxDecoration(border: Border.all(color: scheme.primary), borderRadius: BorderRadius.circular(8)) : null,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('$n', style: Theme.of(context).textTheme.labelSmall),
                      const SizedBox(height: 2),
                      if (entry != null)
                        Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 2, runSpacing: 2, children: [
                          for (final r in entry.runs) _Dot(r.type == 'treadmill' ? scheme.tertiary : scheme.primary, dotSize(r.distanceKm)),
                          for (final _ in entry.workouts) _Dot(scheme.onSurfaceVariant, 5),
                        ]),
                    ]),
                  ),
                );
              }()),
          ]),
        ),
    ]);
  }
}

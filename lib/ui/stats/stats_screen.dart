import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../data/db.dart';
import '../../data/records.dart';
import '../../data/stats.dart';
import '../cardio/cardio_stats.dart';
import '../core/theme.dart';
import '../exercises/exercise_detail.dart';
import '../routines/start.dart';

String fmtNum(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
String fmtVolume(double kg) => kg >= 1000 ? '${(kg / 1000).toStringAsFixed(1)} t' : '${kg.round()} kg';
String fmtDuration(Duration d) => d.inHours > 0 ? '${d.inHours}h ${d.inMinutes % 60}m' : '${d.inMinutes}m';
String fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

/// Everything the stats views read, from live streams.
typedef StatsData = ({
  List<Workout> workouts,
  List<LoggedSet> rows,
  List<CardioData> cardio,
  List<Routine> routines,
  Map<String, CatalogEntry> exercises,
});

/// Rebuilds [builder] whenever history, sets, cardio or routines change.
class StatsBuilder extends StatefulWidget {
  const StatsBuilder({super.key, required this.stores, required this.builder});

  final Stores stores;
  final Widget Function(BuildContext, StatsData) builder;

  @override
  State<StatsBuilder> createState() => _StatsBuilderState();
}

class _StatsBuilderState extends State<StatsBuilder> {
  late final s = widget.stores;
  late final _history = s.workouts.watchHistory(), _logged = s.workouts.watchLogged();
  late final _cardio = s.cardio.watchAll(), _routines = s.routines.watchRoutines();
  final _entries = <String, CatalogEntry>{};
  final _loading = <String>{};

  /// Loads catalog entries for exercise ids not seen yet, then rebuilds.
  void _resolve(Iterable<String> ids) {
    final missing = ids.toSet().difference(_entries.keys.toSet()).difference(_loading);
    if (missing.isEmpty) return;
    _loading.addAll(missing);
    Future.wait([for (final id in missing) s.catalog.byId(id).then((e) => (id, e))]).then((found) {
      if (!mounted) return;
      setState(() {
        for (final (id, e) in found) {
          _entries[id] = e ?? CatalogEntry(name: 'Unknown exercise', rowId: id);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Workout>>(
        stream: _history,
        builder: (context, w) => StreamBuilder<List<LoggedSet>>(
          stream: _logged,
          builder: (context, l) => StreamBuilder<List<CardioData>>(
            stream: _cardio,
            builder: (context, c) => StreamBuilder<List<Routine>>(
              stream: _routines,
              builder: (context, r) {
                if (w.data == null || l.data == null || c.data == null || r.data == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                _resolve(l.data!.map((x) => x.exerciseId));
                return widget.builder(context,
                    (workouts: w.data!, rows: l.data!, cardio: c.data!, routines: r.data!, exercises: _entries));
              },
            ),
          ),
        ),
      );
}

/// Stats tab: Me, Workouts, Exercises and Records.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key, required this.stores});

  final Stores stores;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 4,
        child: Column(children: [
          const TabBar(tabs: [Tab(text: 'Me'), Tab(text: 'Workouts'), Tab(text: 'Exercises'), Tab(text: 'Records')]),
          Expanded(
            child: StatsBuilder(
              stores: stores,
              builder: (context, d) => TabBarView(children: [
                _Me(d),
                _Routines(d),
                _Exercises(d, stores),
                _Records(d, stores),
              ]),
            ),
          ),
        ]),
      );
}

Widget _page(List<Widget> children) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: ListView(padding: const EdgeInsets.only(bottom: 16), children: children),
      ),
    );

class _Me extends StatelessWidget {
  const _Me(this.d);

  final StatsData d;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final sessions = [for (final w in d.workouts) w.startedAt, for (final c in d.cardio) c.startedAt];
    final t = totals(d.workouts, d.rows, d.cardio);
    final streak = weekStreaks(sessions, now);
    final weeks = weekly(d.workouts, volumeByWorkout(d.rows), now);
    return _page([
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          StatChip('Workouts', '${t.workouts}'),
          StatChip('Lifted', fmtVolume(t.volume)),
          StatChip('Sets', '${t.sets}'),
          StatChip('Time', fmtDuration(t.time)),
          StatChip('Cardio', '${fmtNum(t.cardioKm)} km'),
          StatChip('Streak', '${streak.current} wk'),
          StatChip('Best streak', '${streak.longest} wk'),
        ]),
      ),
      _Heatmap(dayCounts(sessions), now),
      _Bars('Workouts per week', [for (final w in weeks) (w.monday, w.workouts.toDouble())]),
      _Bars('Volume per week (t)', [for (final w in weeks) (w.monday, w.volume / 1000)]),
      TileGroup(title: 'Most trained', children: [
        if (d.rows.isEmpty) const ListTile(title: Text('Finish a workout to see stats')),
        for (final (id, n) in topExercises(d.rows))
          ListTile(dense: true, title: Text(d.exercises[id]?.name ?? '…'), trailing: Text('$n sets')),
      ]),
    ]);
  }
}

/// A small labelled number.
class StatChip extends StatelessWidget {
  const StatChip(this.label, this.value, {super.key});

  final String label, value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 104,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: theme.textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(label, style: theme.textTheme.bodySmall),
      ]),
    );
  }
}

/// Last 26 weeks, one column per week, Monday on top; darker means more sessions.
class _Heatmap extends StatelessWidget {
  const _Heatmap(this.counts, this.now);

  final Map<DateTime, int> counts;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final empty = Theme.of(context).colorScheme.surfaceContainerHigh;
    final first = mondayOf(now).subtract(const Duration(days: 7 * 25));
    final today = dayOf(now);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Last 6 months', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, c) {
          final cell = (c.maxWidth / 26).clamp(4.0, 20.0);
          return Row(children: [
            for (var wk = 0; wk < 26; wk++)
              Column(children: [
                for (var day = 0; day < 7; day++)
                  () {
                    final date = DateTime(first.year, first.month, first.day + wk * 7 + day);
                    final n = counts[date] ?? 0;
                    return Container(
                      width: cell - 2,
                      height: cell - 2,
                      margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        color: date.isAfter(today) ? Colors.transparent : (n == 0 ? empty : color.withValues(alpha: n == 1 ? 0.6 : 1)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }(),
              ]),
          ]);
        }),
      ]),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars(this.title, this.points);

  final String title;
  final List<(DateTime, double)> points;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 24, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 2,
          child: BarChart(BarChartData(
            gridData: const FlGridData(drawVerticalLine: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  getTitlesWidget: (x, meta) {
                    final i = x.toInt();
                    if (i % 3 != 0 || i >= points.length) return const SizedBox.shrink();
                    final d = points[i].$1;
                    return SideTitleWidget(meta: meta, child: Text('${d.day}/${d.month}'));
                  },
                ),
              ),
            ),
            barGroups: [
              for (final (i, (_, v)) in points.indexed)
                BarChartGroupData(x: i, barRods: [BarChartRodData(toY: v, color: color, width: 12)]),
            ],
          )),
        ),
      ]),
    );
  }
}

class _Routines extends StatelessWidget {
  const _Routines(this.d);

  final StatsData d;

  @override
  Widget build(BuildContext context) {
    final names = {for (final r in d.routines) r.id: r.name};
    final volumes = volumeByWorkout(d.rows);
    final stats = [for (final r in routineStats(d.workouts)) if (names.containsKey(r.routineId)) r];
    return _page([
      TileGroup(children: [
        if (stats.isEmpty) const ListTile(title: Text('No saved workout done yet')),
        for (final r in stats)
          ListTile(
            leading: const IconTile(Icons.fitness_center),
            title: Text(names[r.routineId]!),
            subtitle: Text('${r.count}× · last ${fmtDate(r.last)} · avg ${fmtDuration(r.avg)}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: Text(names[r.routineId]!)),
                body: _page([
                  _Line('Volume per session (kg)', [
                    for (final w in d.workouts.reversed)
                      if (w.routineId == r.routineId) (w.startedAt, volumes[w.id] ?? 0)
                  ]),
                ]),
              ),
            )),
          ),
      ]),
    ]);
  }
}

class _Line extends StatelessWidget {
  const _Line(this.title, this.points);

  final String title;
  final Series points;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return const ListTile(title: Text('Needs 2 sessions for a chart'));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 24, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 2,
          child: LineChart(LineChartData(
            gridData: const FlGridData(drawVerticalLine: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  interval: points.length > 4 ? (points.length / 4).ceilToDouble() : 1,
                  getTitlesWidget: (x, meta) {
                    final i = x.toInt();
                    if (i != x || i < 0 || i >= points.length) return const SizedBox.shrink();
                    final d = points[i].$1;
                    return SideTitleWidget(meta: meta, child: Text('${d.day}/${d.month}'));
                  },
                ),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                // shortcut: x is session index, not time, so gaps between sessions are evenly spaced.
                spots: [for (final (i, (_, v)) in points.indexed) FlSpot(i.toDouble(), v)],
                color: Theme.of(context).colorScheme.primary,
                barWidth: 3,
                dotData: FlDotData(show: points.length < 30),
              ),
            ],
          )),
        ),
      ]),
    );
  }
}

void _openExercise(BuildContext context, Stores stores, CatalogEntry? e) {
  if (e == null) return;
  Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ExerciseDetail(catalog: stores.catalog, entry: e, workouts: stores.workouts)));
}

class _Exercises extends StatefulWidget {
  const _Exercises(this.d, this.stores);

  final StatsData d;
  final Stores stores;

  @override
  State<_Exercises> createState() => _ExercisesState();
}

class _ExercisesState extends State<_Exercises> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final d = widget.d, now = DateTime.now();
    final sessions = sessionsByExercise(d.rows);
    final ids = sessions.keys
        .where((id) => (d.exercises[id]?.name ?? '').toLowerCase().contains(_query.toLowerCase()))
        .toList()
      ..sort((a, b) => sessions[b]!.last.$1.startedAt.compareTo(sessions[a]!.last.$1.startedAt));
    return _page([
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search exercises'),
          onChanged: (q) => setState(() => _query = q.trim()),
        ),
      ),
      TileGroup(children: [
        if (ids.isEmpty) const ListTile(title: Text('No exercises logged')),
        for (final id in ids)
          () {
            final e = d.exercises[id];
            final loadType = e?.loadType ?? 'weighted';
            final best = records(loadType, [for (final (_, sets) in sessions[id]!) sets]);
            final trend = loadType == 'weighted' ? e1rmTrend(sessions[id]!, now) : null;
            return ListTile(
              title: Text(e?.name ?? '…'),
              subtitle: Text('${sessions[id]!.length} sessions · last ${fmtDate(sessions[id]!.last.$1.startedAt)}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(switch (loadType) {
                  'timed' => '${fmtNum(best['duration'] ?? 0)} s',
                  'bodyweight' => '${fmtNum(best['reps'] ?? 0)} reps',
                  _ => '${fmtNum(best['e1rm'] ?? 0)} kg',
                }),
                if (trend != null) ...[
                  const SizedBox(width: 8),
                  Icon(trend >= 0 ? Icons.trending_up : Icons.trending_down,
                      color: trend >= 0 ? Colors.green : Theme.of(context).colorScheme.error, size: 18),
                  Text('${(trend * 100).round()}%'),
                ],
              ]),
              onTap: () => _openExercise(context, widget.stores, e),
            );
          }(),
      ]),
    ]);
  }
}

class _Records extends StatelessWidget {
  const _Records(this.d, this.stores);

  final StatsData d;
  final Stores stores;

  @override
  Widget build(BuildContext context) {
    final sessions = sessionsByExercise(d.rows);
    String loadType(String id) => d.exercises[id]?.loadType ?? 'weighted';
    final since = DateTime.now().subtract(const Duration(days: 30));
    final recent = [for (final p in prEvents(sessions, loadType)) if (p.workout.startedAt.isAfter(since)) p];
    final ids = sessions.keys.toList()..sort((a, b) => (d.exercises[a]?.name ?? '').compareTo(d.exercises[b]?.name ?? ''));
    return _page([
      TileGroup(title: 'PRs in the last 30 days', children: [
        if (recent.isEmpty) const ListTile(title: Text('None yet. Go lift.')),
        for (final p in recent)
          ListTile(
            leading: const IconTile(Icons.emoji_events),
            title: Text(d.exercises[p.exerciseId]?.name ?? '…'),
            subtitle: Text(fmtDate(p.workout.startedAt)),
            trailing: Text(switch (loadType(p.exerciseId)) {
              'timed' => '${fmtNum(p.value)} s',
              'bodyweight' => '${fmtNum(p.value)} reps',
              _ => 'e1RM ${fmtNum(p.value)} kg',
            }),
            onTap: () => _openExercise(context, stores, d.exercises[p.exerciseId]),
          ),
      ]),
      TileGroup(title: 'All-time bests', children: [
        if (ids.isEmpty) const ListTile(title: Text('No records yet')),
        for (final id in ids)
          ListTile(
            title: Text(d.exercises[id]?.name ?? '…'),
            subtitle: Text([
              for (final MapEntry(:key, :value) in records(loadType(id), [for (final (_, s) in sessions[id]!) s]).entries)
                '$key ${fmtNum(value)}'
            ].join(' · ')),
            onTap: () => _openExercise(context, stores, d.exercises[id]),
          ),
      ]),
      TileGroup(children: [
        ListTile(
          leading: const IconTile(Icons.directions_run),
          title: const Text('Cardio stats'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CardioStatsScreen(cardio: stores.cardio))),
        ),
      ]),
    ]);
  }
}

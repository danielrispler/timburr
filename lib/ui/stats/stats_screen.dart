import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../data/db.dart';
import '../../data/records.dart';
import '../../data/stats.dart';
import '../cardio/cardio_stats.dart';
import '../core/series_chart.dart';
import '../core/theme.dart';
import '../exercises/exercise_detail.dart';
import '../routines/start.dart';

String fmtVolume(double kg) => '${kg.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',')} kg';
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

final _feeds = Expando<Stream<StatsData>>();

/// The one stats stream for [s]: shared by Home and Stats, so each change runs one set of full-history queries.
/// Late listeners get the latest value at once. Exercise entries reload whenever the exercises table changes.
Stream<StatsData> watchStats(Stores s) => _feeds[s.workouts] ??= _statsFeed(s);

Stream<StatsData> _statsFeed(Stores s) {
  StatsData? last;
  final out = StreamController<StatsData>.broadcast();
  final latest = List<Object?>.filled(5, null);
  var entries = <String, CatalogEntry>{};
  var gen = 0;
  Future<void> emit({bool exercisesChanged = false}) async {
    if (latest.contains(null)) return;
    final my = ++gen;
    final rows = latest[1] as List<LoggedSet>;
    final fresh = exercisesChanged ? <String, CatalogEntry>{} : {...entries};
    for (final id in rows.map((x) => x.exerciseId).toSet().difference(fresh.keys.toSet())) {
      fresh[id] = await s.catalog.byId(id) ?? CatalogEntry(name: 'Unknown exercise', rowId: id);
    }
    if (my != gen) return; // a newer change superseded this one
    entries = fresh;
    out.add(last = (
      workouts: latest[0] as List<Workout>,
      rows: rows,
      cardio: latest[2] as List<CardioData>,
      routines: latest[3] as List<Routine>,
      exercises: entries,
    ));
  }

  final db = s.catalog.db;
  final sources = <Stream<Object>>[
    s.workouts.watchHistory(),
    s.workouts.watchLogged(),
    s.cardio.watchAll(),
    s.routines.watchRoutines(),
    db.select(db.exercises).watch(),
  ];
  // Subscribed once for the app's life; the stores live as long as the app.
  for (var i = 0; i < sources.length; i++) {
    sources[i].listen((v) {
      latest[i] = v;
      emit(exercisesChanged: i == 4);
    });
  }
  return Stream.multi((c) {
    if (last case final l?) c.add(l);
    final sub = out.stream.listen(c.add);
    c.onCancel = sub.cancel;
  });
}

/// Rebuilds [builder] whenever history, sets, cardio, routines or exercises change.
class StatsBuilder extends StatelessWidget {
  const StatsBuilder({super.key, required this.stores, required this.builder});

  final Stores stores;
  final Widget Function(BuildContext, StatsData) builder;

  @override
  Widget build(BuildContext context) => StreamBuilder<StatsData>(
        stream: watchStats(stores),
        builder: (context, d) =>
            d.data == null ? const Center(child: CircularProgressIndicator()) : builder(context, d.data!),
      );
}

/// Stats tab: Me, Workouts, Exercises and Records.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key, required this.stores});

  final Stores stores;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: Column(
      children: [
        const TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.center,
          tabs: [
            Tab(text: 'Me'),
            Tab(text: 'Workouts'),
            Tab(text: 'Exercises'),
            Tab(text: 'Records'),
          ],
        ),
        Expanded(
          child: StatsBuilder(
            stores: stores,
            builder: (context, d) =>
                TabBarView(children: [_Me(d), _Routines(d), _Exercises(d, stores), _Records(d, stores)]),
          ),
        ),
      ],
    ),
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
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StatChip('Workouts', '${t.workouts}'),
            StatChip('Lifted', fmtVolume(t.volume)),
            StatChip('Sets', '${t.sets}'),
            StatChip('Time', fmtDuration(t.time)),
            StatChip('Cardio', '${fmtNum(t.cardioKm)} km'),
            StatChip('Streak', '${streak.current} wk'),
            StatChip('Best streak', '${streak.longest} wk'),
          ],
        ),
      ),
      _Heatmap(dayCounts(sessions), now),
      _Bars('Workouts per week', [for (final w in weeks) (w.monday, w.workouts.toDouble())]),
      _Bars('Volume per week (kg)', [for (final w in weeks) (w.monday, w.volume)]),
      TileGroup(
        title: 'Most trained',
        children: [
          if (d.rows.isEmpty) const ListTile(title: Text('Finish a workout to see stats')),
          for (final (id, n) in topExercises(d.rows))
            ListTile(dense: true, title: Text(d.exercises[id]?.name ?? '…'), trailing: Text('$n sets')),
        ],
      ),
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
      width: 124,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: theme.textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
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
    final first = mondayOf(now, weeksAgo: 25);
    final today = dayOf(now);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Last 6 months', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, c) {
              final cell = (c.maxWidth / 26).clamp(4.0, 20.0);
              return Row(
                children: [
                  for (var wk = 0; wk < 26; wk++)
                    Column(
                      children: [
                        for (var day = 0; day < 7; day++)
                          () {
                            final date = DateTime(first.year, first.month, first.day + wk * 7 + day);
                            final n = counts[date] ?? 0;
                            return Container(
                              width: cell - 2,
                              height: cell - 2,
                              margin: const EdgeInsets.all(1),
                              decoration: BoxDecoration(
                                color: date.isAfter(today)
                                    ? Colors.transparent
                                    : (n == 0 ? empty : color.withValues(alpha: n == 1 ? 0.6 : 1)),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            );
                          }(),
                      ],
                    ),
                ],
              );
            },
          ),
        ],
      ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 2,
            child: BarChart(
              BarChartData(
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
                    BarChartGroupData(
                      x: i,
                      barRods: [BarChartRodData(toY: v, color: color, width: 12)],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
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
    final stats = [
      for (final r in routineStats(d.workouts))
        if (names.containsKey(r.routineId)) r,
    ];
    return _page([
      TileGroup(
        children: [
          if (stats.isEmpty) const ListTile(title: Text('No saved workout done yet')),
          for (final r in stats)
            ListTile(
              leading: const IconTile(Icons.fitness_center),
              title: Text(names[r.routineId]!),
              subtitle: Text('${r.count}× · last ${fmtDate(r.last)} · avg ${fmtDuration(r.avg)}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: Text(names[r.routineId]!)),
                    body: _page([
                      _Line('Volume per session (kg)', [
                        for (final w in d.workouts.reversed)
                          if (w.routineId == r.routineId) (w.startedAt, volumes[w.id] ?? 0),
                      ]),
                    ]),
                  ),
                ),
              ),
            ),
        ],
      ),
    ]);
  }
}


class _Line extends StatelessWidget {
  const _Line(this.title, this.points);

  final String title;
  final Series points;

  @override
  Widget build(BuildContext context) => points.length < 2
      ? const ListTile(title: Text('Needs 2 sessions for a chart'))
      : SeriesChart(title, points, leftReserved: 44);
}

void _openExercise(BuildContext context, Stores stores, CatalogEntry? e) {
  if (e == null) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ExerciseDetail(catalog: stores.catalog, entry: e, workouts: stores.workouts),
    ),
  );
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
    final ids =
        sessions.keys.where((id) => (d.exercises[id]?.name ?? '').toLowerCase().contains(_query.toLowerCase())).toList()
          // Main lifts on top, then the most recently done.
          ..sort((a, b) {
            final r = mainLiftRank(d.exercises[a]?.libraryId).compareTo(mainLiftRank(d.exercises[b]?.libraryId));
            return r != 0 ? r : sessions[b]!.last.$1.startedAt.compareTo(sessions[a]!.last.$1.startedAt);
          });
    bool isPopular(String id) => mainLiftRank(d.exercises[id]?.libraryId) < mainLifts.length;
    return _page([
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search exercises'),
          onChanged: (q) => setState(() => _query = q.trim()),
        ),
      ),
      if (ids.isEmpty) const TileGroup(children: [ListTile(title: Text('No exercises logged'))]),
      for (final (title, group) in [('Popular', ids.where(isPopular)), ('All', ids.where((id) => !isPopular(id)))])
        if (group.isNotEmpty)
          TileGroup(
            title: title,
            children: [
              for (final id in group)
                () {
                  final e = d.exercises[id];
                  final loadType = e?.loadType ?? 'weighted';
                  final best = records(loadType, [for (final (_, sets) in sessions[id]!) sets]);
                  final trend = loadType == 'weighted' ? e1rmTrend(sessions[id]!, now) : null;
                  return ListTile(
                    title: Text(e?.name ?? '…'),
                    subtitle: Text(
                      '${sessions[id]!.length} sessions · last ${fmtDate(sessions[id]!.last.$1.startedAt)}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(switch (loadType) {
                          'timed' => '${fmtNum(best['duration'] ?? 0)} s',
                          'bodyweight' => '${fmtNum(best['reps'] ?? 0)} reps',
                          _ => '${fmtNum(best['e1rm'] ?? 0)} kg',
                        }),
                        if (trend != null) ...[
                          const SizedBox(width: 8),
                          Icon(
                            trend >= 0 ? Icons.trending_up : Icons.trending_down,
                            color: trend >= 0 ? Colors.green : Theme.of(context).colorScheme.error,
                            size: 18,
                          ),
                          Text('${(trend * 100).round()}%'),
                        ],
                      ],
                    ),
                    onTap: () => _openExercise(context, widget.stores, e),
                  );
                }(),
            ],
          ),
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
    final recent = [
      for (final p in prEvents(sessions, loadType))
        if (p.workout.startedAt.isAfter(since)) p,
    ];
    (String?, String) key(String id) => (d.exercises[id]?.libraryId, d.exercises[id]?.name ?? '');
    final ids = sessions.keys.toList()..sort((a, b) => byMainLiftThenName(key(a), key(b)));
    bool isPopular(String id) => mainLiftRank(d.exercises[id]?.libraryId) < mainLifts.length;
    return _page([
      TileGroup(
        title: 'PRs in the last 30 days',
        children: [
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
        ],
      ),
      if (ids.isEmpty)
        const TileGroup(
          title: 'All-time bests',
          children: [ListTile(title: Text('No records yet'))],
        ),
      for (final (title, group) in [('Popular', ids.where(isPopular)), ('All', ids.where((id) => !isPopular(id)))])
        if (group.isNotEmpty)
          TileGroup(
            title: title,
            children: [
              for (final id in group)
                ListTile(
                  title: Text(d.exercises[id]?.name ?? '…'),
                  subtitle: Text(
                    [
                      for (final MapEntry(:key, :value) in records(loadType(id), [
                        for (final (_, s) in sessions[id]!) s,
                      ]).entries)
                        '$key ${fmtNum(value)}',
                    ].join(' · '),
                  ),
                  onTap: () => _openExercise(context, stores, d.exercises[id]),
                ),
            ],
          ),
      TileGroup(
        children: [
          ListTile(
            leading: const IconTile(Icons.directions_run),
            title: const Text('Cardio stats'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => CardioStatsScreen(cardio: stores.cardio))),
          ),
        ],
      ),
    ]);
  }
}

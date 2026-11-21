import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/cardio.dart';
import '../../data/db.dart';
import '../../data/health_connect.dart';
import '../../data/recording.dart' show drawsRoute;
import '../../data/running.dart';
import '../cardio/activity_timer.dart';
import '../cardio/run_page.dart';
import '../core/chart_axis.dart';
import '../core/theme.dart';
import '../health/fitbit_screen.dart';
import '../import/strava_import_screen.dart';
import '../routines/start.dart';
import 'goals_section.dart';
import 'race_predictor.dart';
import 'record_screen.dart';
import 'running_records.dart';
import 'training_log.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _km(double km) => '${km.toStringAsFixed(km < 100 ? 1 : 0)} km';

String _time(int sec) {
  final h = sec ~/ 3600, m = (sec % 3600) ~/ 60, s = sec % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// The Running tab: top tabs Runs, Progress and Records.
class RunningTab extends StatefulWidget {
  const RunningTab({super.key, required this.stores, this.health});

  final Stores stores;
  final HealthConnect? health; // offers Check Fitbit now once connected

  @override
  State<RunningTab> createState() => _RunningTabState();
}

class _RunningTabState extends State<RunningTab> {
  late final Stream<List<CardioData>> _runs = widget.stores.cardio.watchAll().map(runsOf);

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Column(children: [
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            tabs: [Tab(text: 'Runs'), Tab(text: 'Progress'), Tab(text: 'Records')],
          ),
          Expanded(
            child: TabBarView(children: [
              _RunsPage(stores: widget.stores, runs: _runs, health: widget.health),
              _ProgressPage(stores: widget.stores, store: widget.stores.cardio, runs: _runs),
              RunningRecords(stores: widget.stores, runs: _runs),
            ]),
          ),
        ]),
      );
}

class _RunsPage extends StatelessWidget {
  const _RunsPage({required this.stores, required this.runs, this.health});

  final Stores stores;
  final Stream<List<CardioData>> runs;
  final HealthConnect? health;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<CardioData>>(
        stream: runs,
        builder: (context, snap) {
          final all = snap.data;
          if (all == null) return const Center(child: CircularProgressIndicator());
          final s = runSummary(all, DateTime.now());
          final theme = Theme.of(context);
          Widget row(String label, RunTotals t) => ListTile(
                title: Text(label),
                subtitle: Text('${_time(t.sec)} · ${t.count} ${t.count == 1 ? 'Run' : 'Runs'}'),
                trailing: Text(_km(t.km), style: theme.textTheme.titleMedium),
              );
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: ListView(children: [
                RecordingBanner(stores: stores),
                TileGroup(children: [
                  ListTile(
                    leading: const IconTile(Icons.fiber_manual_record),
                    title: const Text('Record run'),
                    subtitle: const Text('Outdoor, with GPS'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => openRecorder(context, stores),
                  ),
                  ListTile(
                    leading: const IconTile(Icons.directions_run),
                    title: const Text('Record treadmill run'),
                    subtitle: const Text('Steps, then check the distance'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => openRecorder(context, stores, type: 'treadmill'),
                  ),
                ]),
                TileGroup(title: 'This week', children: [
                  ListTile(
                    title: Text(_km(s.week.km), style: theme.textTheme.headlineMedium),
                    subtitle: Text('${_time(s.week.sec)} · ${s.week.count} ${s.week.count == 1 ? 'Run' : 'Runs'}\nLast 12 weeks: ${_km(s.avgWeekKm12)} a week'),
                    isThreeLine: true,
                  ),
                ]),
                TileGroup(title: 'Totals', children: [
                  row('This month', s.month),
                  row('This year', s.year),
                  row('All time', s.all),
                ]),
                TileGroup(children: [
                  ListTile(
                    leading: const IconTile(Icons.file_download),
                    title: const Text('Import runs'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StravaImportScreen(cardio: stores.cardio))),
                  ),
                  if (health case final health?)
                    ValueListenableBuilder(
                      valueListenable: health.status,
                      builder: (context, status, _) => status != HcStatus.connected
                          ? const SizedBox.shrink()
                          : ListTile(
                              leading: const IconTile(Icons.watch),
                              title: const Text('Check Fitbit now'),
                              subtitle: const Text('Fill in Runs from Health Connect'),
                              onTap: () => checkFitbitNow(context, health),
                            ),
                    ),
                ]),
                TileGroup(title: 'Recent Runs', children: [
                  if (all.isEmpty) const ListTile(title: Text('No Runs yet')),
                  for (final c in all.take(20)) _runTile(context, c),
                ]),
              ]),
            ),
          );
        },
      );

  Widget _runTile(BuildContext context, CardioData c) {
    final pace = paceSecPerKm(c.distanceKm, c.durationSec);
    final route = parseRoute(c.route);
    return ListTile(
      leading: drawsRoute(c.type) && route.length >= 2
          ? RouteThumbnail(route)
          : IconTile(activityIcon(c.type)),
      title: Text('${c.distanceKm == null ? '-' : _km(c.distanceKm!)} · ${_time(c.durationSec)}'),
      subtitle: Text([MaterialLocalizations.of(context).formatMediumDate(c.startedAt), if (c.type == 'treadmill') 'Treadmill', if (pace != null) '${formatPace(pace)} /km'].join(' · ')),
      onTap: () => openRun(context, stores.cardio, c.id),
    );
  }
}

/// A small, still OpenStreetMap map of the route (tiles cached on the phone), for the Runs list.
class RouteThumbnail extends StatelessWidget {
  const RouteThumbnail(this.points, {super.key, this.size = 52});

  final List<(double, double)> points;
  final double size;

  @override
  Widget build(BuildContext context) {
    final line = [for (final (lat, lon) in points) LatLng(lat, lon)];
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: size,
        height: size,
        child: IgnorePointer(
          child: FlutterMap(
            options: MapOptions(
              initialCameraFit: CameraFit.coordinates(coordinates: line, padding: const EdgeInsets.all(8)),
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
            ),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'timburr'),
              PolylineLayer(polylines: [Polyline(points: line, color: Theme.of(context).colorScheme.primary, strokeWidth: 3, borderColor: Colors.black87, borderStrokeWidth: 1.5)]),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressPage extends StatefulWidget {
  const _ProgressPage({required this.stores, required this.store, required this.runs});

  final Stores stores;
  final CardioStore store;
  final Stream<List<CardioData>> runs;

  @override
  State<_ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<_ProgressPage> {
  Period _period = Period.week;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<CardioData>>(
        stream: widget.runs,
        builder: (context, snap) {
          final all = snap.data;
          if (all == null) return const Center(child: CircularProgressIndicator());
          final series = distanceSeries(all, _period, DateTime.now(), last: switch (_period) { Period.week => 26, Period.month => 24, Period.year => null });
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                SegmentedButton<Period>(
                  segments: const [
                    ButtonSegment(value: Period.week, label: Text('Weekly')),
                    ButtonSegment(value: Period.month, label: Text('Monthly')),
                    ButtonSegment(value: Period.year, label: Text('Yearly')),
                  ],
                  selected: {_period},
                  onSelectionChanged: (s) => setState(() => _period = s.single),
                ),
                const SizedBox(height: 16),
                Text('Distance (km)', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                AspectRatio(aspectRatio: 1.6, child: DistanceChart(series, _period)),
                TrainingLog(stores: widget.stores, runs: widget.runs), // Progress sections: one line each, added below
                RaceSection(store: widget.store, runs: widget.runs),
                GoalsSection(store: widget.store, runs: widget.runs),
              ]),
            ),
          );
        },
      );
}

String _label(Period p, DateTime d) => switch (p) {
      Period.week => '${d.day}/${d.month}',
      Period.month => d.month == 1 ? '${_months[0]} ${d.year % 100}' : _months[d.month - 1],
      Period.year => '${d.year}',
    };

/// One bar per real period, empty ones included, so spacing is true to the calendar.
class DistanceChart extends StatelessWidget {
  const DistanceChart(this.series, this.period, {super.key});

  final List<({DateTime start, double km})> series;
  final Period period;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final every = (series.length / 5).ceil().clamp(1, series.length);
    return LayoutBuilder(builder: (context, box) => BarChart(BarChartData(
      gridData: const FlGridData(drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      alignment: BarChartAlignment.spaceAround,
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(getTooltipItem: (group, _, rod, _) {
          final s = series[group.x];
          final end = period == Period.week ? ' week' : '';
          return BarTooltipItem('${_label(period, s.start)}$end\n${_km(s.km)}', TextStyle(color: scheme.onSurface));
        }),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(sideTitles: axisTitles(reservedSize: 40)),
        bottomTitles: AxisTitles(
          sideTitles: axisTitles(
            reservedSize: 28,
            interval: 1,
            // Label from the newest bar back, so the current period is always named.
            show: (x) => x == x.toInt() && x >= 0 && x < series.length && (series.length - 1 - x.toInt()) % every == 0,
            label: (x) => _label(period, series[x.toInt()].start),
          ),
        ),
      ),
      barGroups: [
        for (var i = 0; i < series.length; i++)
          BarChartGroupData(x: i, barRods: [
            BarChartRodData(toY: series[i].km, color: scheme.primary, width: barWidth(box.maxWidth - 40, series.length), borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
          ]),
      ],
    )));
  }
}

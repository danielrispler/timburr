import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/cardio.dart';
import '../../data/db.dart';
import '../../data/running.dart';
import '../cardio/activity_timer.dart';
import '../cardio/run_page.dart';
import '../core/theme.dart';
import '../import/strava_import_screen.dart';
import '../routines/start.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _km(double km) => '${km.toStringAsFixed(km < 100 ? 1 : 0)} km';

String _time(int sec) {
  final h = sec ~/ 3600, m = (sec % 3600) ~/ 60, s = sec % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// The Running tab: top tabs Runs, Progress and Records.
class RunningTab extends StatefulWidget {
  const RunningTab({super.key, required this.stores});

  final Stores stores;

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
              _RunsPage(stores: widget.stores, runs: _runs),
              _ProgressPage(runs: _runs),
              const Center(child: Text('Records are coming soon')), // #61
            ]),
          ),
        ]),
      );
}

class _RunsPage extends StatelessWidget {
  const _RunsPage({required this.stores, required this.runs});

  final Stores stores;
  final Stream<List<CardioData>> runs;

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
      leading: route.length >= 2
          ? RouteThumbnail(route)
          : IconTile(activityIcon(c.type)),
      title: Text('${c.distanceKm == null ? '-' : _km(c.distanceKm!)} · ${_time(c.durationSec)}'),
      subtitle: Text([MaterialLocalizations.of(context).formatMediumDate(c.startedAt), if (c.type == 'treadmill') 'Treadmill', if (pace != null) '${formatPace(pace)} /km'].join(' · ')),
      onTap: () => openRun(context, stores.cardio, c.id),
    );
  }
}

/// A route drawn as a plain polyline, no map tiles. Longitude is scaled by cos(latitude) so the shape is not stretched.
class RouteThumbnail extends StatelessWidget {
  const RouteThumbnail(this.points, {super.key, this.size = 52});

  final List<(double, double)> points;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(16)),
      child: CustomPaint(painter: _RoutePainter(points, scheme.primary)),
    );
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter(this.points, this.color);

  final List<(double, double)> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final lats = [for (final p in points) p.$1], lons = [for (final p in points) p.$2];
    final minLat = lats.reduce((a, b) => a < b ? a : b), maxLat = lats.reduce((a, b) => a > b ? a : b);
    final minLon = lons.reduce((a, b) => a < b ? a : b), maxLon = lons.reduce((a, b) => a > b ? a : b);
    final xScale = math.cos((minLat + maxLat) / 2 * math.pi / 180);
    final w = (maxLon - minLon) * xScale, h = maxLat - minLat;
    final span = w > h ? w : h;
    if (span == 0) return;
    const pad = 8.0;
    final scale = (size.width - 2 * pad) / span;
    final dx = (size.width - w * scale) / 2, dy = (size.height - h * scale) / 2;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = dx + (points[i].$2 - minLon) * xScale * scale, y = dy + (maxLat - points[i].$1) * scale;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2..strokeJoin = StrokeJoin.round..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_RoutePainter old) => old.points != points || old.color != color;
}

class _ProgressPage extends StatefulWidget {
  const _ProgressPage({required this.runs});

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
    return BarChart(BarChartData(
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
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            interval: 1,
            getTitlesWidget: (x, meta) {
              final i = x.toInt();
              // Label from the newest bar back, so the current period is always named.
              if (i != x || i < 0 || i >= series.length || (series.length - 1 - i) % every != 0) return const SizedBox.shrink();
              return SideTitleWidget(meta: meta, child: Text(_label(period, series[i].start), style: const TextStyle(fontSize: 11)));
            },
          ),
        ),
      ),
      barGroups: [
        for (var i = 0; i < series.length; i++)
          BarChartGroupData(x: i, barRods: [
            BarChartRodData(toY: series[i].km, color: scheme.primary, width: series.length > 30 ? 6 : 12, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
          ]),
      ],
    ));
  }
}

import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/cardio.dart';
import '../../data/db.dart';
import '../../data/hr_zones.dart';
import '../../data/load.dart';
import '../../data/recording.dart' show drawsRoute;
import '../../data/run_analysis.dart';
import '../../data/settings.dart';
import '../../data/track.dart';
import '../core/chart_axis.dart';
import '../core/theme.dart';
import 'activity_timer.dart';
import 'max_hr.dart';
import 'cardio_form.dart';
import 'run_efforts.dart';

/// Opens the Run page for [id] on the nearest navigator, so a tab keeps its bottom bar and its own stack. The one way to open a Run: History and the Runs view both call it.
void openRun(BuildContext context, CardioStore store, String id) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => RunPage(store: store, id: id)));

/// One Run: map, numbers, km splits and a chart. Without a route the same page shows no map.
class RunPage extends StatelessWidget {
  const RunPage({super.key, required this.store, required this.id});

  final CardioStore store;
  final String id;

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this Run?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await store.delete(id); // the page closes itself when it sees the Run deleted
  }

  @override
  Widget build(BuildContext context) => StreamBuilder(
        stream: store.watch(id),
        builder: (context, snap) {
          final c = snap.data;
          if (c == null) return const Scaffold(body: SizedBox());
          if (c.deletedAt != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
            });
            return const Scaffold(body: SizedBox());
          }
          return Scaffold(
            appBar: AppBar(
              title: Text(c.title ?? runTitle(c.startedAt.toLocal(), treadmill: c.type == 'treadmill')),
              actions: [
                IconButton(
                    icon: const Icon(Icons.edit),
                    tooltip: 'Edit',
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CardioForm(store: store, existing: c)))),
                IconButton(icon: const Icon(Icons.delete), tooltip: 'Delete', onPressed: () => _delete(context)),
              ],
            ),
            body: StreamBuilder(
              stream: store.watchTrack(id),
              builder: (context, ts) => _RunBody(c, ts.data, store, store.settings),
            ),
          );
        },
      );
}

class _RunBody extends StatefulWidget {
  const _RunBody(this.run, this.track, this.store, this.settings);

  final CardioData run;
  final Track? track;
  final CardioStore store;
  final SettingsStore settings;

  @override
  State<_RunBody> createState() => _RunBodyState();
}

class _RunBodyState extends State<_RunBody> {
  RunMetric _metric = RunMetric.pace;

  @override
  Widget build(BuildContext context) {
    final c = widget.run, t = widget.track;
    final loc = MaterialLocalizations.of(context);
    final pace = paceSecPerKm(c.distanceKm, c.durationSec);
    final splits = t == null ? const <KmSplit>[] : splitsPerKm(t);
    final metrics = [if (t != null) for (final m in RunMetric.values) if (chartSeries(t, m).length >= 2) m];
    final metric = metrics.contains(_metric) ? _metric : metrics.firstOrNull;
    final at = c.startedAt.toLocal();
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      if (t != null && drawsRoute(c.type) && _positions(t).length >= 2) RunMap(_positions(t)),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Text('${loc.formatMediumDate(at)}, ${TimeOfDay.fromDateTime(at).format(context)} · ${activityLabel(c.type)}',
            style: Theme.of(context).textTheme.bodyMedium),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          _Stat('Distance', c.distanceKm == null ? '-' : '${c.distanceKm!.toStringAsFixed(2)} km'),
          _Stat('Moving time', formatDuration(c.durationSec)),
          _Stat('Elapsed time', c.elapsedSec == null ? '-' : formatDuration(c.elapsedSec!)),
          _Stat('Pace', pace == null ? '-' : '${formatPace(pace)} /km'),
          _Stat('Avg HR', c.avgHr?.toString() ?? '-'),
          _Stat('Max HR', c.maxHr?.toString() ?? '-'),
          StreamBuilder<AppSetting?>(
            stream: widget.settings.watch(),
            builder: (context, s) {
              final load = runLoad(c, t, effectiveMaxHr(s.data?.maxHr, s.data?.birthYear, DateTime.now()));
              return _Stat('Relative Effort', load.estimated ? '-' : load.effort.round().toString()); // no HR, no score
            },
          ),
          _Stat('Elevation gain', c.elevationGainM == null ? '-' : '${c.elevationGainM!.round()} m'),
        ]),
      ),
      if (c.notes?.isNotEmpty == true) Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 8), child: Text(c.notes!)),
      if (metric != null) ...[
        const Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, 0), child: Text('Over distance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SegmentedButton<RunMetric>(
            segments: [
              for (final m in RunMetric.values)
                ButtonSegment(value: m, label: Text(switch (m) { RunMetric.pace => 'Pace', RunMetric.hr => 'Heart rate', RunMetric.elevation => 'Elevation' }), enabled: metrics.contains(m)),
            ],
            selected: {metric},
            onSelectionChanged: (s) => setState(() => _metric = s.single),
          ),
        ),
        _MetricChart(chartSeries(t!, metric), metric),
      ],
      ZoneBar(track: t, settings: widget.settings),
      if (splits.isNotEmpty) TileGroup(title: 'Splits', children: [
        for (final s in splits)
          ListTile(
            dense: true,
            leading: SizedBox(width: 56, child: Text(s.distanceM < 1000 ? '${(s.distanceM / 1000).toStringAsFixed(2)} km' : 'km ${s.index}')),
            title: Text('${formatPace(s.paceSecPerKm)} /km'),
            trailing: Text(s.avgHr == null ? '' : '${s.avgHr} bpm'),
          ),
      ]),
      RunBestEfforts(store: widget.store, runId: c.id),
    ]);
  }
}

List<LatLng> _positions(Track t) {
  final lat = t.lat, lon = t.lon;
  if (lat == null || lon == null) return const [];
  return [for (var i = 0; i < lat.length && i < lon.length; i++) if (lat[i] != null && lon[i] != null) LatLng(lat[i]!, lon[i]!)];
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label, value;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 112,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ]),
      );
}

/// OpenStreetMap tiles (cached on the phone by flutter_map) under the route, with the start and finish marked.
class RunMap extends StatelessWidget {
  const RunMap(this.points, {super.key});

  final List<LatLng> points;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    Widget pin(Color c, IconData icon) => Container(
          decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
          child: Icon(icon, color: Colors.white, size: 16),
        );
    return SizedBox(
      height: 280,
      child: FlutterMap(
        options: MapOptions(
          initialCameraFit: CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(40)),
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag | InteractiveFlag.doubleTapZoom),
        ),
        children: [
          // OSM tile policy: identify the app. The generic name is deliberate; no personal details go in the user agent.
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'timburr'),
          PolylineLayer(polylines: [Polyline(points: points, color: color, strokeWidth: 4, borderColor: Colors.black54, borderStrokeWidth: 1)]),
          MarkerLayer(markers: [
            Marker(point: points.first, width: 24, height: 24, child: pin(Colors.green, Icons.play_arrow)),
            Marker(point: points.last, width: 24, height: 24, child: pin(Colors.red, Icons.flag)),
          ]),
          SimpleAttributionWidget(source: const Text('OpenStreetMap') /* the widget adds "flutter_map | © " */, onTap: () => unawaited(launchUrl(Uri.parse('https://www.openstreetmap.org/copyright'), mode: LaunchMode.externalApplication))),
        ],
      ),
    );
  }
}

/// Line over distance in km. Pace is drawn negated so faster is higher, and labelled back as m:ss.
class _MetricChart extends StatelessWidget {
  const _MetricChart(this.points, this.metric);

  final List<(double, double)> points;
  final RunMetric metric;

  @override
  Widget build(BuildContext context) {
    final pace = metric == RunMetric.pace;
    String label(double y) => pace ? formatPace(-y) : y.round().toString();
    // A round km step giving at most about four labels, so they never run into each other.
    final kmStep = [0.5, 1.0, 2.0, 5.0, 10.0].firstWhere((s) => points.last.$1 / s <= 4, orElse: () => 20.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 24, 8),
      child: AspectRatio(
        aspectRatio: 1.5,
        child: LineChart(LineChartData(
          gridData: const FlGridData(drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(touchTooltipData: LineTouchTooltipData(getTooltipItems: (spots) => [for (final s in spots) LineTooltipItem('${label(s.y)} at ${s.x.toStringAsFixed(2)} km', const TextStyle(color: Colors.white))])),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            bottomTitles: AxisTitles(sideTitles: axisTitles(reservedSize: 24, interval: kmStep, label: (x) => '${x.toStringAsFixed(x == x.roundToDouble() ? 0 : 1)} km')),
            leftTitles: AxisTitles(sideTitles: axisTitles(reservedSize: 44, label: label)),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (final (x, y) in points) FlSpot(x, pace ? -y : y)],
              color: Theme.of(context).colorScheme.primary,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              isCurved: false,
            ),
          ],
        )),
      ),
    );
  }
}

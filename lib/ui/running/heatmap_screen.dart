import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/db.dart';
import '../../data/running.dart';
import '../cardio/run_page.dart' show osmAttribution, osmTileLayer;
import '../core/theme.dart';

/// The Progress tile that opens the heatmap.
class HeatmapTile extends StatelessWidget {
  const HeatmapTile({super.key, required this.runs});

  final Stream<List<CardioData>> runs;

  @override
  Widget build(BuildContext context) => TileGroup(children: [
        ListTile(
          leading: const Icon(Icons.map_outlined),
          title: const Text('Heatmap'),
          subtitle: const Text('Every route you have run'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HeatmapScreen(runs: runs))),
        ),
      ]);
}

/// Every outdoor Run's route on one map, drawn faint so the paths run most often show up brightest.
/// It draws the simplified `route` stored on each Run (about 200 points), never the full tracks, and builds the lines once per change of the Runs.
class HeatmapScreen extends StatelessWidget {
  const HeatmapScreen({super.key, required this.runs});

  final Stream<List<CardioData>> runs;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Heatmap')),
        body: StreamBuilder<List<CardioData>>(
          stream: runs,
          builder: (context, snap) {
            final data = snap.data;
            if (data == null) return const Center(child: CircularProgressIndicator());
            return _HeatmapBody(data);
          },
        ),
      );
}

class _HeatmapBody extends StatefulWidget {
  const _HeatmapBody(this.runs);

  final List<CardioData> runs;

  @override
  State<_HeatmapBody> createState() => _HeatmapBodyState();
}

class _HeatmapBodyState extends State<_HeatmapBody> {
  late List<List<LatLng>> _lines = _linesOf(widget.runs);

  static List<List<LatLng>> _linesOf(List<CardioData> runs) => [
        for (final route in heatmapRoutes(runs)) [for (final (lat, lon) in route) LatLng(lat, lon)],
      ];

  @override
  void didUpdateWidget(_HeatmapBody old) {
    super.didUpdateWidget(old);
    if (!identical(old.runs, widget.runs)) _lines = _linesOf(widget.runs); // the camera stays where Daniel put it
  }

  @override
  Widget build(BuildContext context) {
    if (_lines.isEmpty) return const Center(child: Text('No routes yet. Record or import an outdoor Run.'));
    final color = Theme.of(context).colorScheme.primary.withValues(alpha: 0.25);
    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.coordinates(coordinates: [for (final l in _lines) ...l], padding: const EdgeInsets.all(40), maxZoom: 15),
      ),
      children: [
        osmTileLayer(),
        // One layer for all routes: flutter_map culls what is off screen and thins what is far away.
        PolylineLayer(polylines: [for (final l in _lines) Polyline(points: l, color: color, strokeWidth: 3, strokeCap: StrokeCap.round, strokeJoin: StrokeJoin.round)]),
        osmAttribution(),
      ],
    );
  }
}

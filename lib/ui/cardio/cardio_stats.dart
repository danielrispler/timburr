import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/cardio.dart';
import '../../data/db.dart';

String _time(int sec) {
  final h = sec ~/ 3600, m = (sec % 3600) ~/ 60, s = sec % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// Cardio sessions filtered by type and distance bucket, best time per bucket and a pace chart.
class CardioStatsScreen extends StatefulWidget {
  const CardioStatsScreen({super.key, required this.cardio});

  final CardioStore cardio;

  @override
  State<CardioStatsScreen> createState() => _CardioStatsScreenState();
}

class _CardioStatsScreenState extends State<CardioStatsScreen> {
  String _type = 'run';
  int? _bucket;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Cardio stats')),
        body: StreamBuilder<List<CardioData>>(
          stream: widget.cardio.watchAll(),
          builder: (context, snap) {
            final ofType = filterCardio(snap.data ?? [], type: _type);
            final shown = filterCardio(ofType, bucket: _bucket);
            final pace = paceSeries(shown);
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: ListView(children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final t in cardioTypes)
                        ChoiceChip(label: Text(t), selected: _type == t, onSelected: (_) => setState(() => _type = t)),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Wrap(spacing: 8, children: [
                      ChoiceChip(label: const Text('All'), selected: _bucket == null, onSelected: (_) => setState(() => _bucket = null)),
                      for (final b in distanceBuckets)
                        ChoiceChip(label: Text('~$b km'), selected: _bucket == b, onSelected: (_) => setState(() => _bucket = b)),
                    ]),
                  ),
                  for (final b in distanceBuckets)
                    ListTile(
                      leading: const Icon(Icons.emoji_events),
                      title: Text('Best ~$b km'),
                      trailing: Text(switch (bestTime(ofType, b)) {
                        final s? => '${_time(s.durationSec)} (${s.startedAt.day}/${s.startedAt.month})',
                        null => '-',
                      }),
                    ),
                  if (pace.length >= 2) _PaceChart(pace),
                  if (shown.isEmpty) const ListTile(title: Text('No sessions')),
                  for (final s in shown)
                    ListTile(
                      title: Text('${s.distanceKm} km in ${_time(s.durationSec)}'),
                      subtitle: Text('${s.startedAt.day}/${s.startedAt.month}/${s.startedAt.year}'),
                      trailing: Text(switch (paceSecPerKm(s.distanceKm, s.durationSec)) {
                        final p? => '${formatPace(p)} /km',
                        null => '',
                      }),
                    ),
                ]),
              ),
            );
          },
        ),
      );
}

class _PaceChart extends StatelessWidget {
  const _PaceChart(this.points);

  final List<(DateTime, double)> points;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 24, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Pace (min/km)', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 2,
            child: LineChart(LineChartData(
              gridData: const FlGridData(drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
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
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (y, meta) => SideTitleWidget(meta: meta, child: Text(formatPace(y))),
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

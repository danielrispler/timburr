import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/cardio.dart';
import '../../data/db.dart';
import '../../data/hr_zones.dart';
import '../../data/load.dart';
import '../../data/track.dart';
import '../core/chart_axis.dart';

const _days = 90;

/// Progress section: Fitness (42-day), Fatigue (7-day) and Form over the last 90 days, from each Run's Relative Effort.
/// Self-contained; Runs without HR count as an easy Run (see [runLoad]).
class FitnessSection extends StatelessWidget {
  const FitnessSection({super.key, required this.store, required this.runs, this.now});

  final CardioStore store;
  final Stream<List<CardioData>> runs;
  final DateTime? now;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<CardioData>>(
        stream: runs,
        builder: (context, runSnap) => StreamBuilder<Map<String, Track>>(
          stream: store.watchHrTracks(),
          builder: (context, trackSnap) => StreamBuilder<AppSetting?>(
            stream: store.settings.watch(),
            builder: (context, setSnap) {
              final all = runSnap.data, tracks = trackSnap.data;
              if (all == null || tracks == null || all.isEmpty) return const SizedBox();
              final today = now ?? DateTime.now();
              final max = effectiveMaxHr(setSnap.data?.maxHr, setSnap.data?.birthYear, today);
              final series = fitnessSeries(dailyLoads(all, tracks, max), today.subtract(const Duration(days: _days - 1)), today);
              return _FitnessChart(series);
            },
          ),
        ),
      );
}

class _FitnessChart extends StatelessWidget {
  const _FitnessChart(this.series);

  final List<LoadPoint> series;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final today = series.last;
    final colors = (fitness: scheme.primary, fatigue: scheme.error, form: scheme.tertiary);
    LineChartBarData line(double Function(LoadPoint) v, Color c) => LineChartBarData(
          spots: [for (var i = 0; i < series.length; i++) FlSpot(i.toDouble(), v(series[i]))],
          color: c,
          barWidth: 2,
          dotData: const FlDotData(show: false),
        );
    Widget value(String label, double v, Color c) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(label, style: text.bodySmall),
            ]),
            Text(v.round().toString(), key: ValueKey('today $label'), style: text.titleMedium),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Fitness & Freshness', style: text.titleSmall),
        const SizedBox(height: 8),
        Row(children: [
          value('Fitness', today.fitness, colors.fitness),
          value('Fatigue', today.fatigue, colors.fatigue),
          value('Form', today.form, colors.form),
        ]),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 1.6,
          child: LineChart(LineChartData(
            gridData: const FlGridData(drawVerticalLine: false),
            borderData: FlBorderData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(sideTitles: axisTitles(reservedSize: 40)),
              bottomTitles: AxisTitles(
                sideTitles: axisTitles(
                  reservedSize: 24,
                  interval: 1,
                  show: (x) => x == x.toInt() && x >= 0 && x < series.length && (series.length - 1 - x.toInt()) % 30 == 0,
                  label: (x) => '${series[x.toInt()].day.day}/${series[x.toInt()].day.month}',
                ),
              ),
            ),
            lineBarsData: [line((p) => p.fitness, colors.fitness), line((p) => p.fatigue, colors.fatigue), line((p) => p.form, colors.form)],
          )),
        ),
      ]),
    );
  }
}

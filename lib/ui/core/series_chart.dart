import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/records.dart';

/// Titled line chart of [points], one per session, dates along the bottom.
class SeriesChart extends StatelessWidget {
  const SeriesChart(this.title, this.points, {super.key, this.leftReserved = 40, this.leftLabel});

  final String title;
  final Series points;
  final double leftReserved;

  /// Formats left axis values; null uses fl_chart's default.
  final String Function(double)? leftLabel;

  @override
  Widget build(BuildContext context) {
    final label = leftLabel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 2,
            child: LineChart(
              LineChartData(
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
                    sideTitles: label == null
                        ? SideTitles(showTitles: true, reservedSize: leftReserved)
                        : SideTitles(
                            showTitles: true,
                            reservedSize: leftReserved,
                            getTitlesWidget: (y, meta) => SideTitleWidget(meta: meta, child: Text(label(y))),
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}

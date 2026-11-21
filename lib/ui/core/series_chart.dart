import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/records.dart';
import 'chart_axis.dart';

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
            aspectRatio: 1.6,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  bottomTitles: AxisTitles(
                    sideTitles: axisTitles(
                      reservedSize: 24,
                      interval: points.length > 4 ? (points.length / 4).ceilToDouble() : 1,
                      show: (x) => x == x.toInt() && x >= 0 && x < points.length,
                      label: (x) => '${points[x.toInt()].$1.day}/${points[x.toInt()].$1.month}',
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: axisTitles(reservedSize: leftReserved, label: label),
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

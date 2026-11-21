import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Axis labels that never collide: only values on the axis interval get one (fl_chart also labels both ends of the axis, right next to
/// their neighbours), [show] can skip more, and bottom labels at the edges are kept inside the chart.
SideTitles axisTitles({required double reservedSize, String Function(double v)? label, double? interval, bool Function(double v)? show}) => SideTitles(
      showTitles: true,
      reservedSize: reservedSize,
      interval: interval,
      getTitlesWidget: (v, meta) {
        final r = (v / meta.appliedInterval) % 1;
        if ((r > 1e-6 && r < 1 - 1e-6) || (show != null && !show(v))) return const SizedBox.shrink();
        return SideTitleWidget(
          meta: meta,
          // Only along the bottom: on the value axis it would pull the end labels off their gridlines.
          fitInside: meta.axisSide == AxisSide.bottom ? SideTitleFitInsideData.fromTitleMeta(meta) : SideTitleFitInsideData.disable(),
          child: Text(label?.call(v) ?? meta.formattedValue, style: const TextStyle(fontSize: 12)),
        );
      },
    );

/// A bar width that leaves a gap between [count] bars across [width].
double barWidth(double width, int count) => (width / count * 0.6).clamp(2, 16);

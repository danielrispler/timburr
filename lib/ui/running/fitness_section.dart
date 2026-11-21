import 'dart:async';

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
///
/// It subscribes once, and decodes the HR tracks into Relative Efforts only when the tracks or Max HR change, so a rebuild
/// or a new Run never re-reads every track.
class FitnessSection extends StatefulWidget {
  const FitnessSection({super.key, required this.store, required this.runs, this.now});

  final CardioStore store;
  final Stream<List<CardioData>> runs;
  final DateTime? now;

  @override
  State<FitnessSection> createState() => _FitnessSectionState();
}

class _FitnessSectionState extends State<FitnessSection> {
  final _subs = <StreamSubscription<Object?>>[];
  List<CardioData>? _runs;
  Map<String, Track>? _tracks;
  AppSetting? _settings;
  bool _settingsIn = false;
  Map<String, double?>? _efforts; // Relative Effort of each Run with an HR track; null = to recompute
  List<LoadPoint>? _series;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(FitnessSection old) {
    super.didUpdateWidget(old);
    if (old.runs != widget.runs || old.store != widget.store) _listen();
  }

  void _listen() {
    _cancel();
    _subs.addAll([
      widget.runs.listen((r) => _update(() => _runs = r)),
      widget.store.watchHrTracks().listen((t) => _update(() {
            _tracks = t;
            _efforts = null;
          })),
      widget.store.settings.watch().listen((s) => _update(() {
            _settings = s;
            _settingsIn = true;
            _efforts = null;
          })),
    ]);
  }

  void _update(void Function() change) {
    change();
    final all = _runs, tracks = _tracks;
    if (all == null || tracks == null || !_settingsIn) return;
    final today = widget.now ?? DateTime.now();
    final max = effectiveMaxHr(_settings?.maxHr, _settings?.birthYear, today);
    final efforts = _efforts ??= {for (final e in tracks.entries) e.key: relativeEffort(zoneSeconds(e.value, max))};
    final loads = [for (final r in all) (r.startedAt, efforts[r.id] ?? runLoad(r, null, max).effort)];
    setState(() => _series = all.isEmpty ? null : fitnessSeries(loads, today.subtract(const Duration(days: _days - 1)), today));
  }

  void _cancel() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _series == null ? const SizedBox() : _FitnessChart(_series!);
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

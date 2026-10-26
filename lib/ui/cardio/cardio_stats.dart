import 'package:flutter/material.dart';

import '../../data/cardio.dart';
import '../../data/db.dart';
import '../core/series_chart.dart';
import '../core/theme.dart';

String _time(int sec) {
  final h = sec ~/ 3600, m = (sec % 3600) ~/ 60, s = sec % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// Cardio sessions filtered by type and distance bucket, best time per bucket and a pace chart; sports show weekly totals.
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
                  if (!hasDistance(_type))
                    TileGroup(title: 'Per week', children: [
                      if (ofType.isEmpty) const ListTile(title: Text('No sessions')),
                      for (final (monday, sec, n) in weeklyTotals(ofType).reversed)
                        ListTile(
                          title: Text('Week of ${monday.day}/${monday.month}/${monday.year}'),
                          trailing: Text('${_time(sec)} · $n ${n == 1 ? 'session' : 'sessions'}'),
                        ),
                    ])
                  else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Wrap(spacing: 8, children: [
                      ChoiceChip(label: const Text('All'), selected: _bucket == null, onSelected: (_) => setState(() => _bucket = null)),
                      for (final b in distanceBuckets)
                        ChoiceChip(label: Text('~$b km'), selected: _bucket == b, onSelected: (_) => setState(() => _bucket = b)),
                    ]),
                  ),
                  TileGroup(title: 'Best times', children: [
                  for (final b in distanceBuckets)
                    ListTile(
                      leading: const IconTile(Icons.emoji_events),
                      title: Text('Best ~$b km'),
                      trailing: Text(switch (bestTime(ofType, b)) {
                        final s? => '${_time(s.durationSec)} (${s.startedAt.day}/${s.startedAt.month})',
                        null => '-',
                      }),
                    ),
                  ]),
                  if (pace.length >= 2) SeriesChart('Pace (min/km)', pace, leftLabel: formatPace),
                  TileGroup(title: 'Sessions', children: [
                  if (shown.isEmpty) const ListTile(title: Text('No sessions')),
                  for (final s in shown)
                    ListTile(
                      title: Text('${s.distanceKm ?? '-'} km in ${_time(s.durationSec)}'),
                      subtitle: Text('${s.startedAt.day}/${s.startedAt.month}/${s.startedAt.year}'),
                      trailing: Text(switch (paceSecPerKm(s.distanceKm, s.durationSec)) {
                        final p? => '${formatPace(p)} /km',
                        null => '',
                      }),
                    ),
                  ]),
                  ],
                ]),
              ),
            );
          },
        ),
      );
}


import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../../data/cardio.dart';
import '../../data/catalog.dart';
import '../../data/db.dart';
import '../../data/workouts.dart';
import '../cardio/cardio_form.dart';
import '../workouts/workout_screen.dart';

enum _Type { all, strength, cardio }

/// Finished workouts and cardio by date, newest first, with a type filter.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.workouts, required this.cardio, required this.catalog});

  final WorkoutStore workouts;
  final CardioStore cardio;
  final Catalog catalog;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  _Type _type = _Type.all;
  late final _history = widget.workouts.watchHistory();
  late final _cardio = widget.cardio.watchAll();

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: SegmentedButton<_Type>(
          segments: const [
            ButtonSegment(value: _Type.all, label: Text('All')),
            ButtonSegment(value: _Type.strength, label: Text('Strength')),
            ButtonSegment(value: _Type.cardio, label: Text('Cardio')),
          ],
          selected: {_type},
          onSelectionChanged: (s) => setState(() => _type = s.single),
        ),
      ),
      Expanded(
        child: StreamBuilder(
          stream: _history,
          builder: (context, ws) => StreamBuilder(
            stream: _cardio,
            builder: (context, cs) {
              final items = mergeHistory(ws.data ?? const [], cs.data ?? const [],
                  strength: _type != _Type.cardio, cardio: _type != _Type.strength);
              if (items.isEmpty) return const Center(child: Text('No finished sessions yet'));
              // shortcut: one group builds every tile eagerly, switch to per-month lazy groups if history gets long.
              return ListView(children: [
                TileGroup(children: [
                  for (final item in items)
                    switch (item) {
                      final Workout w => _workoutTile(context, w),
                      final c => _cardioTile(context, c as CardioData),
                    },
                ]),
              ]);
            },
          ),
        ),
      ),
    ]);
  }

  String _when(BuildContext context, DateTime at) =>
      '${MaterialLocalizations.of(context).formatMediumDate(at)}, ${TimeOfDay.fromDateTime(at).format(context)}';

  Widget _workoutTile(BuildContext context, Workout w) {
    final mins = w.finishedAt!.difference(w.startedAt).inMinutes;
    return ListTile(
      leading: const IconTile(Icons.fitness_center),
      title: Text(_when(context, w.startedAt)),
      subtitle: Text(w.notes?.isNotEmpty == true ? '$mins min · ${w.notes}' : '$mins min',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => WorkoutScreen(store: widget.workouts, catalog: widget.catalog, workoutId: w.id))),
    );
  }

  Widget _cardioTile(BuildContext context, CardioData c) {
    final pace = paceSecPerKm(c.distanceKm, c.durationSec);
    return ListTile(
      leading: const IconTile(Icons.directions_run),
      title: Text(_when(context, c.startedAt)),
      subtitle: Text(
          '${c.type} · ${c.distanceKm} km · ${c.durationSec ~/ 60} min${pace == null ? '' : ' · ${formatPace(pace)} /km'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => CardioForm(store: widget.cardio, existing: c))),
    );
  }
}

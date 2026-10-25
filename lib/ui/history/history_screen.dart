import 'package:flutter/material.dart';

import '../../data/cardio.dart';
import '../../data/db.dart';
import '../routines/start.dart';
import '../core/theme.dart';
import '../cardio/activity_timer.dart';
import '../cardio/cardio_form.dart';
import '../workouts/workout_screen.dart';

enum _Type { all, strength, cardio }

/// Finished workouts and cardio by date, newest first, with a type filter.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.stores});

  final Stores stores;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  _Type _type = _Type.all;
  late final _history = widget.stores.workouts.watchHistory();
  late final _cardio = widget.stores.cardio.watchAll();
  late final _routines = widget.stores.routines.watchRoutines();

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
            builder: (context, cs) => StreamBuilder(
              stream: _routines,
              builder: (context, rs) {
              final names = {for (final r in rs.data ?? const <Routine>[]) r.id: r.name};
              final items = mergeHistory(ws.data ?? const [], cs.data ?? const [],
                  strength: _type != _Type.cardio, cardio: _type != _Type.strength);
              if (items.isEmpty) return const Center(child: Text('No finished sessions yet'));
              // shortcut: one group builds every tile eagerly, switch to per-month lazy groups if history gets long.
              return ListView(children: [
                TileGroup(children: [
                  for (final item in items)
                    switch (item) {
                      final Workout w => _workoutTile(context, w, names[w.routineId] ?? 'Workout'),
                      final c => _cardioTile(context, c as CardioData),
                    },
                ]),
              ]);
              },
            ),
          ),
        ),
      ),
    ]);
  }

  String _when(BuildContext context, DateTime at) =>
      '${MaterialLocalizations.of(context).formatMediumDate(at)}, ${TimeOfDay.fromDateTime(at).format(context)}';

  Widget _workoutTile(BuildContext context, Workout w, String name) {
    final mins = w.finishedAt!.difference(w.startedAt).inMinutes;
    return ListTile(
      leading: const IconTile(Icons.fitness_center),
      title: Text(name),
      subtitle: Text([_when(context, w.startedAt), '$mins min', if (w.notes?.isNotEmpty == true) w.notes].join(' · '),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
          builder: (_) => WorkoutScreen(store: widget.stores.workouts, catalog: widget.stores.catalog, workoutId: w.id))),
    );
  }

  Widget _cardioTile(BuildContext context, CardioData c) {
    final pace = paceSecPerKm(c.distanceKm, c.durationSec);
    return ListTile(
      leading: IconTile(activityIcon(c.type)),
      title: Text(activityLabel(c.type)),
      subtitle: Text(
          [_when(context, c.startedAt), if (c.distanceKm != null) '${c.distanceKm} km', '${c.durationSec ~/ 60} min', if (pace != null) '${formatPace(pace)} /km'].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => CardioForm(store: widget.stores.cardio, existing: c))),
    );
  }
}

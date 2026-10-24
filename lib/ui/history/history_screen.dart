import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../data/workouts.dart';
import '../workouts/workout_screen.dart';

enum _Type { all, strength, cardio }

/// Finished sessions by date, newest first. Cardio (#16) adds its own stream and tiles here.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.workouts, required this.catalog});

  final WorkoutStore workouts;
  final Catalog catalog;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  _Type _type = _Type.all;
  late final _history = widget.workouts.watchHistory();

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(8),
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
          builder: (context, snap) {
            final items = _type == _Type.cardio ? const [] : snap.data ?? const [];
            if (items.isEmpty) return const Center(child: Text('No finished sessions yet'));
            return ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, i) {
                final w = items[i];
                final mins = w.finishedAt!.difference(w.startedAt).inMinutes;
                return ListTile(
                  leading: const Icon(Icons.fitness_center),
                  title: Text(
                      '${loc.formatMediumDate(w.startedAt)}, ${TimeOfDay.fromDateTime(w.startedAt).format(context)}'),
                  subtitle: Text(w.notes?.isNotEmpty == true ? '$mins min · ${w.notes}' : '$mins min',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          WorkoutScreen(store: widget.workouts, catalog: widget.catalog, workoutId: w.id))),
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}

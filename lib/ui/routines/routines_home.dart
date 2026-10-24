import 'package:flutter/material.dart';

import '../../data/cardio.dart';
import '../../data/catalog.dart';
import '../../data/db.dart';
import '../../data/routines.dart';
import '../../data/workouts.dart';
import '../cardio/cardio_form.dart';
import '../workouts/workout_screen.dart';
import 'routine_editor.dart';

/// Home tab: the routines list (reads the local store, so it works offline) plus "New routine".
class RoutinesHome extends StatelessWidget {
  const RoutinesHome({super.key, required this.store, required this.catalog, required this.workouts, required this.cardio});

  final RoutineStore store;
  final Catalog catalog;
  final WorkoutStore workouts;
  final CardioStore cardio;

  void _open(BuildContext context, String id) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => RoutineEditor(store: store, catalog: catalog, routineId: id)));

  void _workout(BuildContext context, String id) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => WorkoutScreen(store: workouts, catalog: catalog, workoutId: id)));

  Future<void> _start(BuildContext context, {String? routineId}) async {
    final id = await workouts.start(routineId: routineId);
    if (context.mounted) _workout(context, id);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: const Text('New routine'),
          onPressed: () async {
            final id = await store.create('New routine');
            if (context.mounted) _open(context, id);
          },
        ),
        body: StreamBuilder<List<Routine>>(
          stream: store.watchRoutines(),
          builder: (context, snap) {
            final routines = snap.data;
            if (routines == null) return const Center(child: CircularProgressIndicator());
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    StreamBuilder<Workout?>(
                      stream: workouts.watchActive(),
                      builder: (context, snap) {
                        final w = snap.data;
                        return w == null
                            ? ListTile(
                                leading: const Icon(Icons.play_arrow),
                                title: const Text('Start empty workout'),
                                onTap: () => _start(context),
                              )
                            : Card(
                                margin: const EdgeInsets.all(12),
                                child: ListTile(
                                  leading: const Icon(Icons.timer),
                                  title: const Text('Workout in progress'),
                                  subtitle: const Text('Tap to resume'),
                                  onTap: () => _workout(context, w.id),
                                ),
                              );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.directions_run),
                      title: const Text('Log cardio'),
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => CardioForm(store: cardio))),
                    ),
                    const Divider(),
                    if (routines.isEmpty) const ListTile(title: Text('No routines yet')),
                    for (final r in routines)
                      ListTile(
                        title: Text(r.name),
                        subtitle: r.stickyNote == null || r.stickyNote!.isEmpty ? null : Text(r.stickyNote!),
                        leading: IconButton(
                            icon: const Icon(Icons.play_circle),
                            tooltip: 'Start ${r.name}',
                            onPressed: () => _start(context, routineId: r.id)),
                        trailing: const Icon(Icons.edit),
                        onTap: () => _open(context, r.id),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      );
}

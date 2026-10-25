import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../backup/backup_screen.dart';
import '../core/theme.dart';
import '../workouts/workout_screen.dart';
import 'routine_editor.dart';
import 'start.dart';

/// Home tab: backup reminder, the workout in progress, and the big "Start workout" button.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.stores});

  final Stores stores;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
            // No engine here: restored rows go up with the next periodic sync.
            BackupReminderCard(
              onOpen: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => BackupScreen(db: stores.catalog.db, engine: null))),
            ),
            StreamBuilder<Workout?>(
              stream: stores.workouts.watchActive(),
              builder: (context, snap) => snap.data == null
                  ? const SizedBox.shrink()
                  : TileGroup(title: 'Today', children: [
                      ListTile(
                        leading: const IconTile(Icons.timer),
                        title: const Text('Workout in progress'),
                        subtitle: const Text('Tap to resume'),
                        onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
                            builder: (_) => WorkoutScreen(store: stores.workouts, catalog: stores.catalog, workoutId: snap.data!.id))),
                      ),
                    ]),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start workout'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StartWorkoutScreen(stores: stores))),
              ),
            ),
          ]),
        ),
      );
}

/// Workouts tab: the saved workouts (reads the local store, so it works offline) plus "New workout".
class WorkoutsTab extends StatelessWidget {
  const WorkoutsTab({super.key, required this.stores});

  final Stores stores;

  void _open(BuildContext context, String id, {bool isNew = false}) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => RoutineEditor(stores: stores, routineId: id, isNew: isNew)));

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: const Text('New workout'),
          onPressed: () async {
            final id = await stores.routines.create('New workout');
            if (context.mounted) _open(context, id, isNew: true);
          },
        ),
        body: StreamBuilder<List<Routine>>(
          stream: stores.routines.watchRoutines(),
          builder: (context, snap) {
            final routines = snap.data;
            if (routines == null) return const Center(child: CircularProgressIndicator());
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: ListView(padding: const EdgeInsets.only(bottom: 88), children: [
                  TileGroup(children: [
                    if (routines.isEmpty) const ListTile(title: Text('No saved workouts yet')),
                    for (final r in routines)
                      ListTile(
                        leading: const IconTile(Icons.fitness_center),
                        title: Text(r.name),
                        subtitle: r.stickyNote == null || r.stickyNote!.isEmpty ? null : Text(r.stickyNote!),
                        onTap: () => _open(context, r.id),
                        trailing: PopupMenuButton<String>(
                          onSelected: (a) async {
                            if (a == 'start') {
                              final now = await askWhen(context, r.name);
                              if (now != null && context.mounted) await startStrength(context, stores, routineId: r.id, now: now);
                            } else {
                              final copy = await stores.routines.duplicate(r.id);
                              if (context.mounted) _open(context, copy);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'start', child: Text('Start')),
                            PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                          ],
                        ),
                      ),
                  ]),
                ]),
              ),
            );
          },
        ),
      );
}

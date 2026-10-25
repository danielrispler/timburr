import 'package:flutter/material.dart';

import '../../data/cardio.dart';
import '../../data/catalog.dart';
import '../../data/db.dart';
import '../../data/routines.dart';
import '../../data/workouts.dart';
import '../cardio/activity_timer.dart';
import '../cardio/cardio_form.dart';
import '../core/theme.dart';
import '../workouts/workout_screen.dart';

/// Stores the start flow needs, passed down together.
typedef Stores = ({RoutineStore routines, WorkoutStore workouts, CardioStore cardio, Catalog catalog});

/// Date then time picker; null when cancelled.
Future<DateTime?> pickDateTime(BuildContext context, DateTime initial) async {
  final d = await showDatePicker(
      context: context, initialDate: initial, firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 1)));
  if (d == null || !context.mounted) return null;
  final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
  if (t == null) return null;
  return DateTime(d.year, d.month, d.day, t.hour, t.minute);
}

/// "Start now" opens the live workout; "I did it" asks when, then saves it as done and opens it for edits.
Future<void> startStrength(BuildContext context, Stores s, {String? routineId, required bool now}) async {
  final nav = Navigator.of(context, rootNavigator: true);
  void open(String id) =>
      nav.push(MaterialPageRoute(builder: (_) => WorkoutScreen(store: s.workouts, catalog: s.catalog, workoutId: id)));
  if (now) {
    if (await s.workouts.active() case final w?) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Finish the workout in progress first.')));
      }
      return open(w.id);
    }
    return open(await s.workouts.start(routineId: routineId));
  }
  final sets = routineId == null ? 0 : (await s.routines.plan(routineId)).fold(0, (n, p) => n + p.sets.length);
  if (!context.mounted) return;
  final at = await pickDateTime(context, DateTime.now().subtract(estimateDuration(sets)));
  if (at != null) open(await s.workouts.start(routineId: routineId, at: at, done: true));
}

void startActivity(BuildContext context, Stores s, String type, {required bool now}) => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => now ? ActivityTimer(store: s.cardio, type: type) : CardioForm(store: s.cardio, type: type)));

/// Bottom sheet: Start now / I did it. Returns true for now, false for done, null when dismissed.
Future<bool?> askWhen(BuildContext context, String title) => showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(title, style: Theme.of(context).textTheme.titleLarge)),
          ListTile(leading: const Icon(Icons.play_arrow), title: const Text('Start now'), onTap: () => Navigator.pop(context, true)),
          ListTile(leading: const Icon(Icons.check), title: const Text('I did it'), onTap: () => Navigator.pop(context, false)),
        ]),
      ),
    );

/// Saved workouts, an empty one, and the activities. Each asks Start now or I did it.
class StartWorkoutScreen extends StatelessWidget {
  const StartWorkoutScreen({super.key, required this.stores});

  final Stores stores;

  Future<void> _strength(BuildContext context, String title, String? routineId) async {
    final now = await askWhen(context, title);
    if (now != null && context.mounted) await startStrength(context, stores, routineId: routineId, now: now);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Start workout')),
        body: StreamBuilder<List<Routine>>(
          stream: stores.routines.watchRoutines(),
          builder: (context, snap) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
                TileGroup(title: 'Your workouts', children: [
                  for (final r in snap.data ?? const <Routine>[])
                    ListTile(
                      leading: const IconTile(Icons.fitness_center),
                      title: Text(r.name),
                      onTap: () => _strength(context, r.name, r.id),
                    ),
                  ListTile(
                    leading: const IconTile(Icons.add),
                    title: const Text('Empty workout'),
                    onTap: () => _strength(context, 'Empty workout', null),
                  ),
                ]),
                TileGroup(title: 'Activities', children: [
                  for (final t in cardioTypes)
                    ListTile(
                      leading: IconTile(activityIcon(t)),
                      title: Text(activityLabel(t)),
                      onTap: () async {
                        final now = await askWhen(context, activityLabel(t));
                        if (now != null && context.mounted) startActivity(context, stores, t, now: now);
                      },
                    ),
                ]),
              ]),
            ),
          ),
        ),
      );
}

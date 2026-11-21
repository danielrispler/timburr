import 'package:flutter/material.dart';

import '../../data/cardio.dart';
import '../../data/db.dart';
import '../../data/goals.dart';
import '../../data/running.dart';
import '../core/theme.dart';

/// Progress: a ring each for the weekly and yearly distance goals, and the weekly pace needed to hit the yearly one.
class GoalsSection extends StatelessWidget {
  const GoalsSection({super.key, required this.store, required this.runs, this.now});

  final CardioStore store;
  final Stream<List<CardioData>> runs;

  /// For tests; the clock otherwise.
  final DateTime? now;

  @override
  Widget build(BuildContext context) => StreamBuilder<Goal?>(
        stream: store.goals.watch(),
        builder: (context, goalSnap) => StreamBuilder<List<CardioData>>(
          stream: runs,
          builder: (context, runSnap) {
            if (goalSnap.connectionState == ConnectionState.waiting) return const SizedBox.shrink();
            final goal = goalSnap.data;
            final at = now ?? DateTime.now();
            final mine = runsOf(runSnap.data ?? const <CardioData>[]);
            final weekly = goal?.weeklyKm == null ? null : weeklyProgress(mine, goal!.weeklyKm!, at);
            final yearly = goal?.yearlyKm == null ? null : yearlyProgress(mine, goal!.yearlyKm!, at);
            return TileGroup(title: 'Distance goals', children: [
              if (weekly == null && yearly == null)
                ListTile(title: const Text('Set a weekly or yearly goal'), trailing: const Icon(Icons.chevron_right), onTap: () => showGoalsDialog(context, store.goals, goal))
              else ...[
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    if (weekly != null) _Ring(key: const ValueKey('weekly-ring'), label: 'This week', progress: weekly),
                    if (yearly != null) _Ring(key: const ValueKey('yearly-ring'), label: '${at.year}', progress: yearly),
                  ]),
                ),
                if (yearly != null)
                  ListTile(
                    dense: true,
                    title: Text(yearly.remainingKm == 0 ? 'Yearly goal reached' : '${weeklyPaceNeeded(yearly, at).toStringAsFixed(1)} km a week to reach it'),
                  ),
                ListTile(dense: true, title: const Text('Edit goals'), trailing: const Icon(Icons.edit, size: 18), onTap: () => showGoalsDialog(context, store.goals, goal)),
              ],
            ]);
          },
        ),
      );
}

class _Ring extends StatelessWidget {
  const _Ring({super.key, required this.label, required this.progress});

  final String label;
  final GoalProgress progress;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 110,
          height: 110,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(child: CircularProgressIndicator(value: progress.fraction.clamp(0.0, 1.0), strokeWidth: 10, backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest)),
            Text('${(progress.fraction * 100).floor()}%', style: Theme.of(context).textTheme.titleLarge),
          ]),
        ),
        const SizedBox(height: 8),
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        Text('${progress.doneKm.toStringAsFixed(1)} / ${progress.goalKm.toStringAsFixed(0)} km', style: Theme.of(context).textTheme.bodySmall),
      ]);
}

/// Sets the weekly and yearly goals in km. A blank field clears that goal.
Future<void> showGoalsDialog(BuildContext context, GoalStore goals, Goal? current) {
  String text(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.round().toString() : v.toString());
  final weekly = TextEditingController(text: text(current?.weeklyKm));
  final yearly = TextEditingController(text: text(current?.yearlyKm));
  String? error;
  return showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Distance goals'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(key: const ValueKey('weekly-goal'), controller: weekly, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Weekly (km)')),
          const SizedBox(height: 8),
          TextField(key: const ValueKey('yearly-goal'), controller: yearly, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Yearly (km)', errorText: error)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              double? parse(String s) => s.trim().isEmpty ? null : double.tryParse(s.trim().replaceAll(',', '.'));
              final w = parse(weekly.text), y = parse(yearly.text);
              final bad = (weekly.text.trim().isNotEmpty && (w == null || w <= 0)) || (yearly.text.trim().isNotEmpty && (y == null || y <= 0));
              if (bad) return setState(() => error = 'Enter a distance above 0, or leave blank');
              await goals.set(weeklyKm: w, yearlyKm: y);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

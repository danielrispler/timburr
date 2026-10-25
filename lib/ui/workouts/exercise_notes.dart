import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../data/db.dart';
import '../../data/workouts.dart';

/// Outlines a superset (2+ linked cards) so it reads as one block.
class SupersetFrame extends StatelessWidget {
  const SupersetFrame({super.key, required this.size, required this.child});

  final int size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (size < 2) return child;
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Superset', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
          child,
        ],
      ),
    );
  }
}

/// Sticky note (per exercise, carries over), session note (this workout only) and the link-with-next toggle.
class ExerciseNotes extends StatefulWidget {
  const ExerciseNotes({
    super.key,
    required this.store,
    required this.catalog,
    required this.item,
    required this.stickyNote,
    required this.isLast,
  });

  final WorkoutStore store;
  final Catalog catalog;
  final WorkoutExercise item;
  final String? stickyNote;
  final bool isLast;

  @override
  State<ExerciseNotes> createState() => _ExerciseNotesState();
}

class _ExerciseNotesState extends State<ExerciseNotes> {
  late final _sticky = TextEditingController(text: widget.stickyNote ?? '');
  late final _session = TextEditingController(text: widget.item.notes ?? '');
  // Notes are rare: hidden behind an icon unless one already exists.
  late bool _open = (widget.stickyNote ?? '').isNotEmpty || (widget.item.notes ?? '').isNotEmpty;

  @override
  void didUpdateWidget(ExerciseNotes old) {
    super.didUpdateWidget(old);
    // The catalog entry loads after the first build.
    if (old.stickyNote == null && widget.stickyNote != null && _sticky.text.isEmpty) {
      _sticky.text = widget.stickyNote!;
      if (_sticky.text.isNotEmpty) setState(() => _open = true);
    }
  }

  @override
  void dispose() {
    _sticky.dispose();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.item;
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 4),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(_open ? Icons.edit_note : Icons.note_add_outlined),
                tooltip: _open ? 'Hide notes' : 'Add note',
                onPressed: () => setState(() => _open = !_open),
              ),
              if (!widget.isLast)
                IconButton(
                  icon: const Icon(Icons.link),
                  isSelected: e.supersetWithNext,
                  selectedIcon: Icon(Icons.link, color: Theme.of(context).colorScheme.primary),
                  tooltip: e.supersetWithNext ? 'Unlink from next (superset)' : 'Link with next (superset)',
                  onPressed: () => widget.store.saveExercise(e.copyWith(supersetWithNext: !e.supersetWithNext)),
                ),
            ],
          ),
          if (_open) ...[
            TextField(
              controller: _sticky,
              maxLines: null,
              style: const TextStyle(fontStyle: FontStyle.italic),
              decoration: const InputDecoration(labelText: 'Sticky note (every workout)', isDense: true),
              onChanged: (v) => widget.catalog.setStickyNote(e.exerciseId, v.isEmpty ? null : v),
            ),
            TextField(
              controller: _session,
              maxLines: null,
              decoration: const InputDecoration(labelText: 'Session note', isDense: true),
              // Saves the latest row so a reorder in between is not undone.
              onChanged: (v) async {
                final now = (await widget.store.watchExercises(e.workoutId).first).firstWhere((x) => x.id == e.id);
                await widget.store.saveExercise(now.copyWith(notes: Value(v.isEmpty ? null : v)));
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// The routine's sticky note, shown when the workout came from a routine.
class RoutineNote extends StatelessWidget {
  const RoutineNote({super.key, required this.store, required this.routineId});

  final WorkoutStore store;
  final String? routineId;

  @override
  Widget build(BuildContext context) {
    final id = routineId;
    if (id == null) return const SizedBox.shrink();
    return FutureBuilder<String?>(
      future: store.routineStickyNote(id),
      builder: (context, s) {
        final note = s.data;
        if (note == null || note.isEmpty) return const SizedBox.shrink();
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.sticky_note_2_outlined),
          title: Text(note, style: const TextStyle(fontStyle: FontStyle.italic)),
        );
      },
    );
  }
}
